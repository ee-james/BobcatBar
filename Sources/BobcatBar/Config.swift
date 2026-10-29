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
    var notifySports: [String] = []   // sports to send notifications for (Sport.name); none = off
    var notifyStart: Bool = true   // ...30 minutes before a game
    var notifyFinal: Bool = true   // ...when a game ends
    var icon: String = "supercat"  // menu-bar icon: "supercat", "paw" or "custom" (menubar-icon.png)
    var iconColor: Bool = false    // show a custom icon in its own colors instead of as a template
    var updateCatalog: Bool = true // fetch link fixes (catalog.json) from GitHub once a day

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
        notifySports = try c.decodeIfPresent([String].self, forKey: .notifySports) ?? []
        notifyStart = try c.decodeIfPresent(Bool.self, forKey: .notifyStart) ?? true
        notifyFinal = try c.decodeIfPresent(Bool.self, forKey: .notifyFinal) ?? true
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "supercat"
        iconColor = try c.decodeIfPresent(Bool.self, forKey: .iconColor) ?? false
        updateCatalog = try c.decodeIfPresent(Bool.self, forKey: .updateCatalog) ?? true
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
 * @brief   Loads and saves config.json. A file that doesn't parse is never written
 *          over: changes go through update(), which re-reads the file first, and
 *          every save keeps the previous version as config.json.bak.
 */
enum ConfigStore {
    /**
     * @brief   The config folder, ~/.config/bobcatbar. Tests point it elsewhere.
     */
    nonisolated(unsafe) static var dir: URL =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/bobcatbar", isDirectory: true)
    /**
     * @brief   The config file, ~/.config/bobcatbar/config.json.
     */
    static var fileURL: URL { dir.appendingPathComponent("config.json") }
    /**
     * @brief   The version before the last save.
     */
    static var backupURL: URL { dir.appendingPathComponent("config.json.bak") }

    /**
     * @brief   Set when this launch wrote the starter config (a new install).
     */
    nonisolated(unsafe) static var isFirstRun = false

    /**
     * @brief   Why config.json can't be used; the message is shown in the menu and Settings.
     */
    struct Failure: Error, Equatable {
        let message: String
    }

    /**
     * @brief   Loads config.json, writing the starter config on the first run.
     *
     * @return  the config, plus an error message when the file can't be read or
     *          parsed (the starter config is used then, but never saved over it).
     */
    static func load() -> (config: Config, error: String?) {
        switch read() {
        case .success(let c): return (c, nil)
        case .failure(let f): return (.starter, f.message)
        }
    }

    /**
     * @brief   Reads config.json, writing the starter config if there isn't one.
     */
    static func read() -> Result<Config, Failure> {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return .failure(.init(message: "Could not create \(dir.path): \(error.localizedDescription)"))
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            writeStarter()
            isFirstRun = true
            return .success(.starter)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return .success(try JSONDecoder().decode(Config.self, from: data))
        } catch let e as DecodingError {
            return .failure(.init(message: "config.json has an error: \(describe(e))"))
        } catch {
            return .failure(.init(message: "config.json can't be read: \(error.localizedDescription)"))
        }
    }

    /**
     * @brief   Changes config.json: re-reads it (so edits made in an editor since are
     *          kept), applies the change and saves.
     *
     * @param   change  the edit.
     * @return  the saved config, or why the file couldn't be changed.
     */
    @discardableResult
    static func update(_ change: (inout Config) -> Void) -> Result<Config, Failure> {
        read().flatMap { current in
            var c = current
            change(&c)
            return save(c).map { c }
        }
    }

    /**
     * @brief   A modification stamp for config.json, to tell whether it changed.
     */
    static func stamp() -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let m = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(m)/\((a?[.size] as? Int) ?? -1)"
    }

    /**
     * @brief   Writes the starter config to config.json.
     */
    static func writeStarter() {
        _ = save(.starter)
    }

    /**
     * @brief   Writes a config to config.json, pretty-printed with sorted keys, after
     *          copying the current file to config.json.bak.
     *
     * @param   config  the config to save.
     */
    static func save(_ config: Config) -> Result<Void, Failure> {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        do {
            let data = try e.encode(config)
            let fm = FileManager.default
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: backupURL)
                try fm.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: .atomic)
            return .success(())
        } catch {
            return .failure(.init(message: "Could not save config.json: \(error.localizedDescription)"))
        }
    }

    /**
     * @brief   A short description of a JSON error, with where it is.
     */
    private static func describe(_ e: DecodingError) -> String {
        func path(_ c: DecodingError.Context) -> String {
            let p = c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? "." + $0.stringValue }.joined()
            return p.isEmpty ? "" : " at \(p.hasPrefix(".") ? String(p.dropFirst()) : p)"
        }
        switch e {
        case .dataCorrupted(let c):
            let detail = (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return detail ?? c.debugDescription
        case .keyNotFound(let k, let c): return "missing \"\(k.stringValue)\"" + path(c)
        case .typeMismatch(_, let c), .valueNotFound(_, let c): return c.debugDescription + path(c)
        @unknown default: return e.localizedDescription
        }
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
