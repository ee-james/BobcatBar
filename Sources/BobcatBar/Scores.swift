/**
 * @file    Scores.swift
 * @author  James Zeman
 * @date    28 OCT 2026
 * @brief   Texas State scores from ESPN's public schedule data: the latest game
 *          for the menu line, and recent and upcoming games per sport for its
 *          submenu.
 */
import AppKit

/**
 * @brief   A Texas State team ESPN covers. Team ids differ by sport.
 */
struct Sport: Hashable {
    let name: String
    let emoji: String
    let league: String   // ESPN path, e.g. "football/college-football"
    let teamID: String

    static let all: [Sport] = [
        .init(name: "Football", emoji: "🏈", league: "football/college-football", teamID: "326"),
        .init(name: "Men's Basketball", emoji: "🏀", league: "basketball/mens-college-basketball", teamID: "326"),
        .init(name: "Women's Basketball", emoji: "🏀", league: "basketball/womens-college-basketball", teamID: "326"),
        .init(name: "Volleyball", emoji: "🏐", league: "volleyball/womens-college-volleyball", teamID: "326"),
        .init(name: "Baseball", emoji: "⚾️", league: "baseball/college-baseball", teamID: "147"),
        .init(name: "Softball", emoji: "🥎", league: "softball/college-softball", teamID: "326"),
    ]
}

/**
 * @brief   One game, from Texas State's side.
 */
struct Game {
    enum State { case upcoming, live, final }

    let id: String         // ESPN's event id
    let sport: Sport
    let date: Date
    let state: State
    let opponent: String   // short name, e.g. "Boise State"
    let home: Bool
    let us: String?        // scores as ESPN shows them; nil before the game
    let them: String?
    let won: Bool?
    let detail: String     // ESPN's short status: "Final", "Q3 5:12", "Canceled"
    let url: String        // the ESPN game page

    /**
     * @brief   The game as one menu line, e.g. "🏈 W 20–17 vs Utah State".
     *
     * @param   withSport   lead with the sport's emoji (the top-level line does).
     * @return  the line.
     */
    func line(withSport: Bool) -> String {
        let lead = withSport ? sport.emoji + " " : ""
        let versus = (home ? "vs " : "at ") + opponent
        switch state {
        case .upcoming:
            return lead + Self.when(date) + " " + versus
        case .live:
            return lead + "LIVE \(us ?? "0")–\(them ?? "0") \(versus) · \(detail)"
        case .final:
            guard let us, let them else { return lead + "\(detail): \(versus)" }   // canceled, postponed
            let result = won == true ? "W" : won == false ? "L" : "T"
            let extra = detail.hasPrefix("Final/") ? " (\(detail.dropFirst(6)))" : ""   // "Final/OT"
            return lead + "\(result) \(us)–\(them) \(versus)" + extra
        }
    }

    /**
     * @brief   A short local start time, e.g. "Sat 10/31 9:00 PM".
     */
    private static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE M/d h:mm a"
        return f.string(from: d)
    }
}

@MainActor
/**
 * @brief   Fetches and keeps the games. Refreshes every 15 minutes, every minute
 *          while a game is live, and when the menu opens with stale data.
 */
final class Scores {
    private(set) var games: [Sport: [Game]] = [:]
    private(set) var updated: Date?
    private var fetching = false
    private var timer: Timer?
    var onChange: () -> Void = {}   // after every fetch
    var onTick: () -> Void = {}     // once a minute while running

    /**
     * @brief   Starts fetching, now and on the refresh timer.
     */
    func start() {
        refresh(ifOlderThan: 0)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh(ifOlderThan: self?.isLive == true ? 55 : 15 * 60)
                self?.onTick()
            }
        }
    }

    /**
     * @brief   Stops the timer and forgets the games (scores turned off).
     */
    func stop() {
        timer?.invalidate()
        timer = nil
        games = [:]
        updated = nil
    }

    var isRunning: Bool { timer != nil }

    /**
     * @brief   Every sport's games.
     */
    var all: [Game] { Array(games.values.joined()) }

    /**
     * @brief   Whether any game is in progress.
     */
    var isLive: Bool { games.values.joined().contains { $0.state == .live } }

    /**
     * @brief   Fetches every sport unless the data is newer than maxAge.
     *
     * @param   maxAge  seconds; 0 always fetches.
     */
    func refresh(ifOlderThan maxAge: TimeInterval) {
        if fetching { return }
        if let u = updated, Date().timeIntervalSince(u) < maxAge { return }
        fetching = true
        Task {
            var fresh: [Sport: [Game]] = [:]
            await withTaskGroup(of: (Sport, [Game]?).self) { group in
                for sport in Sport.all {
                    group.addTask { (sport, await Self.fetch(sport)) }
                }
                for await (sport, list) in group {
                    fresh[sport] = list ?? self.games[sport]   // keep the old games if a fetch fails
                }
            }
            games = fresh
            updated = Date()
            fetching = false
            onChange()
        }
    }

    /**
     * @brief   The game for the menu line: a live one, else the latest result from
     *          the last two weeks, else the next game.
     */
    var headline: Game? { Self.headline(all, now: Date()) }

    /**
     * @brief   Live games, then every result from the past week in any sport, newest first.
     */
    var pastWeek: [Game] { Self.pastWeek(all, now: Date()) }

    /**
     * @brief   Games in the coming week in any sport, soonest first.
     */
    var comingWeek: [Game] { Self.comingWeek(all, now: Date()) }

    nonisolated static func headline(_ all: [Game], now: Date) -> Game? {
        if let live = all.filter({ $0.state == .live }).max(by: { $0.date < $1.date }) { return live }
        let recent = now.addingTimeInterval(-14 * 86400)
        if let last = all.filter({ $0.state == .final && $0.us != nil && $0.date > recent }).max(by: { $0.date < $1.date }) {
            return last
        }
        return all.filter { $0.state == .upcoming && $0.date > now }.min { $0.date < $1.date }
    }

    nonisolated static func pastWeek(_ all: [Game], now: Date) -> [Game] {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        return all.filter { $0.state == .live }.sorted { $0.date > $1.date }
            + all.filter { $0.state == .final && $0.date > weekAgo }.sorted { $0.date > $1.date }
    }

    nonisolated static func comingWeek(_ all: [Game], now: Date) -> [Game] {
        let weekOut = now.addingTimeInterval(7 * 86400)
        return all.filter { $0.state == .upcoming && $0.date > now.addingTimeInterval(-6 * 3600) && $0.date < weekOut }
            .sorted { $0.date < $1.date }
    }

    // MARK: - ESPN

    /**
     * @brief   Downloads and parses one sport's schedule.
     *
     * @param   sport   the sport.
     * @return  its games by date, or nil when the request or parse fails.
     */
    nonisolated private static func fetch(_ sport: Sport) async -> [Game]? {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(sport.league)/teams/\(sport.teamID)/schedule")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("BobcatBar", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data: data, sport)
    }

    /**
     * @brief   Parses an ESPN team schedule.
     *
     * @param   data    the JSON response.
     * @param   sport   the sport it's for.
     * @return  its games by date, or nil when it isn't a schedule.
     */
    nonisolated static func parse(data: Data, _ sport: Sport) -> [Game]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return nil }
        return events.compactMap { parse($0, sport) }.sorted { $0.date < $1.date }
    }

    /**
     * @brief   Turns one ESPN event into a Game, or nil if it's missing what we need.
     */
    nonisolated static func parse(_ e: [String: Any], _ sport: Sport) -> Game? {
        guard let id = e["id"] as? String,
              let date = (e["date"] as? String).flatMap(parseDate),
              let comp = (e["competitions"] as? [[String: Any]])?.first,
              let teams = comp["competitors"] as? [[String: Any]],
              let ours = teams.first(where: { ($0["team"] as? [String: Any])?["id"] as? String == sport.teamID }),
              let theirs = teams.first(where: { ($0["team"] as? [String: Any])?["id"] as? String != sport.teamID }),
              let type = ((comp["status"] as? [String: Any])?["type"]) as? [String: Any] else { return nil }

        let state: Game.State
        switch type["state"] as? String {
        case "in": state = .live
        case "post": state = .final
        default: state = .upcoming
        }
        let opp = theirs["team"] as? [String: Any]
        return Game(
            id: id, sport: sport, date: date, state: state,
            opponent: (opp?["shortDisplayName"] as? String) ?? (opp?["displayName"] as? String) ?? "TBA",
            home: (ours["homeAway"] as? String) == "home",
            us: score(ours), them: score(theirs),
            won: ours["winner"] as? Bool,
            detail: (type["shortDetail"] as? String) ?? "",
            url: "https://www.espn.com/\(sport.league.split(separator: "/").last!)/game/_/gameId/\(id)")
    }

    /**
     * @brief   A competitor's score: an object with displayValue on schedules, a plain
     *          string on scoreboards.
     */
    nonisolated static func score(_ c: [String: Any]) -> String? {
        if let s = c["score"] as? [String: Any] { return s["displayValue"] as? String }
        return c["score"] as? String
    }

    /**
     * @brief   ESPN dates look like "2026-10-24T23:30Z", sometimes with seconds.
     */
    nonisolated static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
