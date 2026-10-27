/**
 * @file    AppDelegate.swift
 * @author  James Zeman
 * @date    10 SEP 2026
 * @brief   The BobcatBar menu: pinned links, links, sections with headings
 *          (Orgs), apps, and the Settings/Reload/Quit items.
 */
import AppKit

@MainActor
/**
 * @brief   Owns the menu-bar item and rebuilds its menu from config.json.
 */
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var config = Config.starter
    private var configError: String?

    /**
     * @brief   Creates the menu-bar item and loads the config.
     *
     * @param   notification  unused.
     */
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.toolTip = "BobcatBar"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        reload(nil)
    }

    // MARK: - Config

    /**
     * @brief   Re-reads config.json and rebuilds the menu.
     *
     * @param   sender  the menu item, or nil when called from code.
     */
    @objc func reload(_ sender: Any?) {
        let result = ConfigStore.load()
        config = result.config
        configError = result.error
        rebuildMenu()
    }

    /**
     * @brief   Opens config.json in the default editor, writing the starter first if
     *          there isn't one yet.
     *
     * @param   sender  the menu item.
     */
    @objc func editConfig(_ sender: Any?) {
        if !FileManager.default.fileExists(atPath: ConfigStore.fileURL.path) {
            ConfigStore.writeStarter()
        }
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    /**
     * @brief   Opens the Settings window. Saving there reloads the menu.
     *
     * @param   sender  the menu item.
     */
    @objc func openSettings(_ sender: Any?) {
        SettingsWindow.show(config: config) { [weak self] in self?.reload(nil) }
    }

    // MARK: - NSMenuDelegate

    /**
     * @brief   Reloads just before the menu shows, so config edits appear right away.
     *
     * @param   menu    the menu about to open.
     */
    func menuWillOpen(_ menu: NSMenu) {
        reload(nil)
    }

    // MARK: - Menu

    /**
     * @brief   Builds the whole menu from the current config. A config error shows
     *          first, as an item that opens the file.
     */
    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        if let err = configError {
            let e = NSMenuItem(title: "⚠︎ \(err)", action: #selector(editConfig), keyEquivalent: "")
            e.target = self
            menu.addItem(e)
            menu.addItem(.separator())
        }

        for link in config.pinned {
            addLink(to: menu, link)
        }
        if !config.pinned.isEmpty { menu.addItem(.separator()) }

        let ordered = config.sortLinks
            ? config.links.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            : config.links
        for link in ordered {
            addLink(to: menu, link)
        }
        if !ordered.isEmpty { menu.addItem(.separator()) }

        for section in config.sections {
            let items = section.sort
                ? section.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                : section.items
            guard !items.isEmpty else { continue }
            if !section.name.isEmpty { menu.addItem(.sectionHeader(title: section.name)) }
            for link in items {
                addLink(to: menu, link)
            }
            menu.addItem(.separator())
        }

        for app in config.apps {
            let item = NSMenuItem(title: app.name, action: #selector(openApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.target
            menu.addItem(item)
        }
        if !config.apps.isEmpty { menu.addItem(.separator()) }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reload(_:)), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        let quit = NSMenuItem(title: "Quit BobcatBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /**
     * @brief   Adds one link to a menu.
     *
     * @param   menu    the menu to add to.
     * @param   link    the link; its browser, if set, goes in the tooltip.
     */
    private func addLink(to menu: NSMenu, _ link: Config.Link) {
        let item = NSMenuItem(title: link.name, action: #selector(openLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = link
        if link.browser != nil {
            item.toolTip = "Opens in \(link.browser!)"
        }
        menu.addItem(item)
    }

    // MARK: - Actions

    /**
     * @brief   Opens a link, in its chosen browser if it has one.
     *
     * @param   sender  the menu item; its representedObject is the link.
     */
    @objc private func openLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? Config.Link else { return }
        Shell.open(url: link.url, with: link.browser)
    }

    /**
     * @brief   Launches an app from the Apps list.
     *
     * @param   sender  the menu item; its representedObject is the app's name or bundle id.
     */
    @objc private func openApp(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        Shell.launch(app: target)
    }

    // MARK: - Icon

    /**
     * @brief   Loads the menu-bar icon.
     *
     * @return  the Supercat template image, or a drawn paw print if the png is missing.
     */
    static func menuBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "BobcatTemplate@2x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        // no png in the bundle (a debug run): draw a simple paw print instead
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 3, width: 8, height: 7)).fill()   // pad
            for cx in [4.0, 7.5, 11.0, 14.0] {
                let y = cx == 7.5 || cx == 11.0 ? 11.0 : 9.0
                NSBezierPath(ovalIn: NSRect(x: cx - 1.6, y: y, width: 3.2, height: 4)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
