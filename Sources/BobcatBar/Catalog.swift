/**
 * @file    Catalog.swift
 * @author  James Zeman
 * @date    27 OCT 2026
 * @brief   The Texas State links and apps that Settings offers as checkboxes,
 *          and how they're matched against config.json. The list is built in and
 *          also kept in the repo as catalog.json, which BobcatBar checks daily so a
 *          dead link can be fixed without a new release (CatalogUpdater).
 */
import Foundation

/**
 * @brief   Built-in links and apps. Checking one adds it to config.json;
 *          unchecking removes the matching entry.
 */
enum Catalog {
    /**
     * @brief   Where a catalog item goes when it's checked.
     */
    enum Group: String, CaseIterable, Codable {
        case pinned, links, apps

        var title: String {
            switch self {
            case .pinned: return "Pinned (top of the menu)"
            case .links: return "Links"
            case .apps: return "Apps"
            }
        }
    }

    /**
     * @brief   One checkbox: a link (URL) or an app (name or bundle id).
     */
    struct Item: Identifiable, Codable, Equatable {
        let id: String       // stable, so renaming an item keeps its checkbox
        let name: String
        let target: String   // URL for links, app name or bundle id for apps
        let group: Group
        var browser: String? = nil
    }

    /**
     * @brief   The list in use: the built-in one, or the last good catalog.json.
     */
    nonisolated(unsafe) static var items: [Item] = builtIn

    /**
     * @brief   Everything Settings offers. TXST rebranded txstate.edu to txst.edu,
     *          but a few services (Degree Audit) still live on txstate.edu hosts.
     */
    static let builtIn: [Item] = [
        .init(id: "canvas", name: "Canvas", target: "https://txstate.instructure.com", group: .pinned),
        .init(id: "catsweb", name: "CatsWeb", target: "https://www.catsweb.txst.edu/students.html", group: .pinned),
        .init(id: "navigate-360", name: "Navigate 360", target: "https://txst.navigate.eab.com/app/#/authentication/remote/", group: .pinned),
        .init(id: "genio", name: "Genio", target: "https://app.genio.co", group: .pinned),

        .init(id: "campus-map", name: "Campus Map", target: "https://maps.txst.edu", group: .links),
        .init(id: "computer-science", name: "Computer Science", target: "https://cs.txst.edu", group: .links),
        .init(id: "degree-audit", name: "Degree Audit", target: "https://dw-prod.ec.txstate.edu/responsiveDashboard/worksheets/WEB31", group: .links),
        .init(id: "disability-services", name: "Disability Services", target: "https://disability.txst.edu", group: .links),
        .init(id: "financial-aid", name: "Financial Aid", target: "https://www.finaid.txst.edu", group: .links),
        .init(id: "ingram-school-of-eng", name: "Ingram School of Eng.", target: "https://www.engineering.txst.edu", group: .links),
        .init(id: "parking-services", name: "Parking Services", target: "https://www.parking.txst.edu", group: .links),
        .init(id: "registration", name: "Registration", target: "https://www.registrar.txst.edu", group: .links),
        .init(id: "student-balance", name: "Student Balance", target: "https://www.sbs.txst.edu", group: .links),
        .init(id: "veterans-affairs", name: "Veterans Affairs", target: "https://va.txst.edu", group: .links),

        .init(id: "obsidian", name: "Obsidian", target: "md.obsidian", group: .apps),
        .init(id: "chrome", name: "Chrome", target: "chrome", group: .apps),
    ]

    /**
     * @brief   Finds a catalog item by name.
     *
     * @param   name    the item's name.
     * @return  the item, or nil if there isn't one by that name.
     */
    static func item(named name: String) -> Item? {
        items.first { $0.name == name }
    }

    // MARK: - Matching against config.json

    /**
     * @brief   Whether config already has this item.
     *
     * @param   item    the catalog item.
     * @param   config  the config to look in.
     * @return  true if a link matches by name or host (anywhere in the menu),
     *          or an app matches by name or target.
     */
    static func isIncluded(_ item: Item, in config: Config) -> Bool {
        switch item.group {
        case .apps:
            return config.apps.contains { matches(item, $0) }
        case .pinned, .links:
            return allLinks(config).contains { matches(item, $0) }
        }
    }

    /**
     * @brief   Adds the item to its group, or removes every matching entry.
     *
     * @param   item      the catalog item.
     * @param   included  true to add, false to remove.
     * @param   config    the config to change.
     */
    static func set(_ item: Item, included: Bool, in config: inout Config) {
        if included {
            guard !isIncluded(item, in: config) else { return }
            switch item.group {
            case .pinned: config.pinned.append(.init(name: item.name, url: item.target, browser: item.browser))
            case .links: config.links.append(.init(name: item.name, url: item.target, browser: item.browser))
            case .apps: config.apps.append(.init(name: item.name, target: item.target))
            }
        } else {
            config.apps.removeAll { matches(item, $0) }
            config.pinned.removeAll { matches(item, $0) }
            config.links.removeAll { matches(item, $0) }
            for i in config.sections.indices {
                config.sections[i].items.removeAll { matches(item, $0) }
            }
        }
    }

    /**
     * @brief   Every link in the config, wherever it sits in the menu.
     *
     * @param   c       the config.
     * @return  pinned, links and every section's items.
     */
    private static func allLinks(_ c: Config) -> [Config.Link] {
        c.pinned + c.links + c.sections.flatMap(\.items)
    }

    /**
     * @brief   Whether a config link is this catalog item.
     *
     * @param   item    the catalog item.
     * @param   link    the config link.
     * @return  true for the same name or the same address (ignoring www. and a
     *          trailing slash). A different page on the same site is the user's own.
     */
    private static func matches(_ item: Item, _ link: Config.Link) -> Bool {
        guard item.group != .apps else { return false }
        if link.name.caseInsensitiveCompare(item.name) == .orderedSame { return true }
        return normalized(item.target) == normalized(link.url)
    }

    private static func matches(_ item: Item, _ app: Config.AppLink) -> Bool {
        item.group == .apps
            && (app.name.caseInsensitiveCompare(item.name) == .orderedSame
                || app.target.caseInsensitiveCompare(item.target) == .orderedSame)
    }

    /**
     * @brief   A URL reduced for matching.
     *
     * @param   url     the URL.
     * @return  host (lowercased, without www.) plus path without trailing slashes,
     *          query and fragment; nil if there's no host.
     */
    static func normalized(_ url: String) -> String? {
        guard let u = URLComponents(string: url), var h = u.host?.lowercased() else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        var path = u.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        return h + path + (u.percentEncodedQuery.map { "?" + $0 } ?? "") + (u.percentEncodedFragment.map { "#" + $0 } ?? "")
    }

    /**
     * @brief   Whether a link in config.json is one of the catalog's (by name or address),
     *          as opposed to one the user added.
     *
     * @param   link    the link.
     */
    static func isCatalogLink(_ link: Config.Link) -> Bool {
        items.contains { matches($0, link) }
    }
}
