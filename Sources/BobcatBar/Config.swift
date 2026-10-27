import Foundation

/// User-editable configuration, loaded from ~/.config/bobcatbar/config.json.
/// Additive: unknown keys ignored, missing keys use defaults.
struct Config: Codable {
    /// Kept in the given order, above everything else.
    var pinned: [Link] = []
    /// Sorted alphabetically by name at render time when `sortLinks` is true.
    var links: [Link] = []
    /// Local apps to launch (by name or bundle id).
    var apps: [AppLink] = []
    /// Extra named categories of links (e.g. "Orgs"), rendered between links and apps
    /// in the order listed here, each under its name as a heading.
    var sections: [Section] = []
    var sortLinks: Bool = true

    struct Link: Codable {
        var name: String
        var url: String
        /// Optional: open in this browser ("Google Chrome", "Safari", or a bundle id).
        /// Omit to use the system default.
        var browser: String?
    }

    struct AppLink: Codable {
        var name: String
        var target: String   // app name ("Obsidian") or bundle id ("md.obsidian")
    }

    /// A named group of links, shown under `name` as a menu heading (no heading when empty).
    struct Section: Codable {
        var name: String = ""
        /// Sorted alphabetically by name at render time when true.
        var sort: Bool = true
        var items: [Link] = []
    }

    /// The section Settings manages as the Orgs list.
    static let orgsName = "Orgs"
}

/// Missing keys fall back to the defaults above, so a hand-trimmed config.json still loads.
extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pinned = try c.decodeIfPresent([Link].self, forKey: .pinned) ?? []
        links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        apps = try c.decodeIfPresent([AppLink].self, forKey: .apps) ?? []
        sections = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        sortLinks = try c.decodeIfPresent(Bool.self, forKey: .sortLinks) ?? true
    }
}

extension Config.Section {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sort = try c.decodeIfPresent(Bool.self, forKey: .sort) ?? true
        items = try c.decodeIfPresent([Config.Link].self, forKey: .items) ?? []
    }
}

enum ConfigStore {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bobcatbar", isDirectory: true)
    }
    static var fileURL: URL { dir.appendingPathComponent("config.json") }

    static func load() -> (config: Config, error: String?) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return (.starter, "Could not create \(dir.path): \(error.localizedDescription)")
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            writeStarter()
            return (.starter, nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return (try JSONDecoder().decode(Config.self, from: data), nil)
        } catch {
            return (.starter, "config.json parse error: \(error.localizedDescription)")
        }
    }

    static func writeStarter() {
        save(.starter)
    }

    static func save(_ config: Config) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        guard let data = try? e.encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension Config {
    /// What a new install starts with: the core Texas State links. Everything else in
    /// Catalog is a checkbox away in Settings, and Orgs starts empty.
    static let starter: Config = {
        var c = Config()
        for name in ["Canvas", "CatsWeb", "Navigate 360",
                     "Campus Map", "Degree Audit", "Financial Aid", "Registration", "Student Balance"] {
            if let item = Catalog.item(named: name) { Catalog.set(item, included: true, in: &c) }
        }
        return c
    }()
}
