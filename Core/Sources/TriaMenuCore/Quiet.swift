import Foundation

/// "Open Triathlon quietly": Triathlon writes today's note only when it opens, so this app opens it in the
/// background (hidden, never in front) when the note is not today's, and again every half hour while a
/// session is still to do — and closes that hidden copy again once the note is written.
///
/// Since 0.4.1 it never touches a Triathlon that is already running, and does nothing while the Mac sleeps.
/// Why (27 Nov 2026): the Mac puts a hidden Triathlon (the iPad app) to sleep. The old "close it and open it
/// hidden again" sent a sleeping copy a quit it could not answer; the quit waited, and when Martin later
/// clicked Triathlon it woke up, carried out the waiting quit and closed at once ("not responding").
public enum QuietOpen {
    public enum Step: Equatable {
        case nothing
        /// Triathlon is not running: open it hidden (and close it again after `closeAfter` seconds).
        case open
    }

    /// After a try that did not bring today's note: wait this long before the next.
    public static let retry: Double = 20 * 60
    /// While a session is still to do: look again this often.
    public static let refresh: Double = 30 * 60
    /// After opening it hidden: close that copy again this many seconds later (it writes its note within seconds).
    public static let closeAfter: Double = 20

    /// `sinceLastTry`: seconds since this app last opened Triathlon quietly; nil = not yet since it started.
    /// `asked`: he pressed "Refresh now" or right-clicked (the waiting times do not count then).
    /// `macAwake`: false while the screens or the Mac sleep (a dark wake included).
    public static func step(on: Bool, installed: Bool, noteIsToday: Bool, hasToDo: Bool, running: Bool, macAwake: Bool,
                            sinceLastTry: Double?, asked: Bool = false) -> Step {
        guard installed, on || asked else { return .nothing }
        // A running Triathlon is never touched: his own copy, or one that may be asleep.
        guard !running, macAwake else { return .nothing }
        if !asked {
            if noteIsToday {
                guard hasToDo, (sinceLastTry ?? .infinity) >= refresh else { return .nothing }
            } else {
                guard (sinceLastTry ?? .infinity) >= retry else { return .nothing }
            }
        }
        return .open
    }

    /// Whether the copy this app opened hidden is closed again: only while it is still hidden and not in front
    /// (he may have brought it forward in the meantime) and he did not open Triathlon himself since.
    public static func closeOwnCopy(stillRunning: Bool, hidden: Bool, active: Bool, openedByHimSince: Bool) -> Bool {
        stillRunning && hidden && !active && !openedByHimSince
    }
}
