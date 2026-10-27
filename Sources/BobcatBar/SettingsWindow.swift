import AppKit
import SwiftUI

/// Settings: checkboxes for the built-in links and apps, and the Orgs list.
/// Every change is written to config.json straight away.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published var newOrgName = ""
    @Published var newOrgURL = ""
    private let onSave: () -> Void

    init(config: Config, onSave: @escaping () -> Void) {
        self.config = config
        self.onSave = onSave
    }

    func binding(for item: Catalog.Item) -> Binding<Bool> {
        Binding(
            get: { Catalog.isIncluded(item, in: self.config) },
            set: { on in
                Catalog.set(item, included: on, in: &self.config)
                self.save()
            })
    }

    var orgs: [Config.Link] {
        config.sections.first { $0.name == Config.orgsName }?.items ?? []
    }

    var canAddOrg: Bool {
        !newOrgName.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: normalizedNewURL)?.host != nil
    }

    private var normalizedNewURL: String {
        let u = newOrgURL.trimmingCharacters(in: .whitespaces)
        return u.contains("://") ? u : "https://" + u
    }

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

    func removeOrg(_ name: String) {
        guard let i = config.sections.firstIndex(where: { $0.name == Config.orgsName }) else { return }
        config.sections[i].items.removeAll { $0.name == name }
        save()
    }

    private func save() {
        ConfigStore.save(config)
        onSave()
    }
}

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
enum SettingsWindow {
    private static var window: NSWindow?

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
