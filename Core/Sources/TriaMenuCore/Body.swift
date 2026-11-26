import Foundation

/// One Body Battery reading: when (seconds since 1970) and how much (0 to 100).
public struct BodyPoint: Codable, Equatable {
    public let time: Double
    public let value: Int
    public init(time: Double, value: Int) { self.time = time; self.value = value }
}

/// What the Garmin Board on this Mac says about today (its address: 127.0.0.1:7788/api/board).
public struct BoardBody: Equatable {
    public var day: String
    public var latest: Int?
    public var points: [BodyPoint]
    public var watchSynced: Date?

    public init(day: String, latest: Int?, points: [BodyPoint], watchSynced: Date?) {
        self.day = day; self.latest = latest; self.points = points; self.watchSynced = watchSynced
    }

    /// Reads only what this app needs from the Board's answer; anything missing stays empty.
    public static func read(_ data: Data) -> BoardBody? {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let day = top["date"] as? String else { return nil }
        let today = top["today"] as? [String: Any]
        let battery = today?["bodyBattery"] as? [String: Any]
        let curve = top["bodyBatteryCurve"] as? [String: Any]
        let points = Times.points(curve?["points"])
        let updated = top["updated"] as? [String: Any]
        let synced = (updated?["watchSyncedAt"] as? String ?? top["lastSyncAt"] as? String).flatMap(Times.date)
        return BoardBody(day: day, latest: (battery?["latest"] as? NSNumber)?.intValue ?? points.last?.value,
                         points: points, watchSynced: synced)
    }
}

/// Body Battery as AMS Triathlon Training last read it (its own file beside the today note). Used for
/// yesterday's line, and for today when the Board does not answer.
public struct TriathlonBody: Equatable {
    public var day: String
    public var points: [BodyPoint]
    public var yesterday: [BodyPoint]

    public static func read(_ data: Data) -> TriathlonBody? {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let body = top["body"] as? [String: Any], let day = body["day"] as? String else { return nil }
        let battery = body["battery"] as? [String: Any]
        return TriathlonBody(day: day, points: Times.points(battery?["points"]), yesterday: Times.points(battery?["yesterday"]))
    }
}

enum Times {
    /// Seconds since 1970, whatever the source counts in: thousandths since 1970 (the Board), seconds since
    /// 1970, or seconds since 2001 (how Apple's own apps count; Triathlon's file does). A count from 2001
    /// stays below 1.2 thousand million until 2039, one from 1970 has been above it since 2008.
    static func seconds(_ raw: Double) -> Double {
        if raw > 100_000_000_000 { return raw / 1000 }
        return raw < 1_200_000_000 ? raw + 978_307_200 : raw
    }

    /// Points as pairs ([time, value]) or as {"time":, "value":}; sorted by time.
    static func points(_ raw: Any?) -> [BodyPoint] {
        var out: [BodyPoint] = []
        for one in raw as? [Any] ?? [] {
            if let pair = one as? [NSNumber], pair.count >= 2 {
                out.append(BodyPoint(time: seconds(pair[0].doubleValue), value: pair[1].intValue))
            } else if let named = one as? [String: Any], let time = named["time"] as? NSNumber, let value = named["value"] as? NSNumber {
                out.append(BodyPoint(time: seconds(time.doubleValue), value: value.intValue))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    static func date(_ text: String) -> Date? {
        let fine = ISO8601DateFormatter()
        fine.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fine.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// The app's own memory of each day's curve, so that tomorrow has a "yesterday" even without Triathlon's file.
public struct BodyDays: Codable, Equatable {
    public static let kept = 3
    public var days: [String: [BodyPoint]]

    public init(days: [String: [BodyPoint]] = [:]) { self.days = days }

    /// Remembers a day's curve (the fuller one wins) and forgets all but the newest three days.
    public mutating func keep(day: String, points: [BodyPoint]) {
        guard !points.isEmpty else { return }
        if let have = days[day], have.count > points.count, (have.last?.time ?? 0) >= (points.last?.time ?? 0) { return }
        days[day] = points
        for old in days.keys.sorted().dropLast(Self.kept) { days[old] = nil }
    }
}

/// What the Body Battery card shows.
public struct BodyShown: Equatable {
    /// `waiting`: the Board answers, but the watch has not synced anything for today yet.
    public enum Source: Equatable { case board, triathlon, waiting, none }
    public var latest: Int?
    public var today: [BodyPoint]
    public var yesterday: [BodyPoint]
    public var watchSynced: Date?
    public var source: Source

    public static let empty = BodyShown(latest: nil, today: [], yesterday: [], watchSynced: nil, source: .none)

    public init(latest: Int?, today: [BodyPoint], yesterday: [BodyPoint], watchSynced: Date?, source: Source) {
        self.latest = latest; self.today = today; self.yesterday = yesterday; self.watchSynced = watchSynced; self.source = source
    }

    /// Today from the Garmin Board when it has a reading for today, else from Triathlon's own reading of today.
    /// When the Board answers for today but has nothing yet (the watch has not synced), that is said, not hidden.
    /// Yesterday from Triathlon's reading (the same line as on its Body page), else from this app's memory.
    public static func choose(board: BoardBody?, triathlon: TriathlonBody?, kept: BodyDays, today: String, yesterday: String?) -> BodyShown {
        var shown = BodyShown.empty
        let fresh = triathlon.flatMap { $0.day == today ? $0 : nil }
        if let board, board.day == today, board.latest != nil || !board.points.isEmpty {
            shown.latest = board.latest ?? board.points.last?.value
            shown.today = board.points
            shown.watchSynced = board.watchSynced
            shown.source = .board
        } else if let fresh, let last = fresh.points.last {
            shown.latest = last.value
            shown.today = fresh.points
            shown.source = .triathlon
        } else if let board, board.day == today {
            shown.source = .waiting
        }
        if let fresh, !fresh.yesterday.isEmpty {
            shown.yesterday = fresh.yesterday
        } else if let triathlon, let yesterday, triathlon.day == yesterday, !triathlon.points.isEmpty {
            // Triathlon has not read today yet: what it holds as "today" is yesterday's curve.
            shown.yesterday = triathlon.points
        } else if let yesterday, let mine = kept.days[yesterday] {
            shown.yesterday = mine
        }
        return shown
    }

    /// The words under the number.
    public func smallWords(now: Date, calendar: Calendar = .current) -> String {
        switch source {
        case .board: return Words.synced(watchSynced, now: now, calendar: calendar)
        case .triathlon: return "as Triathlon last read it"
        case .waiting: return "no reading yet today"
        case .none: return "Garmin Board not answering"
        }
    }
}

/// Where a reading sits in the small curve: across the day (0 at midnight, 1 at the next), up by its value.
public enum BodyCurve {
    public struct Spot: Equatable { public let x: Double; public let y: Double }

    public static func spots(_ points: [BodyPoint], dayStart: Double) -> [Spot] {
        points.compactMap { point in
            let x = (point.time - dayStart) / 86_400
            guard x >= -0.001, x <= 1.001 else { return nil }
            return Spot(x: min(max(x, 0), 1), y: min(max(Double(point.value) / 100, 0), 1))
        }
    }
}
