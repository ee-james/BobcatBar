import XCTest
@testable import BobcatBar

/// Fixtures in this folder: trimmed real ESPN schedules saved on 2026-10-28.
let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtures.appendingPathComponent(name))
}

func sport(_ name: String) -> Sport {
    Sport.all.first { $0.name == name }!
}

/// 2026-10-28 12:00 Central, when the fixtures were saved.
let fixtureNow = ISO8601DateFormatter().date(from: "2026-10-28T17:00:00Z")!

final class ScoresTests: XCTestCase {
    func testParsesFootballSchedule() throws {
        let games = try XCTUnwrap(Scores.parse(data: try fixture("football-schedule.json"), sport("Football")))
        XCTAssertEqual(games.count, 11)
        XCTAssertEqual(games.filter { $0.state == .final }.count, 7)
        XCTAssertEqual(games.map(\.date), games.map(\.date).sorted())

        let utah = try XCTUnwrap(games.first { $0.id == "401860906" })
        XCTAssertEqual(utah.opponent, "Utah State")
        XCTAssertTrue(utah.home)
        XCTAssertEqual(utah.us, "20")
        XCTAssertEqual(utah.them, "17")
        XCTAssertEqual(utah.won, true)
        XCTAssertEqual(utah.line(withSport: true), "🏈 W 20–17 vs Utah State")
        XCTAssertEqual(utah.url, "https://www.espn.com/college-football/game/_/gameId/401860906")

        let texas = try XCTUnwrap(games.first { $0.id == "401856667" })
        XCTAssertEqual(texas.line(withSport: false), "L 7–59 at Texas")

        let boise = try XCTUnwrap(games.first { $0.id == "401860908" })
        XCTAssertEqual(boise.state, .upcoming)
        XCTAssertNil(boise.us)
        XCTAssertFalse(boise.home)
    }

    func testLists() throws {
        let football = try XCTUnwrap(Scores.parse(data: try fixture("football-schedule.json"), sport("Football")))
        let volleyball = try XCTUnwrap(Scores.parse(data: try fixture("volleyball-schedule.json"), sport("Volleyball")))
        let all = football + volleyball

        XCTAssertEqual(Scores.headline(all, now: fixtureNow)?.id, "401860906")   // the Utah State win
        let past = Scores.pastWeek(all, now: fixtureNow)
        XCTAssertFalse(past.isEmpty)
        XCTAssertTrue(past.allSatisfy { $0.state == .final && $0.date > fixtureNow.addingTimeInterval(-7 * 86400) })
        XCTAssertEqual(past.map(\.date), past.map(\.date).sorted(by: >))

        let coming = Scores.comingWeek(all, now: fixtureNow)
        XCTAssertTrue(coming.contains { $0.id == "401860908" })   // at Boise State on 10/31
        XCTAssertFalse(coming.contains { $0.id == "401860912" })  // Oregon State is 11/7, over a week out
    }

    func testLiveGameLeadsEverything() throws {
        let live = """
        {"events": [{"id": "1", "date": "2026-10-28T16:00Z", "competitions": [{
          "status": {"type": {"state": "in", "shortDetail": "Q3 5:12"}},
          "competitors": [
            {"homeAway": "away", "score": "14", "team": {"id": "326", "shortDisplayName": "Texas St"}},
            {"homeAway": "home", "score": "10", "team": {"id": "68", "shortDisplayName": "Boise St"}}]}]}]}
        """
        let games = try XCTUnwrap(Scores.parse(data: Data(live.utf8), sport("Football")))
        XCTAssertEqual(games.first?.line(withSport: true), "🏈 LIVE 14–10 at Boise St · Q3 5:12")
        let football = try XCTUnwrap(Scores.parse(data: try fixture("football-schedule.json"), sport("Football")))
        XCTAssertEqual(Scores.headline(football + games, now: fixtureNow)?.id, "1")
        XCTAssertEqual(Scores.pastWeek(football + games, now: fixtureNow).first?.id, "1")
    }

    func testRejectsNonSchedule() {
        XCTAssertNil(Scores.parse(data: Data("{}".utf8), sport("Football")))
        XCTAssertNil(Scores.parse(data: Data("<html>".utf8), sport("Football")))
    }

    func testDates() {
        XCTAssertNotNil(Scores.parseDate("2026-10-24T23:30Z"))
        XCTAssertNotNil(Scores.parseDate("2026-10-24T23:30:00Z"))
        XCTAssertNil(Scores.parseDate("Oct 24"))
    }
}

final class ConfigTests: XCTestCase {
    var dir: URL!
    var savedDir: URL!

    override func setUp() {
        savedDir = ConfigStore.dir
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bobcatbar-tests-\(UUID().uuidString)")
        ConfigStore.dir = dir
    }

    override func tearDown() {
        ConfigStore.dir = savedDir
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: ConfigStore.fileURL)
    }

    func testMissingKeysUseDefaults() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(c.scores)
        XCTAssertTrue(c.sortLinks)
        XCTAssertTrue(c.links.isEmpty)
        let s = try JSONDecoder().decode(Config.self, from: Data(#"{"sections": [{"name": "Orgs"}]}"#.utf8))
        XCTAssertEqual(s.sections.first?.sort, true)
    }

    func testFirstRunWritesStarter() {
        let r = ConfigStore.load()
        XCTAssertNil(r.error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ConfigStore.fileURL.path))
        XCTAssertTrue(r.config.pinned.contains { $0.name == "Canvas" })
    }

    func testBrokenFileIsNeverOverwritten() throws {
        let broken = #"{"links": [{"name": "Mine", "url": "https://example.com"},]"#
        try write(broken)
        let r = ConfigStore.load()
        XCTAssertNotNil(r.error)
        XCTAssertTrue(r.config.pinned.contains { $0.name == "Canvas" })   // shows the starter meanwhile

        if case .success = ConfigStore.update({ $0.scores = false }) { XCTFail("saved over a broken file") }
        XCTAssertEqual(try String(contentsOf: ConfigStore.fileURL, encoding: .utf8), broken)
    }

    func testUpdateKeepsOutsideEditsAndBacksUp() throws {
        try write(#"{"links": [{"name": "Mine", "url": "https://example.com"}]}"#)
        _ = ConfigStore.load()
        // edited in an editor after Settings loaded it
        try write(#"{"links": [{"name": "Mine", "url": "https://example.com"}, {"name": "Also", "url": "https://example.org"}]}"#)

        let saved = try ConfigStore.update { $0.scores = false }.get()
        XCTAssertEqual(saved.links.map(\.name), ["Mine", "Also"])
        XCTAssertFalse(saved.scores)
        let backup = try String(contentsOf: ConfigStore.backupURL, encoding: .utf8)
        XCTAssertTrue(backup.contains("Also"))
        XCTAssertFalse(backup.contains("scores"))
    }

    func testStampChangesWithFile() throws {
        try write("{}")
        let a = ConfigStore.stamp()
        try write(#"{"scores": false}"#)
        XCTAssertNotEqual(a, ConfigStore.stamp())
    }
}

final class CatalogTests: XCTestCase {
    func testMatchesByNameOrSameAddress() {
        let canvas = Catalog.item(named: "Canvas")!
        var c = Config()
        XCTAssertFalse(Catalog.isIncluded(canvas, in: c))
        c.links = [.init(name: "My Canvas", url: "https://txstate.instructure.com/")]
        XCTAssertTrue(Catalog.isIncluded(canvas, in: c))
        c.links = [.init(name: "canvas", url: "https://example.com")]
        XCTAssertTrue(Catalog.isIncluded(canvas, in: c))
    }

    func testAPageOnTheSameSiteIsYourOwn() {
        let course = Config.Link(name: "EE 2100", url: "https://txstate.instructure.com/courses/123")
        XCTAssertFalse(Catalog.isCatalogLink(course))
        var c = Config()
        c.links = [course]
        Catalog.set(Catalog.item(named: "Canvas")!, included: true, in: &c)
        Catalog.set(Catalog.item(named: "Canvas")!, included: false, in: &c)
        XCTAssertEqual(c.links.map(\.name), ["EE 2100"])   // unticking Canvas leaves the course link alone
    }

    func testToggleApps() {
        var c = Config()
        let obsidian = Catalog.item(named: "Obsidian")!
        Catalog.set(obsidian, included: true, in: &c)
        Catalog.set(obsidian, included: true, in: &c)
        XCTAssertEqual(c.apps.count, 1)
        Catalog.set(obsidian, included: false, in: &c)
        XCTAssertTrue(c.apps.isEmpty)
    }
}

final class LinkDraftTests: XCTestCase {
    func testValidation() {
        var d = LinkDraft(title: "Add Org")
        XCTAssertNotNil(d.problem)
        d.name = "VATS"
        d.url = "dummy"
        XCTAssertNotNil(d.problem)
        d.url = "groupme.com/join_group/123"
        XCTAssertNil(d.problem)
        XCTAssertEqual(d.normalizedURL, "https://groupme.com/join_group/123")
        d.url = "ftp://files.txst.edu"
        XCTAssertNotNil(d.problem)
    }
}

final class NotifierTests: XCTestCase {
    func game(_ id: String, _ state: Game.State, at date: Date, us: String? = nil, them: String? = nil,
              won: Bool? = nil, sport: String = "Football") -> Game {
        Game(id: id, sport: BobcatBarTests.sport(sport), date: date, state: state, opponent: "Boise St", home: false,
             us: us, them: them, won: won, detail: state == .final ? "Final" : "", url: "https://espn.com/\(id)")
    }

    func testStartingSoon() {
        let now = fixtureNow
        let soon = game("1", .upcoming, at: now.addingTimeInterval(25 * 60))
        let later = game("2", .upcoming, at: now.addingTimeInterval(3 * 3600))
        let e = Notifier.events([soon, later], lastState: [:], notified: [], sports: ["Football"],
                                start: true, final: true, now: now)
        XCTAssertEqual(e.map(\.key), ["start:1"])
        XCTAssertEqual(e.first?.title, "🏈 Texas State at Boise St starts in 25 min")
        XCTAssertTrue(Notifier.events([soon], lastState: [:], notified: ["start:1"], sports: ["Football"],
                                      start: true, final: true, now: now).isEmpty)
        XCTAssertTrue(Notifier.events([soon], lastState: [:], notified: [], sports: ["Volleyball"],
                                      start: true, final: true, now: now).isEmpty)
        XCTAssertTrue(Notifier.events([soon], lastState: [:], notified: [], sports: ["Football"],
                                      start: false, final: true, now: now).isEmpty)
    }

    func testFinalOnlyWhenSeenBefore() {
        let done = game("3", .final, at: fixtureNow.addingTimeInterval(-3 * 3600), us: "31", them: "28", won: true)
        // just launched: an old result isn't announced
        XCTAssertTrue(Notifier.events([done], lastState: [:], notified: [], sports: ["Football"],
                                      start: true, final: true, now: fixtureNow).isEmpty)
        let e = Notifier.events([done], lastState: ["3": .live], notified: [], sports: ["Football"],
                                start: true, final: true, now: fixtureNow)
        XCTAssertEqual(e.first?.title, "🏈 Texas State wins 31–28")
        XCTAssertEqual(e.first?.body, "Final at Boise St · Football")
        XCTAssertTrue(Notifier.events([done], lastState: ["3": .final], notified: [], sports: ["Football"],
                                      start: true, final: true, now: fixtureNow).isEmpty)
    }
}

final class MenuIconTests: XCTestCase {
    func image(_ w: Int, _ h: Int, opaque: Bool) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if opaque {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.setFillColor(CGColor(red: 0.3, green: 0.05, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(x: w / 4, y: h / 4, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    func alpha(_ cg: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: -y, width: cg.width, height: cg.height))
        return px[3]
    }

    func testOpaqueLogoBecomesAShape() throws {
        let mask = try XCTUnwrap(MenuIcon.templateMask(image(40, 40, opaque: true)))
        XCTAssertGreaterThan(alpha(mask, 20, 20), 200)   // the dark logo is solid
        XCTAssertLessThan(alpha(mask, 2, 2), 30)          // the white background is clear
    }

    func testTransparentLogoIsUsedAsIs() {
        XCTAssertNil(MenuIcon.templateMask(image(40, 40, opaque: false)))
    }
}
