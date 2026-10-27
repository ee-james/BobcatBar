/**
 * @file    Shell.swift
 * @author  James Zeman
 * @date    9 SEP 2026
 * @brief   Thin wrappers around the NSWorkspace calls the menu needs.
 */
import Foundation
import AppKit

/**
 * @brief   Opens links and launches apps.
 */
enum Shell {

    /**
     * @brief   Opens a URL, in a specific browser if one is given.
     *
     * @param   url      the URL.
     * @param   browser  a browser name ("Google Chrome") or bundle id; nil for
the default.
     */
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

    /**
     * @brief   Launches an app.
     *
     * @param   target  an app name or bundle id.
     */
    static func launch(app target: String) {
        if let appURL = appURL(for: target) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else {
            // not a name we know, so let `open -a` find it with Spotlight
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", target]
            try? p.run()
        }
    }

    /**
     * @brief   Finds an installed app.
     *
     * @param   id      a bundle id (has a dot) or a known name ("chrome").
     * @return  the app's location, or nil if it isn't installed or isn't known.
     */
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

    /**
     * @brief   Display names people type in config.json, mapped to bundle ids.
     */
    private static let knownBundleIDs: [String: String] = [
        "google chrome": "com.google.Chrome",
        "chrome": "com.google.Chrome",
        "safari": "com.apple.Safari",
        "firefox": "org.mozilla.firefox",
        "arc": "company.thebrowser.Browser",
        "obsidian": "md.obsidian",
    ]
}
