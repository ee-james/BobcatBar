/**
 * @file    Updater.swift
 * @author  James Zeman
 * @date    28 OCT 2026
 * @brief   App updates with Sparkle: a daily check of appcast.xml in the GitHub repo,
 *          and Check for Updates… in the menu. Only release builds (build.sh
 *          --release) carry the feed, so a local --install build never replaces
 *          itself with the published one.
 */
import AppKit
import Sparkle

@MainActor
/**
 * @brief   Owns Sparkle's updater, when this build has a feed.
 */
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    /**
     * @brief   Starts Sparkle if Info.plist names a feed.
     */
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /**
     * @brief   Whether this build can update itself.
     */
    var isAvailable: Bool { controller != nil }

    /**
     * @brief   Checks now and shows the result (Check for Updates…).
     */
    @objc func checkForUpdates(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }

    /**
     * @brief   Whether Sparkle checks once a day by itself.
     */
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /**
     * @brief   Whether found updates are downloaded and installed at quit without asking.
     */
    var installsAutomatically: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /**
     * @brief   A menu-bar app has no Dock icon to bounce, so Sparkle is told it may
     *          bring its update window to the front itself.
     */
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}
