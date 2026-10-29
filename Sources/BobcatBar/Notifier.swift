/**
 * @file    Notifier.swift
 * @author  James Zeman
 * @date    28 OCT 2026
 * @brief   Score notifications: 30 minutes before a game and when it ends, for the
 *          sports picked in Settings. Clicking one opens the game on ESPN.
 */
import AppKit
import UserNotifications

@MainActor
/**
 * @brief   Watches the games Scores fetches and notifies about changes.
 */
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var sports: Set<String> = []
    private var notifyStart = true
    private var notifyFinal = true
    private var lastState: [String: Game.State] = [:]   // per game id, from the last check
    private var notified: Set<String>                   // "start:<id>" / "final:<id>", kept across launches
    private static let notifiedKey = "notified"
    nonisolated static let startLead: TimeInterval = 30 * 60

    override init() {
        notified = Set(UserDefaults.standard.stringArray(forKey: Self.notifiedKey) ?? [])
        super.init()
    }

    /**
     * @brief   Applies the settings. Asks for permission the first time a sport is
     *          turned on (not at launch).
     *
     * @param   config  the config.
     */
    func configure(_ config: Config) {
        let wasOff = sports.isEmpty
        sports = config.scores ? Set(config.notifySports) : []
        notifyStart = config.notifyStart
        notifyFinal = config.notifyFinal
        if wasOff, !sports.isEmpty {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /**
     * @brief   Whether macOS lets BobcatBar show notifications.
     */
    static func isAllowed() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            || s.authorizationStatus == .notDetermined
    }

    /**
     * @brief   Checks the games for anything to announce. Called after every fetch
     *          and once a minute (for the 30-minute warning).
     *
     * @param   games   every sport's games.
     * @param   now     the time.
     */
    func check(_ games: [Game], now: Date = Date()) {
        let events = Self.events(games, lastState: lastState, notified: notified, sports: sports,
                                 start: notifyStart, final: notifyFinal, now: now)
        for game in games { lastState[game.id] = game.state }
        guard !events.isEmpty else { return }
        for e in events {
            notified.insert(e.key)
            post(e)
        }
        // keep only keys for games still in the schedules
        let ids = Set(games.map(\.id))
        notified = notified.filter { ids.contains(String($0.split(separator: ":").last ?? "")) }
        UserDefaults.standard.set(Array(notified), forKey: Self.notifiedKey)
    }

    /**
     * @brief   One notification to send.
     */
    struct Event: Equatable {
        let key: String     // "start:<id>" or "final:<id>"
        let title: String
        let body: String
        let url: String
    }

    /**
     * @brief   Works out which notifications are due. A final is announced only when
     *          this run saw the game before it ended, so a relaunch doesn't repeat
     *          old results.
     */
    nonisolated static func events(_ games: [Game], lastState: [String: Game.State], notified: Set<String>,
                                   sports: Set<String>, start: Bool, final: Bool, now: Date) -> [Event] {
        var out: [Event] = []
        for g in games where sports.contains(g.sport.name) {
            let versus = (g.home ? "vs " : "at ") + g.opponent
            if start, g.state == .upcoming, !notified.contains("start:\(g.id)") {
                let mins = g.date.timeIntervalSince(now) / 60
                if mins > 0, mins <= startLead / 60 + 0.5 {
                    out.append(Event(key: "start:\(g.id)",
                                     title: "\(g.sport.emoji) Texas State \(versus) starts in \(Int(mins.rounded())) min",
                                     body: g.sport.name + " · " + g.date.formatted(date: .omitted, time: .shortened),
                                     url: g.url))
                }
            }
            if final, g.state == .final, let before = lastState[g.id], before != .final,
               !notified.contains("final:\(g.id)") {
                let title: String
                if let us = g.us, let them = g.them {
                    let verb = g.won == true ? "wins" : g.won == false ? "falls" : "ties"
                    title = "\(g.sport.emoji) Texas State \(verb) \(us)–\(them)"
                } else {
                    title = "\(g.sport.emoji) \(g.detail)"   // canceled, postponed
                }
                let extra = g.detail.hasPrefix("Final/") ? " (\(g.detail.dropFirst(6)))" : ""
                out.append(Event(key: "final:\(g.id)", title: title,
                                 body: "Final \(versus)\(extra) · \(g.sport.name)", url: g.url))
            }
        }
        return out
    }

    private func post(_ e: Event) {
        let content = UNMutableNotificationContent()
        content.title = e.title
        content.body = e.body
        content.sound = .default
        content.userInfo = ["url": e.url]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.key, content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /**
     * @brief   Shows notifications even while a BobcatBar window is in front.
     */
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /**
     * @brief   Clicking a notification opens the game on ESPN.
     */
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse)
        async {
        guard let s = response.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(u) }
    }
}
