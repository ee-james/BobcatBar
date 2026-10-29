/**
 * @file    SettingsWindow.swift
 * @author  James Zeman
 * @date    27 OCT 2026
 * @brief   The Settings window: checkboxes for the built-in links and apps, your
 *          own links, the Orgs list, and scores. Every change is saved to
 *          config.json straight away, re-reading the file first so edits made in
 *          an editor are kept.
 */
import AppKit
import SwiftUI

/**
 * @brief   Which list in config.json a link lives in.
 */
enum LinkList: Equatable {
    case pinned, links, section(String)
}

/**
 * @brief   A link being added or edited in the link sheet.
 */
struct LinkDraft: Identifiable {
    var id = UUID()
    var title: String              // sheet title, e.g. "Add Org"
    var name = ""
    var url = ""
    var pinned = false
    var allowsPin = false          // My Links can be pinned; orgs can't
    var editing: (list: LinkList, index: Int)? = nil

    /**
     * @brief   The URL with https:// added when no scheme was typed.
     */
    var normalizedURL: String {
        let u = url.trimmingCharacters(in: .whitespaces)
        return u.contains("://") ? u : "https://" + u
    }

    /**
     * @brief   Why the draft can't be saved yet, or nil when it can.
     */
    var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a name." }
        if url.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a link." }
        guard let u = URL(string: normalizedURL), let host = u.host, host.contains("."),
              ["http", "https"].contains(u.scheme?.lowercased() ?? "") else {
            return "That doesn't look like a web address."
        }
        return nil
    }
}

@MainActor
/**
 * @brief   The config being shown, kept in step with config.json.
 */
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published var error: String?
    @Published var draft: LinkDraft?
    private let onSave: () -> Void

    /**
     * @brief   Starts showing the config.
     *
     * @param   config  the current config.
     * @param   error   why config.json can't be used, if it can't; Settings is read-only then.
     * @param   onSave  called after every save, to reload the menu.
     */
    init(config: Config, error: String?, onSave: @escaping () -> Void) {
        self.config = config
        self.error = error
        self.onSave = onSave
    }

    /**
     * @brief   Re-reads config.json, e.g. when the window comes back to the front.
     */
    func reload() {
        let r = ConfigStore.load()
        config = r.config
        error = r.error
    }

    /**
     * @brief   Applies one change to config.json. If the file has an error the change
     *          is dropped and the error shown, so a broken file is never overwritten.
     *
     * @param   change  the edit.
     */
    func apply(_ change: (inout Config) -> Void) {
        switch ConfigStore.update(change) {
        case .success(let c):
            config = c
            error = nil
            onSave()
        case .failure(let f):
            error = f.message
        }
    }

    /**
     * @brief   A checkbox binding for one catalog item.
     *
     * @param   item    the catalog item.
     * @return  a binding that reads and changes the config, saving on change.
     */
    func binding(for item: Catalog.Item) -> Binding<Bool> {
        Binding(
            get: { Catalog.isIncluded(item, in: self.config) },
            set: { on in self.apply { Catalog.set(item, included: on, in: &$0) } })
    }

    /**
     * @brief   A binding for a Bool setting in the config.
     *
     * @param   key     the setting.
     * @return  a binding that saves on change.
     */
    func binding(_ key: WritableKeyPath<Config, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.config[keyPath: key] },
            set: { on in self.apply { $0[keyPath: key] = on } })
    }

    // MARK: - Your links and orgs

    /**
     * @brief   Pinned and plain links that aren't from the catalog, with where they live.
     */
    var myLinks: [(list: LinkList, index: Int, link: Config.Link)] {
        let pinned = config.pinned.enumerated().map { (list: LinkList.pinned, index: $0.offset, link: $0.element) }
        let links = config.links.enumerated().map { (list: LinkList.links, index: $0.offset, link: $0.element) }
        return (pinned + links).filter { !Catalog.isCatalogLink($0.link) }
    }

    /**
     * @brief   The Orgs section's links.
     */
    var orgs: [Config.Link] {
        config.sections.first { $0.name == Config.orgsName }?.items ?? []
    }

    /**
     * @brief   Opens the sheet to add a link of your own.
     */
    func newLink() {
        draft = LinkDraft(title: "Add Link", allowsPin: true)
    }

    /**
     * @brief   Opens the sheet to add an org.
     */
    func newOrg() {
        draft = LinkDraft(title: "Add Org")
    }

    /**
     * @brief   Opens the sheet to edit a link in place.
     *
     * @param   list    where the link lives.
     * @param   index   its position there.
     */
    func edit(_ list: LinkList, _ index: Int) {
        guard let link = Self.links(list, in: config)?[safe: index] else { return }
        let isOrg = list == .section(Config.orgsName)
        draft = LinkDraft(title: isOrg ? "Edit Org" : "Edit Link", name: link.name, url: link.url,
                          pinned: list == .pinned, allowsPin: !isOrg, editing: (list, index))
    }

    /**
     * @brief   Saves the sheet: adds the link, or replaces the one being edited
     *          (moving it between Pinned and Links if that changed).
     */
    func saveDraft() {
        guard let d = draft, d.problem == nil else { return }
        let name = d.name.trimmingCharacters(in: .whitespaces)
        let target: LinkList = d.allowsPin ? (d.pinned ? .pinned : .links) : .section(Config.orgsName)
        apply { c in
            var link = Config.Link(name: name, url: d.normalizedURL)
            if let (list, i) = d.editing, let old = Self.links(list, in: c)?[safe: i] {
                link.browser = old.browser
                Self.modify(list, in: &c) { $0.remove(at: i) }
                if list == target {
                    Self.modify(target, in: &c) { $0.insert(link, at: i) }
                    return
                }
            }
            Self.modify(target, in: &c) { $0.append(link) }
        }
        if error == nil { draft = nil }
    }

    /**
     * @brief   Removes a link by position, so two with the same name are told apart.
     *
     * @param   list    where the link lives.
     * @param   index   its position there.
     */
    func remove(_ list: LinkList, _ index: Int) {
        apply { c in Self.modify(list, in: &c) { if $0.indices.contains(index) { $0.remove(at: index) } } }
    }

    /**
     * @brief   The links in one list.
     */
    private static func links(_ list: LinkList, in c: Config) -> [Config.Link]? {
        switch list {
        case .pinned: return c.pinned
        case .links: return c.links
        case .section(let name): return c.sections.first { $0.name == name }?.items
        }
    }

    /**
     * @brief   Changes one list, creating the section if it's new.
     */
    private static func modify(_ list: LinkList, in c: inout Config, _ change: (inout [Config.Link]) -> Void) {
        switch list {
        case .pinned: change(&c.pinned)
        case .links: change(&c.links)
        case .section(let name):
            if let i = c.sections.firstIndex(where: { $0.name == name }) {
                change(&c.sections[i].items)
            } else {
                var items: [Config.Link] = []
                change(&items)
                c.sections.append(.init(name: name, sort: true, items: items))
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/**
 * @brief   The Settings form.
 */
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            if let err = model.error {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(err)
                            Text("Settings can't make changes until it's fixed. Your file hasn't been changed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    HStack {
                        Spacer()
                        Button("Edit config.json…") { NSWorkspace.shared.open(ConfigStore.fileURL) }
                        Button("Try Again") { model.reload() }
                    }
                }
            }

            Group {
                ForEach(Catalog.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(Catalog.items.filter { $0.group == group }) { item in
                            Toggle(item.name, isOn: model.binding(for: item))
                        }
                    }
                }

                Section {
                    ForEach(Array(model.myLinks.enumerated()), id: \.offset) { _, entry in
                        LinkRow(link: entry.link, pinned: entry.list == .pinned,
                                edit: { model.edit(entry.list, entry.index) },
                                remove: { model.remove(entry.list, entry.index) })
                    }
                    AddRow(title: "Add Link…") { model.newLink() }
                } header: {
                    Text("My Links")
                } footer: {
                    Text("Any site you like. Pin one to keep it at the top of the menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach(Array(model.orgs.enumerated()), id: \.offset) { i, org in
                        LinkRow(link: org, pinned: false,
                                edit: { model.edit(.section(Config.orgsName), i) },
                                remove: { model.remove(.section(Config.orgsName), i) })
                    }
                    AddRow(title: "Add Org…") { model.newOrg() }
                } header: {
                    Text("Orgs")
                } footer: {
                    Text("Your student organizations: a GroupMe, Instagram or website link for each.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Scores") {
                    Toggle("Bobcat Scores (past week and coming week, from ESPN)", isOn: model.binding(\.scores))
                }
            }
            .disabled(model.error != nil)

            Section {
                HStack {
                    Text("Everything here is saved in config.json, along with anything you add by hand.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit config.json…") { NSWorkspace.shared.open(ConfigStore.fileURL) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .sheet(item: $model.draft) { _ in
            LinkSheet(model: model)
        }
    }
}

/**
 * @brief   One link in a list: name and address, with edit and remove buttons.
 */
struct LinkRow: View {
    let link: Config.Link
    let pinned: Bool
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(link.name)
                    if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).help("Pinned") }
                }
                Text(link.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(action: edit) { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("Edit \(link.name)")
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("Remove \(link.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }
}

/**
 * @brief   The "Add…" button at the bottom of a list.
 */
struct AddRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
    }
}

/**
 * @brief   The sheet for adding or editing a link or org.
 */
struct LinkSheet: View {
    @ObservedObject var model: SettingsModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        let draft = Binding(get: { model.draft ?? LinkDraft(title: "") }, set: { model.draft = $0 })
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.wrappedValue.title).font(.headline)
            Form {
                TextField("Name", text: draft.name, prompt: Text(draft.wrappedValue.allowsPin ? "e.g. Library" : "e.g. IEEE TXST"))
                    .focused($nameFocused)
                TextField("Link", text: draft.url, prompt: Text(draft.wrappedValue.allowsPin ? "library.txst.edu" : "groupme.com/join_group/…"))
                if draft.wrappedValue.allowsPin {
                    Toggle("Pin to the top of the menu", isOn: draft.pinned)
                }
            }
            .formStyle(.columns)
            Text(model.error ?? (showProblem ? draft.wrappedValue.problem ?? " " : " "))
                .font(.caption).foregroundStyle(model.error != nil ? .red : .secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.draft = nil }
                    .keyboardShortcut(.cancelAction)
                Button(draft.wrappedValue.editing == nil ? "Add" : "Save") { model.saveDraft() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.wrappedValue.problem != nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { nameFocused = true }
    }

    /**
     * @brief   Shows what's missing once something has been typed in both fields.
     */
    private var showProblem: Bool {
        guard let d = model.draft else { return false }
        return !d.name.isEmpty && !d.url.isEmpty
    }
}

@MainActor
/**
 * @brief   Shows the one Settings window, reusing it when it's already open.
 */
enum SettingsWindow {
    private static var window: NSWindow?
    private static var model: SettingsModel?
    private static var observer: NSObjectProtocol?

    /**
     * @brief   Shows Settings and brings it to the front.
     *
     * @param   config  the current config.
     * @param   error   why config.json can't be used, if it can't.
     * @param   onSave  called after every save.
     */
    static func show(config: Config, error: String?, onSave: @escaping () -> Void) {
        let m = SettingsModel(config: config, error: error, onSave: onSave)
        model = m
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "BobcatBar Settings"
            w.isReleasedWhenClosed = false
            window = w
            // pick up edits made in an editor while the window was in the back
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { if model?.draft == nil { model?.reload() } }
            }
        }
        window?.contentViewController = NSHostingController(rootView: SettingsView(model: m))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /**
     * @brief   Refreshes an open Settings window after config.json changed.
     */
    static func configChanged() {
        if window?.isVisible == true, model?.draft == nil { model?.reload() }
    }
}
