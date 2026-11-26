import XCTest
@testable import TriaMenuCore

/// All values here are invented.
final class RulesTests: XCTestCase {
    private let sample = """
    {"v":1,"day":"2026-12-01","dayWords":"Tue 1 Dec","written":"2026-12-01T06:50:12Z","someNewField":7,
     "sessions":[
      {"key":"w12-tue-run","sport":"run","sportWord":"Run","title":"Easy run","minutes":45,"length":"45 min",
       "state":"todo","canDone":true,"open":"amsworkoutsync://session/w12-tue-run","done":"amsworkoutsync://done/w12-tue-run"},
      {"key":"w12-tue-swim","sport":"swim","sportWord":"Swim","title":"Drills","minutes":40,"length":"40 min",
       "state":"done","canDone":false,"open":"amsworkoutsync://session/w12-tue-swim"}],
     "tomorrow":"Bike, 1 h 10 min","week":"40 min done of 3 h 35 min planned","weekDoneMinutes":40,"weekPlannedMinutes":215}
    """

    private func note(_ text: String? = nil) -> TodayNote? {
        if case .note(let note) = TodayNote.read(Data((text ?? sample).utf8)) { return note }
        return nil
    }

    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testReadsTheNoteAndIgnoresWhatItDoesNotKnow() {
        let note = note()
        XCTAssertEqual(note?.sessions.count, 2)
        XCTAssertEqual(note?.sessions.first?.state, .todo)
        XCTAssertEqual(note?.sessions.first?.open, "amsworkoutsync://session/w12-tue-run")
        XCTAssertEqual(note?.tomorrow, "Bike, 1 h 10 min")
        XCTAssertEqual(note?.weekPlannedMinutes, 215)
        XCTAssertEqual(note?.written, at("2026-12-01T06:50:12Z"))
        XCTAssertEqual(TodayNote.read(Data(#"{"v":2,"day":"2026-12-01"}"#.utf8)), .newer, "a newer format is not guessed at")
        XCTAssertEqual(TodayNote.read(Data("not a note".utf8)), .unreadable)
    }

    func testNeverYesterdaysSession() {
        let note = note()!
        XCTAssertTrue(note.counts(today: "2026-12-01", now: at("2026-12-01T18:00:00Z")))
        XCTAssertFalse(note.counts(today: "2026-12-02", now: at("2026-12-02T05:00:00Z")), "another day: nothing")
        XCTAssertFalse(note.counts(today: "2026-12-01", now: at("2026-12-03T00:00:00Z")), "older than 36 hours: nothing")
    }

    func testDayNames() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        XCTAssertEqual(DayKey.of(at("2026-12-01T23:30:00Z"), calendar: calendar), "2026-12-02", "the Mac's own day, not London's")
        XCTAssertEqual(DayKey.before("2026-12-01", calendar: calendar), "2026-11-30")
    }

    func testTheMarkInTheMenuBar() {
        XCTAssertEqual(Face.of(nil), .grey(sport: nil))
        XCTAssertEqual(Face.of(note()), .toDo(sport: "run"), "the first session still to do, though it is second in time")
        var done = note()!
        done.sessions[0].state = .done
        XCTAssertEqual(Face.of(done), .done)
        let rest = TodayNote(day: "2026-12-01", sessions: [.init(key: "r", sport: "rest", sportWord: "Rest", state: .rest)])
        XCTAssertEqual(Face.of(rest), .rest)
        let missed = TodayNote(day: "2026-12-01", sessions: [.init(key: "m", sport: "bike", sportWord: "Bike", state: .missed)])
        XCTAssertEqual(Face.of(missed), .grey(sport: "bike"))
        XCTAssertEqual(Face.of(TodayNote(day: "2026-12-01")), .rest, "nothing planned reads as a rest day")
    }

    func testWords() {
        let note = note()!
        XCTAssertEqual(Words.session(note.sessions[0]), "Run 45 min")
        XCTAssertEqual(Words.session(.init(key: "x", sport: "rest", sportWord: "Rest", state: .rest)), "Rest")
        XCTAssertEqual(Words.number(44), "44")
        XCTAssertEqual(Words.number(nil), "\u{2013}")
        XCTAssertEqual(Words.hover(note: note, battery: 44), "Run 45 min, to do \u{00B7} Swim 40 min, done\nBody Battery 44")
        XCTAssertEqual(Words.hover(note: nil, battery: nil), "No note for today yet\nBody Battery not known")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Words.synced(at("2026-12-01T15:09:00Z"), now: at("2026-12-01T18:00:00Z"), calendar: calendar), "watch synced 15:09")
        XCTAssertEqual(Words.synced(at("2026-11-30T22:10:00Z"), now: at("2026-12-01T07:00:00Z"), calendar: calendar), "watch synced Mon 22:10")
        XCTAssertEqual(Week.share(done: 40, planned: 215)!, 40.0 / 215.0, accuracy: 0.0001)
        XCTAssertNil(Week.share(done: 40, planned: 0))
        XCTAssertEqual(Week.share(done: 300, planned: 215), 1)
    }

    func testReadsTheBoardAndTriathlonsOwnReading() {
        let board = BoardBody.read(Data("""
        {"ok":true,"date":"2026-12-01","today":{"bodyBattery":{"latest":44,"min":44,"max":77}},
         "bodyBatteryCurve":{"points":[[1796108400000,77],[1796097600000,60],[1796137200000,44]]},
         "updated":{"watchSyncedAt":"2026-12-01T15:09:00.000Z"}}
        """.utf8))
        XCTAssertEqual(board?.latest, 44)
        XCTAssertEqual(board?.points.map(\.value), [60, 77, 44], "sorted by time")
        XCTAssertEqual(board?.points.first?.time, 1_796_097_600, "thousandths become seconds")
        XCTAssertEqual(board?.watchSynced, at("2026-12-01T15:09:00Z"))
        let own = TriathlonBody.read(Data("""
        {"body":{"day":"2026-12-01","battery":{"points":[{"time":817790400,"value":60}],
         "yesterday":[{"time":817704000,"value":38},{"time":817742800,"value":70}]}},"lastTried":1.0}
        """.utf8))
        XCTAssertEqual(own?.points.first?.time, 1_796_097_600, "Triathlon counts from 2001; here it is from 1970 like the rest")
        XCTAssertEqual(own?.yesterday.map(\.value), [38, 70])
        XCTAssertNil(BoardBody.read(Data("{}".utf8)))
    }

    func testWhichBodyBatteryIsShown() {
        let board = BoardBody(day: "2026-12-01", latest: 44, points: [BodyPoint(time: 10, value: 44)], watchSynced: nil)
        let own = TriathlonBody(day: "2026-12-01", points: [BodyPoint(time: 5, value: 50)], yesterday: [BodyPoint(time: 1, value: 30)])
        var kept = BodyDays()
        kept.keep(day: "2026-11-30", points: [BodyPoint(time: 2, value: 33), BodyPoint(time: 3, value: 35)])

        let both = BodyShown.choose(board: board, triathlon: own, kept: kept, today: "2026-12-01", yesterday: "2026-11-30")
        XCTAssertEqual(both.source, .board)
        XCTAssertEqual(both.latest, 44)
        XCTAssertEqual(both.yesterday.map(\.value), [30], "Triathlon's yesterday, the same line as on its Body page")

        let noBoard = BodyShown.choose(board: nil, triathlon: own, kept: kept, today: "2026-12-01", yesterday: "2026-11-30")
        XCTAssertEqual(noBoard.source, .triathlon)
        XCTAssertEqual(noBoard.latest, 50)

        let oldBoard = BoardBody(day: "2026-11-30", latest: 61, points: [], watchSynced: nil)
        let mine = BodyShown.choose(board: oldBoard, triathlon: nil, kept: kept, today: "2026-12-01", yesterday: "2026-11-30")
        XCTAssertEqual(mine.source, .none, "the Board's answer for another day is not today's number")
        XCTAssertNil(mine.latest)
        XCTAssertEqual(mine.yesterday.map(\.value), [33, 35], "the app's own memory of yesterday")

        // Early morning: the Board answers for today, but the watch has not synced yet.
        let early = BoardBody(day: "2026-12-01", latest: nil, points: [], watchSynced: nil)
        let stale = TriathlonBody(day: "2026-11-30", points: [BodyPoint(time: 4, value: 61)], yesterday: [BodyPoint(time: 1, value: 20)])
        let morning = BodyShown.choose(board: early, triathlon: stale, kept: kept, today: "2026-12-01", yesterday: "2026-11-30")
        XCTAssertEqual(morning.source, .waiting)
        XCTAssertNil(morning.latest, "never yesterday's number as today's")
        XCTAssertEqual(morning.smallWords(now: Date()), "no reading yet today")
        XCTAssertEqual(morning.yesterday.map(\.value), [61], "what Triathlon still holds as today is yesterday's curve")
    }

    func testTheAppsMemoryOfDays() {
        var kept = BodyDays()
        for day in ["2026-11-27", "2026-11-28", "2026-11-29", "2026-11-30"] { kept.keep(day: day, points: [BodyPoint(time: 1, value: 1)]) }
        XCTAssertEqual(kept.days.keys.sorted(), ["2026-11-28", "2026-11-29", "2026-11-30"], "three days, the oldest goes")
        kept.keep(day: "2026-11-30", points: [])
        XCTAssertEqual(kept.days["2026-11-30"]?.count, 1, "an empty answer does not wipe a day")
        let spots = BodyCurve.spots([BodyPoint(time: 43_200, value: 50), BodyPoint(time: 200_000, value: 9)], dayStart: 0)
        XCTAssertEqual(spots, [BodyCurve.Spot(x: 0.5, y: 0.5)], "noon sits in the middle; another day's reading is left out")
    }

    func testOpeningTriathlonQuietly() {
        func step(on: Bool = true, installed: Bool = true, today: Bool, toDo: Bool = false, running: Bool = false, showing: Bool = false,
                  since: Double? = nil, asked: Bool = false) -> QuietOpen.Step {
            QuietOpen.step(on: on, installed: installed, noteIsToday: today, hasToDo: toDo, running: running, showing: showing,
                           sinceLastTry: since, asked: asked)
        }
        XCTAssertEqual(step(today: false), .open, "morning: no note for today, Triathlon closed")
        XCTAssertEqual(step(today: false, running: true), .restart, "left running hidden overnight")
        XCTAssertEqual(step(today: false, running: true, showing: true), .nothing, "never while its window is showing")
        XCTAssertEqual(step(today: false, since: 60), .nothing, "a try a minute ago: wait")
        XCTAssertEqual(step(today: false, since: 21 * 60), .open)
        XCTAssertEqual(step(today: true, toDo: true, running: true, since: 10 * 60), .nothing)
        XCTAssertEqual(step(today: true, toDo: true, running: true, since: 31 * 60), .restart, "a session to do: look again each half hour")
        XCTAssertEqual(step(today: true, toDo: false, since: 5 * 3600), .nothing, "all done: left in peace")
        XCTAssertEqual(step(on: false, today: false), .nothing, "switched off")
        XCTAssertEqual(step(on: false, today: true, since: 5, asked: true), .open, "Refresh now works even when switched off")
        XCTAssertEqual(step(installed: false, today: false, asked: true), .nothing)
    }

    func testKeeperAndPlace() {
        let order = Keeper.plist(executable: "/Applications/X.app/Contents/MacOS/X", bundleID: "com.schabbauer.AMSTriaMenu")
        XCTAssertEqual(order["ProgramArguments"] as? [String], ["/Applications/X.app/Contents/MacOS/X", "--keeper"])
        XCTAssertEqual((order["KeepAlive"] as? [String: Bool])?["SuccessfulExit"], false)
        XCTAssertTrue(Keeper.handsOver(wanted: true, openedByKeeper: false, plain: false, inApplications: true))
        XCTAssertFalse(Keeper.handsOver(wanted: true, openedByKeeper: true, plain: false, inApplications: true))
        XCTAssertTrue(BarPlace.needsRepair(saved: 8250, visible: false, unseenSeconds: 11))
        XCTAssertFalse(BarPlace.needsRepair(saved: 236, visible: false, unseenSeconds: 60))
        let me = OneCopy.Copy(started: 10, pid: 5)
        XCTAssertEqual(OneCopy.earlier(than: me, among: [.init(started: 9, pid: 9), .init(started: 11, pid: 1)]).count, 1)
    }
}
