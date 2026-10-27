/**
 * @file    SettingsWindow.swift
 * @author  James Zeman
 * @date    27 OCT 2026
 * @brief   The Settings window: checkboxes for the built-in links and apps,
 *          and the Orgs list. Every change is saved to config.json straight away.
 */
import AppKit
import SwiftUI

@MainActor
/**
 * @brief   The config being edited, plus the new-org fields.
 */
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published var newOrgName = ""
    @Published var newOrgURL = ""
    private let onSave: () -> Void

    /**
     * @brief   Starts editing a copy of the config.
     *
     * @param   config  the current config.
     * @param   onSave  called after every save, to reload the menu.
     */
    init(config: Config, onSave: @escaping () -> Void) {
        self.config = config
        self.onSave = onSave
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
            set: { on in
                Catalog.set(item, included: on, in: &self.config)
                self.save()
            })
    }

    /**
     * @brief   The links in the Orgs section.
     *
     * @return  the Orgs links, or none if there's no Orgs section yet.
     */
    var orgs: [Config.Link] {
        config.sections.first { $0.name == Config.orgsName }?.items ?? []
    }

    /**
     * @brief   Whether the new-org fields are filled in well enough to add.
     *
     * @return  true with a name and a link that has a host.
     */
    var canAddOrg: Bool {
        !newOrgName.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: normalizedNewURL)?.host != nil
    }

    /**
     * @brief   The new org's link with https:// added if it has no scheme.
     *
     * @return  the link to save.
     */
    private var normalizedNewURL: String {
        let u = newOrgURL.trimmingCharacters(in: .whitespaces)
        return u.contains("://") ? u : "https://" + u
    }

    /**
     * @brief   Adds the new org to the Orgs section (creating it if needed) and saves.
     */
    func addOrg() {
        guard canAddOrg else { return }
        let link = Config.Link(name: newOrgName.trimmingCharacters(in: .whitespaces), url: normalizedNewURL)
        if let i = config.sections.firstIndex(where: { $0.name == Config.orgsName }) {
            config.sections[i].items.append(link)
        } else {
            config.sections.append(.init(name: Config.orgsName, sort: true, items: [link]))
        }
        newOrgName = ""
        newOrgURL = ""
        save()
    }

    /**
     * @brief   Removes an org by name and saves.
     *
     * @param   name    the org's name.
     */
    func removeOrg(_ name: String) {
        guard let i = config.sections.firstIndex(where: { $0.name == Config.orgsName }) else { return }
        config.sections[i].items.removeAll { $0.name == name }
        save()
    }

    /**
     * @brief   Writes config.json and tells the menu to reload.
     */
    private func save() {
        ConfigStore.save(config)
        onSave()
    }
}

/**
 * @brief   The Settings form: one section per catalog group, then Orgs.
 */
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            ForEach(Catalog.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(Catalog.items.filter { $0.group == group }) { item in
                        Toggle(item.name, isOn: model.binding(for: item))
                    }
                }
            }
            Section("Orgs") {
                ForEach(model.orgs, id: \.name) { org in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(org.name)
                            Text(org.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) { model.removeOrg(org.name) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(org.name)")
                    }
                }
                HStack {
                    TextField("Name", text: $model.newOrgName).frame(width: 110)
                    TextField("Link (GroupMe, Instagram, website…)", text: $model.newOrgURL)
                        .onSubmit { model.addOrg() }
                    Button("Add") { model.addOrg() }.disabled(!model.canAddOrg)
                }
            }
            Section {
                HStack {
                    Text("Other links you add to config.json are kept.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit config.json…") { NSWorkspace.shared.open(ConfigStore.fileURL) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 620)
    }
}

@MainActor
/**
 * @brief   Shows the one Settings window, reusing it when it's already open.
 */
enum SettingsWindow {
    private static var window: NSWindow?

    /**
     * @brief   Shows Settings for the given config and brings it to the front.
     *
     * @param   config  the current config.
     * @param   onSave  called after every save.
     */
    static func show(config: Config, onSave: @escaping () -> Void) {
        let model = SettingsModel(config: config, onSave: onSave)
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "BobcatBar Settings"
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
