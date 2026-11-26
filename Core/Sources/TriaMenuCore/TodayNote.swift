import Foundation

/// The small "today" note AMS Triathlon Training writes on the Mac (format 1). This app only reads it.
/// Contract: Triathlon is the only writer; readers ignore unknown fields; a format above the one they
/// know means: show nothing.
public struct TodayNote: Equatable {
    public enum State: String, Equatable { case todo, done, missed, rest, other }

    public struct Session: Equatable, Identifiable {
        public var key: String
        public var sport: String
        public var sportWord: String
        public var title: String
        public var minutes: Int?
        public var length: String
        public var state: State
        /// The link that opens this session in Triathlon.
        public var open: String?
        public var id: String { key }

        public init(key: String, sport: String, sportWord: String, title: String = "", minutes: Int? = nil,
                    length: String = "", state: State, open: String? = nil) {
            self.key = key; self.sport = sport; self.sportWord = sportWord; self.title = title
            self.minutes = minutes; self.length = length; self.state = state; self.open = open
        }
    }

    public static let knownFormat = 1

    public var day: String
    public var dayWords: String
    public var written: Date?
    public var sessions: [Session]
    public var tomorrow: String?
    public var week: String?
    public var weekDoneMinutes: Int?
    public var weekPlannedMinutes: Int?

    public init(day: String, dayWords: String = "", written: Date? = nil, sessions: [Session] = [], tomorrow: String? = nil,
                week: String? = nil, weekDoneMinutes: Int? = nil, weekPlannedMinutes: Int? = nil) {
        self.day = day; self.dayWords = dayWords; self.written = written; self.sessions = sessions
        self.tomorrow = tomorrow; self.week = week
        self.weekDoneMinutes = weekDoneMinutes; self.weekPlannedMinutes = weekPlannedMinutes
    }

    public enum ReadResult: Equatable { case note(TodayNote), newer, unreadable }

    /// Reads the note's bytes. Unknown fields are ignored, missing ones are empty; a newer format is not guessed at.
    public static func read(_ data: Data) -> ReadResult {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let format = top["v"] as? Int, let day = top["day"] as? String, !day.isEmpty else { return .unreadable }
        guard format <= knownFormat else { return .newer }
        var note = TodayNote(day: day)
        note.dayWords = top["dayWords"] as? String ?? ""
        note.written = (top["written"] as? String).flatMap(date)
        note.tomorrow = (top["tomorrow"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        note.week = (top["week"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        note.weekDoneMinutes = top["weekDoneMinutes"] as? Int
        note.weekPlannedMinutes = top["weekPlannedMinutes"] as? Int
        for one in top["sessions"] as? [[String: Any]] ?? [] {
            guard let key = one["key"] as? String else { continue }
            let sport = one["sport"] as? String ?? "other"
            note.sessions.append(Session(key: key, sport: sport,
                                         sportWord: one["sportWord"] as? String ?? sport.capitalized,
                                         title: one["title"] as? String ?? "",
                                         minutes: one["minutes"] as? Int,
                                         length: one["length"] as? String ?? "",
                                         state: State(rawValue: one["state"] as? String ?? "") ?? .other,
                                         open: one["open"] as? String))
        }
        return .note(note)
    }

    private static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fine = ISO8601DateFormatter()
        fine.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fine.date(from: text)
    }

    /// Never yesterday's session: a note counts only on its own day, and only for 36 hours.
    public static let tooOldAfter: Double = 36 * 3600

    public func counts(today: String, now: Date) -> Bool {
        guard day == today else { return false }
        if let written, now.timeIntervalSince(written) > Self.tooOldAfter { return false }
        return true
    }

    public var hasToDo: Bool { sessions.contains { $0.state == .todo } }
}

/// A day as the note names it: "2026-12-01", in the Mac's own time zone.
public enum DayKey {
    public static func of(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The first moment of that day.
    public static func start(of key: String, calendar: Calendar = .current) -> Date? {
        let numbers = key.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2]))
    }

    public static func before(_ key: String, calendar: Calendar = .current) -> String? {
        guard let start = start(of: key, calendar: calendar),
              let earlier = calendar.date(byAdding: .day, value: -1, to: start) else { return nil }
        return of(earlier, calendar: calendar)
    }
}

/// Why there is nothing to show for today.
public enum NoNote: Equatable {
    case notInstalled, notAllowed, missing, notToday, newer

    /// The grey words in the panel.
    public var words: String {
        switch self {
        case .notInstalled: return "AMS Triathlon Training is not on this Mac."
        case .notAllowed: return "The Mac did not let AMS Tria Menu read Triathlon's note. Allow it in System Settings, Privacy & Security."
        case .missing, .notToday: return "No note for today yet. Triathlon writes it when it opens."
        case .newer: return "Triathlon's note is newer than this version understands. AMS Tria Menu needs an update."
        }
    }
}

/// What the mark in the menu bar is.
public enum Face: Equatable {
    /// A session is still to do: that sport's mark, in the sport's colour.
    case toDo(sport: String)
    /// Nothing left to do and at least one session done: the green tick.
    case done
    /// A rest day (or nothing planned): the moon.
    case rest
    /// Grey: no note for today (sport nil), or today's session was missed.
    case grey(sport: String?)

    public static func of(_ note: TodayNote?) -> Face {
        guard let note else { return .grey(sport: nil) }
        if let next = note.sessions.first(where: { $0.state == .todo }) { return .toDo(sport: next.sport) }
        if note.sessions.contains(where: { $0.state == .done }) { return .done }
        if let missed = note.sessions.first(where: { $0.state == .missed }) { return .grey(sport: missed.sport) }
        return .rest
    }
}

public enum Words {
    /// "Run 45 min": the length right beside the sport.
    public static func session(_ session: TodayNote.Session) -> String {
        session.length.isEmpty ? session.sportWord : "\(session.sportWord) \(session.length)"
    }

    public static func state(_ state: TodayNote.State) -> String {
        switch state {
        case .todo: return "to do"
        case .done: return "done"
        case .missed: return "missed"
        case .rest: return "rest day"
        case .other: return ""
        }
    }

    /// The number beside the mark: Body Battery, or a dash when there is none.
    public static func number(_ battery: Int?) -> String { battery.map(String.init) ?? "\u{2013}" }

    /// What the pointer resting on the mark says.
    public static func hover(note: TodayNote?, battery: Int?) -> String {
        var parts: [String] = []
        if let note {
            let lines = note.sessions.filter { $0.state != .rest }.map { "\(session($0)), \(state($0.state))" }
            parts.append(lines.isEmpty ? "Rest day" : lines.joined(separator: " \u{00B7} "))
        } else {
            parts.append("No note for today yet")
        }
        parts.append(battery.map { "Body Battery \($0)" } ?? "Body Battery not known")
        return parts.joined(separator: "\n")
    }

    /// "watch synced 15:09", or with the day when it was not today.
    public static func synced(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let clock = DateFormatter()
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "en_GB")
        clock.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return "watch synced " + clock.string(from: date)
    }
}

/// The slim bar under "This week".
public enum Week {
    public static func share(done: Int?, planned: Int?) -> Double? {
        guard let done, let planned, planned > 0 else { return nil }
        return min(max(Double(done) / Double(planned), 0), 1)
    }
}
