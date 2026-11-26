import Foundation

/// "Open Triathlon quietly": Triathlon writes today's note only when it opens, so this app opens it in the
/// background (hidden, never in front) when the note is not today's, and again every half hour while a
/// session is still to do. It never touches Triathlon while its window is showing.
public enum QuietOpen {
    public enum Step: Equatable {
        case nothing
        /// Triathlon is not running: open it hidden.
        case open
        /// Triathlon runs hidden: close it politely and open it hidden again, so it reads the plan afresh.
        case restart
    }

    /// After a try that did not bring today's note: wait this long before the next.
    public static let retry: Double = 20 * 60
    /// While a session is still to do: look again this often.
    public static let refresh: Double = 30 * 60

    /// `sinceLastTry`: seconds since this app last opened Triathlon quietly; nil = not yet since it started.
    /// `asked`: he pressed "Refresh now" (the waiting times do not count then).
    public static func step(on: Bool, installed: Bool, noteIsToday: Bool, hasToDo: Bool, running: Bool, showing: Bool,
                            sinceLastTry: Double?, asked: Bool = false) -> Step {
        guard installed, on || asked else { return .nothing }
        if !asked {
            if noteIsToday {
                guard hasToDo, (sinceLastTry ?? .infinity) >= refresh else { return .nothing }
            } else {
                guard (sinceLastTry ?? .infinity) >= retry else { return .nothing }
            }
        }
        if !running { return .open }
        return showing ? .nothing : .restart
    }
}
