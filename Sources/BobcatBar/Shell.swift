import Foundation
import AppKit

/// Thin wrappers around the NSWorkspace calls the menu needs.
enum Shell {

    static func open(url: String, with browser: String? = nil) {
        guard let u = URL(string: url) else { return }
        guard let browser, !browser.isEmpty else {
            NSWorkspace.shared.open(u)
            return
        }
        if let appURL = appURL(for: browser) {
            let cfg = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([u], withApplicationAt: appURL, configuration: cfg)
        } else {
            NSWorkspace.shared.open(u)   // browser not found; fall back to default
        }
    }

    static func launch(app target: String) {
        if let appURL = appURL(for: target) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else {
            // Unknown display name — let `open -a` resolve it by Spotlight.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", target]
            try? p.run()
        }
    }

    /// Resolve an app by bundle id (contains a dot) or by a known display name.
    private static func appURL(for id: String) -> URL? {
        if id.contains("."),
           let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return u
        }
        if let bid = knownBundleIDs[id.lowercased()] {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        }
        return nil
    }

    private static let knownBundleIDs: [String: String] = [
        "google chrome": "com.google.Chrome",
        "chrome": "com.google.Chrome",
        "safari": "com.apple.Safari",
        "firefox": "org.mozilla.firefox",
        "arc": "company.thebrowser.Browser",
        "obsidian": "md.obsidian",
    ]
}
