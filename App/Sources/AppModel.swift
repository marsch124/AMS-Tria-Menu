import AppKit
import Combine
import TriaMenuCore

/// Where things are on this Mac.
enum Places {
    static let triathlonID = "com.schabbauer.AMSWorkoutSync"
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Triathlon runs as the iPad app, so its files sit in its own closed folder.
    private static var triathlonFolder: URL {
        home.appendingPathComponent("Library/Containers/\(triathlonID)/Data/Library/Application Support")
    }
    static var note: URL { triathlonFolder.appendingPathComponent("today-note.json") }
    static var triathlonBody: URL { triathlonFolder.appendingPathComponent("garmin-body.json") }
    static var bodyDays: URL { home.appendingPathComponent("Library/Application Support/AMS Tria Menu/body-days.json") }
    static let board = URL(string: "http://127.0.0.1:7788/api/board")!

    /// The Triathlon app itself. Only a copy in an Applications folder counts: build folders hold copies
    /// with the same name that cannot run on the Mac.
    static var triathlonApp: URL? {
        for path in ["/Applications/Triathlon.app", home.path + "/Applications/Triathlon.app"]
        where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: triathlonID), found.path.contains("/Applications/") {
            return found
        }
        return nil
    }
}

/// Everything the menu bar mark and the panel show, and the reading that keeps it fresh.
final class AppModel: ObservableObject {
    /// Today's note; nil when there is none that counts today.
    @Published private(set) var note: TodayNote?
    @Published private(set) var noNote: NoNote? = .missing
    @Published private(set) var body: BodyShown = .empty
    @Published private(set) var face: Face = .grey(sport: nil)
    @Published private(set) var boardAnswered: Date?
    @Published private(set) var busy = false
    @Published var quietOn: Bool {
        didSet { if live { UserDefaults.standard.set(quietOn, forKey: Self.quietKey) } }
    }
    /// For the words that depend on the time; moves with every look.
    @Published private(set) var now = Date()

    var panelOpen = false {
        didSet { if panelOpen, !oldValue { panelOpened() } }
    }

    static let quietKey = "openTriathlonQuietly"
    private static let lastTryKey = "lastQuietTry"

    private let live: Bool
    private let io = DispatchQueue(label: "com.schabbauer.AMSTriaMenu.reading")
    private var timer: Timer?
    private var noteBusy = false
    private var boardBusy = false
    private var board: BoardBody?
    private var triathlonBody: TriathlonBody?
    private var kept = BodyDays()
    private var boardTried: Date?
    private var shownDay = ""
    private var lastNoNote: NoNote?

    init(live: Bool = true) {
        self.live = live
        quietOn = UserDefaults.standard.object(forKey: Self.quietKey) as? Bool ?? true
        guard live else { return }
        if let data = try? Data(contentsOf: Places.bodyDays), let days = try? JSONDecoder().decode(BodyDays.self, from: data) {
            kept = days
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.look() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        look()
    }

    @objc private func woke() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.look() }
    }

    // MARK: Looking

    /// Once a minute: read the note; ask the Board when it is time; open Triathlon quietly when that is due.
    private func look() {
        readNote { [weak self] in self?.quietStep(asked: false) }
        if (boardTried.map { Date().timeIntervalSince($0) } ?? .infinity) >= 30 * 60 { askBoard() }
    }

    private func panelOpened() {
        readNote(then: nil)
        if (boardTried.map { Date().timeIntervalSince($0) } ?? .infinity) >= 5 * 60 { askBoard() }
    }

    /// "Refresh now": read again, ask the Board, and let Triathlon write its note afresh.
    func refreshNow() {
        Diary.note("Refresh now")
        askBoard()
        readNote { [weak self] in self?.quietStep(asked: true) }
    }

    private enum NoteRead { case result(TodayNote.ReadResult), missing, notAllowed }

    private func readNote(then: (() -> Void)?) {
        guard live, !noteBusy else { return }
        noteBusy = true
        io.async { [weak self] in
            // The first read makes the Mac ask once whether this app may read another app's data; the read
            // waits for the answer, which is why it never happens on the main thread.
            var read = NoteRead.missing
            do {
                read = .result(TodayNote.read(try Data(contentsOf: Places.note)))
            } catch let error as NSError {
                let denied = error.code == NSFileReadNoPermissionError || (error.underlyingErrors.first as NSError?)?.code == Int(EPERM)
                read = denied ? .notAllowed : .missing
            }
            let own = (try? Data(contentsOf: Places.triathlonBody)).flatMap(TriathlonBody.read)
            DispatchQueue.main.async {
                guard let self else { return }
                self.noteBusy = false
                self.triathlonBody = own
                self.take(read)
                then?()
            }
        }
    }

    private func take(_ read: NoteRead) {
        now = Date()
        let today = DayKey.of(now)
        var fresh: TodayNote?
        var why: NoNote?
        switch read {
        case .result(.note(let one)):
            if one.counts(today: today, now: now) { fresh = one } else { why = .notToday }
        case .result(.newer): why = .newer
        case .result(.unreadable), .missing: why = Places.triathlonApp == nil ? .notInstalled : .missing
        case .notAllowed: why = .notAllowed
        }
        if why != lastNoNote {
            lastNoNote = why
            Diary.note(why.map { "No note to show: \($0)" } ?? "Today's note read: \(fresh?.sessions.count ?? 0) session(s)")
        }
        if note != fresh { note = fresh }
        if noNote != why { noNote = why }
        let mark = Face.of(fresh)
        if face != mark { face = mark }
        // A new day: yesterday's Body Battery is not today's.
        if shownDay != today {
            let first = shownDay.isEmpty
            shownDay = today
            if !first { askBoard() }
        }
        showBody()
    }

    private func showBody() {
        let today = DayKey.of(now)
        let shown = BodyShown.choose(board: board, triathlon: triathlonBody, kept: kept, today: today, yesterday: DayKey.before(today))
        if body != shown { body = shown }
    }

    private func askBoard() {
        guard live, !boardBusy else { return }
        boardBusy = true
        boardTried = Date()
        var request = URLRequest(url: Places.board)
        request.timeoutInterval = 40
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let answer = data.flatMap(BoardBody.read)
            DispatchQueue.main.async {
                guard let self else { return }
                self.boardBusy = false
                // No answer: what the Board said before stays (it still counts only on its own day).
                if let answer {
                    if self.boardAnswered == nil { Diary.note("The Garmin Board answers") }
                    self.board = answer
                    self.boardAnswered = Date()
                    var days = self.kept
                    days.keep(day: answer.day, points: answer.points)
                    if days != self.kept {
                        self.kept = days
                        self.saveDays()
                    }
                } else if self.boardAnswered != nil || self.board == nil {
                    if self.boardAnswered != nil { Diary.note("The Garmin Board does not answer") }
                    self.boardAnswered = nil
                }
                self.now = Date()
                self.showBody()
            }
        }.resume()
    }

    private func saveDays() {
        let days = kept
        io.async {
            let url = Places.bodyDays
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(days) { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: Triathlon

    private var runningTriathlon: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Places.triathlonID).first { !$0.isTerminated }
    }

    /// Opens Triathlon in the background when its note is not today's, and again each half hour while a
    /// session is still to do. Rule: `QuietOpen`.
    private func quietStep(asked: Bool) {
        guard live else { return }
        let store = UserDefaults.standard
        let last = store.object(forKey: Self.lastTryKey) as? Double
        let app = runningTriathlon
        let step = QuietOpen.step(on: quietOn, installed: Places.triathlonApp != nil, noteIsToday: note != nil,
                                  hasToDo: note?.hasToDo ?? false, running: app != nil,
                                  showing: app.map { $0.isActive || !$0.isHidden } ?? false,
                                  sinceLastTry: last.map { Date().timeIntervalSince1970 - $0 }, asked: asked)
        guard step != .nothing else { return }
        store.set(Date().timeIntervalSince1970, forKey: Self.lastTryKey)
        busy = true
        if step == .restart, let app {
            Diary.note("Triathlon runs hidden; closing it and opening it hidden again for a fresh note")
            app.terminate()
            waitUntilGone(app, tries: 20) { [weak self] in self?.openHidden() }
        } else {
            Diary.note("Opening Triathlon in the background for today's note")
            openHidden()
        }
    }

    private func waitUntilGone(_ app: NSRunningApplication, tries: Int, then: @escaping () -> Void) {
        if app.isTerminated || tries == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: then)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.waitUntilGone(app, tries: tries - 1, then: then) }
        }
    }

    private func openHidden() {
        guard let url = Places.triathlonApp else { busy = false; return }
        let how = NSWorkspace.OpenConfiguration()
        how.activates = false
        how.hides = true
        how.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: how) { _, error in
            if let error { DispatchQueue.main.async { Diary.note("Triathlon did not open: \(error.localizedDescription)") } }
        }
        readSoon([3, 8, 20])
    }

    /// Reads the note again a few times after Triathlon was opened: it writes within seconds.
    private func readSoon(_ seconds: [Double]) {
        for (index, wait) in seconds.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.readNote(then: nil)
                if index == seconds.count - 1 { self?.busy = false }
            }
        }
    }

    /// Brings Triathlon to the front, at a session when there is one. Only Triathlon's own links are followed.
    func openTriathlon(_ session: TodayNote.Session? = nil) {
        guard let app = Places.triathlonApp else { return }
        let how = NSWorkspace.OpenConfiguration()
        how.activates = true
        if let link = session?.open, link.hasPrefix("amsworkoutsync://"), let url = URL(string: link) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: how)
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: how)
        }
        readSoon([3, 10])
    }

    var triathlonInstalled: Bool { Places.triathlonApp != nil }

    // MARK: Words for Settings and for checks

    var noteLine: String {
        if let note {
            guard let written = note.written else { return note.sessions.count == 1 ? "Read. 1 session today." : "Read. \(note.sessions.count) sessions today." }
            let clock = DateFormatter()
            clock.dateFormat = "HH:mm"
            return "Written by Triathlon at \(clock.string(from: written))."
        }
        return noNote?.words ?? ""
    }

    var bodyLine: String {
        switch body.source {
        case .board: return "From the Garmin Board on this Mac. " + Words.synced(body.watchSynced, now: now).capitalizedFirst + "."
        case .triathlon: return "The Garmin Board is not answering. Shown as Triathlon last read it."
        case .waiting: return "The Garmin Board answers, but it has no reading for today yet. It comes when the watch has synced."
        case .none: return "The Garmin Board is not answering, and Triathlon has no reading for today."
        }
    }

    /// For checks: what the app reads right now, in a few lines. Waits for the reading.
    static func readout() -> String {
        let model = AppModel(live: true)
        let until = Date().addingTimeInterval(45)
        while Date() < until, model.noteBusy || model.boardBusy {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        var lines = ["mark: \(model.face)", "number: \(Words.number(model.body.latest))"]
        if let note = model.note {
            lines.append("day: \(note.day) · sessions: " + note.sessions.map { "\($0.sport)/\($0.state.rawValue)" }.joined(separator: ", "))
            lines.append("tomorrow: \(note.tomorrow ?? "none") · week: \(note.week ?? "none")")
        } else {
            lines.append("no note: \(model.noNote.map { "\($0)" } ?? "?")")
        }
        lines.append("body: source \(model.body.source), today \(model.body.today.count) readings, yesterday \(model.body.yesterday.count)")
        lines.append("triathlon: \(Places.triathlonApp?.path ?? "not found")")
        return lines.joined(separator: "\n")
    }

    // MARK: Samples for pictures (invented values)

    enum SampleKind { case toDo, allDone, rest, noNote, missed, noBody, waiting, long }

    static func sample(_ kind: SampleKind) -> AppModel {
        let model = AppModel(live: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!.timeIntervalSince1970
        model.now = Date(timeIntervalSince1970: start + 15.5 * 3600)
        func hours(_ pairs: [(Double, Int)], day: Double) -> [BodyPoint] { pairs.map { BodyPoint(time: day + $0.0 * 3600, value: $0.1) } }
        let swim = TodayNote.Session(key: "w12-tue-swim", sport: "swim", sportWord: "Swim", title: "Drills, easy", minutes: 40, length: "40 min", state: .done)
        let run = TodayNote.Session(key: "w12-tue-run", sport: "run", sportWord: "Run", title: "Easy run, flat; keep the pulse low", minutes: 45, length: "45 min", state: .todo)
        var note = TodayNote(day: "2026-12-01", dayWords: "Tue 1 Dec", sessions: [swim, run], tomorrow: "Bike, 1 h 10 min",
                             week: "40 min done of 3 h 35 min planned", weekDoneMinutes: 40, weekPlannedMinutes: 215)
        var body = BodyShown(latest: 44, today: hours([(0, 36), (3, 58), (6.75, 77), (10, 71), (12.5, 62), (14.6, 44)], day: start),
                             yesterday: hours([(0, 38), (3, 55), (6.5, 82), (9, 74), (12, 60), (15, 49), (18, 41), (21, 33), (23.9, 36)], day: start - 86_400),
                             watchSynced: Date(timeIntervalSince1970: start + 15.15 * 3600), source: .board)
        switch kind {
        case .toDo: break
        case .allDone:
            note.sessions[1].state = .done
            note.week = "1 h 25 min done of 3 h 35 min planned"
            note.weekDoneMinutes = 85
            body.latest = 38
        case .rest:
            note.sessions = [.init(key: "w12-tue-rest", sport: "rest", sportWord: "Rest", state: .rest)]
            note.tomorrow = "Swim, 40 min"
            body.latest = 71
        case .missed:
            note.sessions = [.init(key: "w12-tue-bike", sport: "bike", sportWord: "Bike", title: "Steady ride", minutes: 70, length: "1 h 10 min", state: .missed)]
        case .long:
            note.sessions = [.init(key: "w12-tue-run", sport: "run", sportWord: "Run", title: "Hill repeats, six times up the long slope, jog down between them",
                                   minutes: 30, length: "30 min", state: .todo),
                             .init(key: "w12-tue-str", sport: "strength", sportWord: "Strength", title: "Gym, legs", minutes: 50, length: "50 min", state: .todo),
                             .init(key: "w12-tue-bike", sport: "bike", sportWord: "Bike", title: "Spin", minutes: 30, length: "30 min", state: .todo)]
        case .noNote:
            model.noNote = .missing
            model.body = body
            return model
        case .noBody:
            body = .empty
        case .waiting:
            body = BodyShown(latest: nil, today: [], yesterday: body.yesterday, watchSynced: nil, source: .waiting)
        }
        model.note = note
        model.noNote = nil
        model.face = Face.of(note)
        model.body = body
        return model
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
