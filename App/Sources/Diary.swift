import Foundation

/// A short diary of what happened, kept on this Mac only, so that a problem can be checked afterwards
/// without anybody having to describe it: times and what the app did, no training or health figures.
enum Diary {
    /// Only the newest lines are kept.
    static let keep = 300
    private static let queue = DispatchQueue(label: "com.schabbauer.AMSTriaMenu.diary")
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AMS Tria Menu/diary.log")
    }
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Waits until everything noted so far is written — for a copy that quits right after a note.
    static func finish() { queue.sync {} }

    /// Call on the main thread.
    static func note(_ text: String) {
        let line = stamp.string(from: Date()) + "  " + text
        queue.async {
            let url = file
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            lines.append(line)
            if lines.count > keep { lines.removeFirst(lines.count - keep) }
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
