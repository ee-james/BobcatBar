/**
 * @file    CatalogUpdater.swift
 * @author  James Zeman
 * @date    28 OCT 2026
 * @brief   Keeps the campus links current from catalog.json in the GitHub repo, so
 *          a dead link can be fixed without a new release. Only addresses on the
 *          built-in allowlist below are accepted; anything else needs a signed
 *          release. Checked once a day; the last good copy is cached. When a link's
 *          address changes, the copy in config.json is updated too, since ticking a
 *          checkbox copies the address there.
 */
import Foundation

/**
 * @brief   The catalog.json format.
 */
struct CatalogFile: Codable {
    var version: Int
    var items: [Catalog.Item]
}

enum CatalogUpdater {
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/ee-james/BobcatBar/main/catalog.json")!
    static let maxAge: TimeInterval = 24 * 3600

    /**
     * @brief   The only places a downloaded catalog may point. These are compiled in,
     *          so changing them takes a signed release, not just an edit to catalog.json.
     *          A domain also allows its subdomains; a host allows only itself.
     */
    static let allowedDomains: Set<String> = ["txst.edu", "txstate.edu"]
    static let allowedHosts: Set<String> = ["txstate.instructure.com", "txst.navigate.eab.com", "app.genio.co"]
    static let allowedApps: Set<String> = ["md.obsidian", "chrome"]
    static let allowedBrowsers: Set<String> = ["Safari", "com.apple.Safari", "Google Chrome", "com.google.Chrome",
                                               "Firefox", "org.mozilla.firefox", "Microsoft Edge", "com.microsoft.edgemac",
                                               "Arc", "company.thebrowser.Browser", "Brave Browser", "com.brave.Browser"]

    /**
     * @brief   Whether a link's host is on the allowlist.
     */
    static func isAllowed(host: String) -> Bool {
        let h = host.lowercased()
        return allowedHosts.contains(h) || allowedDomains.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    /**
     * @brief   The cached copy, ~/Library/Caches/com.zetsystems.bobcatbar/catalog.json.
     */
    static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.zetsystems.bobcatbar/catalog.json")
    }

    /**
     * @brief   Uses the cached catalog, if there's a good one. Call at launch.
     */
    static func loadCached() {
        if let data = try? Data(contentsOf: cacheURL), let items = validate(data) {
            Catalog.items = items
        }
    }

    /**
     * @brief   Whether the cached copy is older than a day (or missing).
     */
    static var isStale: Bool {
        let a = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        guard let m = a?[.modificationDate] as? Date else { return true }
        return Date().timeIntervalSince(m) > maxAge
    }

    /**
     * @brief   Downloads catalog.json and, if it changed, switches to it and updates
     *          config.json's copies of changed links. If config.json has an error the
     *          new catalog isn't used yet, so the fix is applied on a later try.
     *
     * @param   onChange    called on the main actor when the catalog changed.
     */
    @MainActor
    static func refresh(onChange: @escaping @MainActor () -> Void) {
        Task {
            var req = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("BobcatBar", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let fresh = validate(data) else { return }
            let old = Catalog.items
            if fresh != old {
                if needsMigration(from: old, to: fresh) {
                    guard case .success = ConfigStore.update({ migrate(&$0, from: old, to: fresh) }) else { return }
                }
                Catalog.items = fresh
                onChange()
            }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)   // also marks it checked today
        }
    }

    /**
     * @brief   Checks a downloaded catalog. Anything odd rejects the whole file: links
     *          must be https addresses on an allowed host, apps and browsers must be on
     *          their allowlists.
     *
     * @param   data    the file.
     * @return  its items, or nil.
     */
    static func validate(_ data: Data) -> [Catalog.Item]? {
        guard let file = try? JSONDecoder().decode(CatalogFile.self, from: data),
              file.version == 1, (1...200).contains(file.items.count),
              Set(file.items.map(\.id)).count == file.items.count else { return nil }
        let appName = /^[A-Za-z0-9][A-Za-z0-9 .\-]{0,80}$/
        for item in file.items {
            let name = item.name.trimmingCharacters(in: .whitespaces)
            guard !item.id.isEmpty, !name.isEmpty, name.count <= 60 else { return nil }
            if let b = item.browser, b.wholeMatch(of: appName) == nil || !allowedBrowsers.contains(b) { return nil }
            switch item.group {
            case .apps:
                guard item.target.wholeMatch(of: appName) != nil, allowedApps.contains(item.target) else { return nil }
            case .pinned, .links:
                guard let u = URLComponents(string: item.target), u.scheme == "https",
                      let host = u.host, host.contains("."), u.user == nil, u.password == nil, u.port == nil,
                      isAllowed(host: host) else { return nil }
            }
        }
        return file.items
    }

    /**
     * @brief   Whether any item kept its id but changed address or name.
     */
    static func needsMigration(from old: [Catalog.Item], to new: [Catalog.Item]) -> Bool {
        let byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return new.contains { n in byID[n.id].map { $0.target != n.target || $0.name != n.name } ?? false }
    }

    /**
     * @brief   Updates config.json's copies of catalog items that changed address or
     *          name. Only entries that still have the old catalog address (or the old
     *          name for apps) change, so links a user edited are left alone.
     *
     * @param   config  the config to update.
     * @param   old     the catalog it was made from.
     * @param   new     the new catalog.
     */
    static func migrate(_ config: inout Config, from old: [Catalog.Item], to new: [Catalog.Item]) {
        let byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for n in new {
            guard let o = byID[n.id], o.target != n.target || o.name != n.name else { continue }
            if n.group == .apps {
                for i in config.apps.indices where config.apps[i].target.caseInsensitiveCompare(o.target) == .orderedSame {
                    config.apps[i].target = n.target
                    if config.apps[i].name == o.name { config.apps[i].name = n.name }
                }
                continue
            }
            let oldAddress = Catalog.normalized(o.target)
            func fix(_ links: inout [Config.Link]) {
                for i in links.indices where Catalog.normalized(links[i].url) == oldAddress {
                    links[i].url = n.target
                    if links[i].name == o.name { links[i].name = n.name }
                }
            }
            fix(&config.pinned)
            fix(&config.links)
            for s in config.sections.indices { fix(&config.sections[s].items) }
        }
    }
}
