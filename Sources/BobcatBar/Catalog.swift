/**
 * @file    Catalog.swift
 * @author  James Zeman
 * @date    27 OCT 2026
 * @brief   The built-in Texas State links and apps that Settings offers as
 *          checkboxes, and how they're matched against config.json.
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
    enum Group: String, CaseIterable {
        case pinned = "Pinned (top of the menu)"
        case links = "Links"
        case apps = "Apps"
    }

    /**
     * @brief   One checkbox: a link (URL) or an app (name or bundle id).
     */
    struct Item: Identifiable {
        let name: String
        let target: String   // URL for links, app name or bundle id for apps
        let group: Group
        var browser: String? = nil
        var id: String { name }
    }

    /**
     * @brief   Everything Settings offers. TXST rebranded txstate.edu to txst.edu,
     *          but a few services (Degree Audit) still live on txstate.edu hosts.
     */
    static let items: [Item] = [
        .init(name: "Canvas", target: "https://txstate.instructure.com", group: .pinned),
        .init(name: "CatsWeb", target: "https://www.catsweb.txst.edu/students.html", group: .pinned),
        .init(name: "Navigate 360", target: "https://txst.navigate.eab.com/app/#/authentication/remote/", group: .pinned),
        .init(name: "Genio", target: "https://app.genio.co", group: .pinned),

        .init(name: "Campus Map", target: "https://maps.txst.edu", group: .links),
        .init(name: "Computer Science", target: "https://cs.txst.edu", group: .links),
        .init(name: "Degree Audit", target: "https://dw-prod.ec.txstate.edu/responsiveDashboard/worksheets/WEB31", group: .links),
        .init(name: "Disability Services", target: "https://disability.txst.edu", group: .links),
        .init(name: "Financial Aid", target: "https://www.finaid.txst.edu", group: .links),
        .init(name: "Ingram School of Eng.", target: "https://www.engineering.txst.edu", group: .links),
        .init(name: "Parking Services", target: "https://www.parking.txst.edu", group: .links),
        .init(name: "Registration", target: "https://www.registrar.txst.edu", group: .links),
        .init(name: "Student Balance", target: "https://www.sbs.txst.edu", group: .links),
        .init(name: "Veterans Affairs", target: "https://va.txst.edu", group: .links),

        .init(name: "Obsidian", target: "md.obsidian", group: .apps),
        .init(name: "Chrome", target: "chrome", group: .apps),
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
     * @return  true for the same name or the same host (ignoring www.).
     */
    private static func matches(_ item: Item, _ link: Config.Link) -> Bool {
        guard item.group != .apps else { return false }
        if link.name.caseInsensitiveCompare(item.name) == .orderedSame { return true }
        guard let a = host(item.target), let b = host(link.url) else { return false }
        return a == b
    }

    /**
     * @brief   Whether a config app is this catalog item.
     *
     * @param   item    the catalog item.
     * @param   app     the config app.
     * @return  true for the same name or target.
     */
    private static func matches(_ item: Item, _ app: Config.AppLink) -> Bool {
        item.group == .apps
            && (app.name.caseInsensitiveCompare(item.name) == .orderedSame
                || app.target.caseInsensitiveCompare(item.target) == .orderedSame)
    }

    /**
     * @brief   Gets a URL's host for matching.
     *
     * @param   url     the URL.
     * @return  the lowercased host without www., or nil if there isn't one.
     */
    private static func host(_ url: String) -> String? {
        guard let h = URL(string: url)?.host?.lowercased() else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}
