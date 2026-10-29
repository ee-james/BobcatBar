/**
 * @file    SettingsWindow.swift
 * @author  James Zeman
 * @date    27 OCT 2026
 * @brief   The Settings window: opening at login, the menu-bar icon, checkboxes
 *          for the built-in links and apps, your own links, the Orgs list, scores
 *          and their notifications. Every change is saved to
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
    @Published var loginEnabled = LoginItem.isEnabled
    @Published var notificationsBlocked = false
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
        loginEnabled = LoginItem.isEnabled
        checkNotifications()
    }

    // MARK: - General

    /**
     * @brief   The "Open at login" switch, read from macOS each time.
     */
    var login: Binding<Bool> {
        Binding(
            get: { self.loginEnabled },
            set: { on in
                if let e = LoginItem.set(on) { self.error = e }
                self.loginEnabled = LoginItem.isEnabled
            })
    }

    // MARK: - Menu-bar icon

    /**
     * @brief   The icon picker: supercat, paw or custom.
     */
    var icon: Binding<String> {
        Binding(
            get: { self.config.icon },
            set: { choice in
                if choice == "custom", !FileManager.default.fileExists(atPath: MenuIcon.customURL.path) {
                    self.chooseIcon()   // nothing imported yet: pick one first
                } else {
                    self.apply { $0.icon = choice }
                }
            })
    }

    /**
     * @brief   Picks an image file and makes it the menu-bar icon.
     */
    func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for the menu bar. A simple logo works best; it's shown 18 points tall."
        panel.prompt = "Use Image"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MenuIcon.importImage(from: url)
            apply { $0.icon = "custom" }
            onSave()   // the file changed even if config.json didn't
            objectWillChange.send()
        } catch let f as ConfigStore.Failure {
            error = f.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Notifications

    /**
     * @brief   A switch for notifications about one sport.
     *
     * @param   sport   the sport.
     */
    func notifies(_ sport: Sport) -> Binding<Bool> {
        Binding(
            get: { self.config.notifySports.contains(sport.name) },
            set: { on in
                self.apply { c in
                    c.notifySports.removeAll { $0 == sport.name }
                    if on { c.notifySports.append(sport.name) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkNotifications() }
            })
    }

    /**
     * @brief   Notes whether macOS has notifications turned off for BobcatBar.
     */
    func checkNotifications() {
        Task { @MainActor in
            notificationsBlocked = !(await Notifier.isAllowed())
        }
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
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            page {
                Section("General") {
                    Toggle("Open BobcatBar when you log in", isOn: model.login)
                        .disabled(LoginItem.placementProblem != nil && !model.loginEnabled)
                    if let p = LoginItem.placementProblem {
                        Text(p).font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    Picker("Menu bar icon", selection: model.icon) {
                        Text("Supercat").tag("supercat")
                        Text("Paw print").tag("paw")
                        Text("Your own…").tag("custom")
                    }
                    if model.config.icon == "custom" {
                        HStack {
                            Image(nsImage: MenuIcon.image(for: model.config))
                                .frame(minWidth: 36, minHeight: 22)
                                .padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                            Spacer()
                            Button("Choose Image…") { model.chooseIcon() }
                        }
                        Toggle("Keep its colors", isOn: model.binding(\.iconColor))
                    }
                } header: {
                    Text("Menu Bar")
                } footer: {
                    Text(model.config.icon == "custom" && model.config.iconColor
                         ? "In color, the icon looks the same on light and dark menu bars, so check it on both."
                         : "Icons follow the menu bar's light or dark look. Your own image stays on your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if let u = (NSApp.delegate as? AppDelegate)?.updater, u.isAvailable {
                        Toggle("Check for new versions daily", isOn: Binding(
                            get: { u.checksAutomatically },
                            set: { u.checksAutomatically = $0; model.objectWillChange.send() }))
                        Toggle("Install them automatically", isOn: Binding(
                            get: { u.installsAutomatically },
                            set: { u.installsAutomatically = $0; model.objectWillChange.send() }))
                            .disabled(!u.checksAutomatically)
                    }
                    Toggle("Get campus link fixes daily", isOn: model.binding(\.updateCatalog))
                } header: {
                    SectionHeader("Updates", "Both come from the BobcatBar page on GitHub. Nothing about you is sent.")
                }

                Section("About") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BobcatBar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                            Link(AppDelegate.contactEmail, destination: URL(string: "mailto:\(AppDelegate.contactEmail)")!)
                                .font(.caption)
                        }
                        Spacer()
                        Button("About BobcatBar") { (NSApp.delegate as? AppDelegate)?.showAbout(nil) }
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag("general")

            page {
                ForEach(Catalog.Group.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(Catalog.items.filter { $0.group == group }) { item in
                            Toggle(item.name, isOn: model.binding(for: item))
                        }
                    }
                }

            }
            .tabItem { Label("Campus", systemImage: "building.columns") }
            .tag("links")

            page {
                Section {
                    ForEach(Array(model.myLinks.enumerated()), id: \.offset) { _, entry in
                        LinkRow(link: entry.link, pinned: entry.list == .pinned,
                                edit: { model.edit(entry.list, entry.index) },
                                remove: { model.remove(entry.list, entry.index) })
                    }
                    AddRow(title: "Add Link…") { model.newLink() }
                } header: {
                    SectionHeader("My Links", "Any site you like. Pin one to keep it at the top of the menu.")
                }

                Section {
                    ForEach(Array(model.orgs.enumerated()), id: \.offset) { i, org in
                        LinkRow(link: org, pinned: false,
                                edit: { model.edit(.section(Config.orgsName), i) },
                                remove: { model.remove(.section(Config.orgsName), i) })
                    }
                    AddRow(title: "Add Org…") { model.newOrg() }
                } header: {
                    SectionHeader("Orgs", "Your student organizations: a GroupMe, Instagram or website link for each.")
                }
            }
            .tabItem { Label("My Links", systemImage: "link") }
            .tag("mine")

            page {
                Section {
                    Toggle("Bobcat Scores (past week and coming week, from ESPN)", isOn: model.binding(\.scores))
                } header: {
                    Text("Scores")
                }

                Section {
                    ForEach(Sport.all, id: \.self) { sport in
                        Toggle("\(sport.emoji) \(sport.name)", isOn: model.notifies(sport))
                    }
                    Toggle("30 minutes before a game", isOn: model.binding(\.notifyStart))
                        .disabled(model.config.notifySports.isEmpty)
                    Toggle("Final scores", isOn: model.binding(\.notifyFinal))
                        .disabled(model.config.notifySports.isEmpty)
                    if model.notificationsBlocked, !model.config.notifySports.isEmpty {
                        HStack {
                            Text("Notifications are turned off for BobcatBar.")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("Open Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                            }
                        }
                    }
                } header: {
                    SectionHeader("Notifications", "Pick the sports you follow. Click a notification to open the game on ESPN.")
                }
                .disabled(!model.config.scores)
            }
            .tabItem { Label("Scores", systemImage: "sportscourt") }
            .tag("scores")
        }
        .frame(width: 480, height: 600)
        .sheet(item: $model.draft) { _ in
            LinkSheet(model: model)
        }
        .onAppear { model.checkNotifications() }
    }

    /**
     * @brief   One tab: the config error (if any), its sections, and the config.json footer.
     */
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
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

            Group { content() }
                .disabled(model.error != nil)

            Section {
                HStack {
                    Text("Saved in config.json, along with anything you add by hand.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit config.json…") { NSWorkspace.shared.open(ConfigStore.fileURL) }
                }
            }
        }
        .formStyle(.grouped)
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
        HStack {
            Button(action: action) {
                Label(title, systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
    }
}

/**
 * @brief   A section heading with a line of explanation under it.
 */
struct SectionHeader: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
        }
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
