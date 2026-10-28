/**
 * @file    Config.swift
 * @author  James Zeman
 * @date    10 SEP 2026
 * @brief   BobcatBar's settings: the config.json format, loading and saving it,
 *          and the starter config for a new install.
 */
import Foundation

/**
 * @brief   Everything in config.json (~/.config/bobcatbar). Unknown keys are
 *          ignored; missing keys use the defaults here.
 */
struct Config: Codable {
    var pinned: [Link] = []        // top of the menu, in the order given
    var links: [Link] = []         // sorted by name when sortLinks is true
    var apps: [AppLink] = []       // launched by app name or bundle id
    var sections: [Section] = []   // e.g. Orgs; shown between links and apps
    var sortLinks: Bool = true
    var scores: Bool = true        // the Bobcat Scores menu item (ESPN data)

    /**
     * @brief   A link: name, URL and an optional browser.
     */
    struct Link: Codable {
        var name: String
        var url: String
        var browser: String?   // "Google Chrome", "Safari" or a bundle id; nil = default browser
    }

    /**
     * @brief   An app to launch.
     */
    struct AppLink: Codable {
        var name: String
        var target: String   // app name ("Obsidian") or bundle id ("md.obsidian")
    }

    /**
     * @brief   A named group of links, shown under its name as a menu heading
     *          (no heading when the name is empty).
     */
    struct Section: Codable {
        var name: String = ""
        var sort: Bool = true   // sort the items by name
        var items: [Link] = []
    }

    /**
     * @brief   The section Settings manages as the Orgs list.
     */
    static let orgsName = "Orgs"
}

/**
 * @brief   Decoding with defaults, so a hand-trimmed config.json still loads.
 */
extension Config {
    /**
     * @brief   Reads a config, using the default for any missing key.
     *
     * @param   decoder  the JSON decoder.
     */
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pinned = try c.decodeIfPresent([Link].self, forKey: .pinned) ?? []
        links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        apps = try c.decodeIfPresent([AppLink].self, forKey: .apps) ?? []
        sections = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        sortLinks = try c.decodeIfPresent(Bool.self, forKey: .sortLinks) ?? true
        scores = try c.decodeIfPresent(Bool.self, forKey: .scores) ?? true
    }
}

/**
 * @brief   The same for sections.
 */
extension Config.Section {
    /**
     * @brief   Reads a section, using the default for any missing key.
     *
     * @param   decoder  the JSON decoder.
     */
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sort = try c.decodeIfPresent(Bool.self, forKey: .sort) ?? true
        items = try c.decodeIfPresent([Config.Link].self, forKey: .items) ?? []
    }
}

/**
 * @brief   Loads and saves config.json.
 */
enum ConfigStore {
    /**
     * @brief   The config folder, ~/.config/bobcatbar.
     */
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bobcatbar", isDirectory: true)
    }
    /**
     * @brief   The config file, ~/.config/bobcatbar/config.json.
     */
    static var fileURL: URL { dir.appendingPathComponent("config.json") }

    /**
     * @brief   Loads config.json, writing the starter config on the first run.
     *
     * @return  the config, plus an error message when the file can't be read or
     *          parsed (the starter config is used then).
     */
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

    /**
     * @brief   Writes the starter config to config.json.
     */
    static func writeStarter() {
        save(.starter)
    }

    /**
     * @brief   Writes a config to config.json, pretty-printed with sorted keys.
     *
     * @param   config  the config to save.
     */
    static func save(_ config: Config) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        guard let data = try? e.encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension Config {
    /**
     * @brief   What a new install starts with: the core Texas State links. The rest
     *          of the catalog is a checkbox away in Settings, and Orgs starts empty.
     */
    static let starter: Config = {
        var c = Config()
        for name in ["Canvas", "CatsWeb", "Navigate 360",
                     "Campus Map", "Degree Audit", "Financial Aid", "Registration", "Student Balance"] {
            if let item = Catalog.item(named: name) { Catalog.set(item, included: true, in: &c) }
        }
        return c
    }()
}
