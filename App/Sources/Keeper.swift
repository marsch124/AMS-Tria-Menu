import AppKit
import Darwin
import TriaMenuCore
import ServiceManagement

/// The keeper at work: writes the start order down for the Mac, looks whether the Mac knows it, and lets a
/// copy opened by hand give way to the copy the keeper opens. Rules: `Keeper` and `OneCopy` in Core.
///
/// Why: on 17 Nov 2026 the Mac restarted, "Open at login" was on, and the Mac's own login list could not
/// find the app ("Unable to resolve startup item"), so the menu bar icon stayed missing.
enum KeeperJob {
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Keeper.label).plist")
    }
    private static var domain: String { "gui/\(getuid())" }
    private static var service: String { "\(domain)/\(Keeper.label)" }

    static var openedByKeeper: Bool { CommandLine.arguments.contains(Keeper.argument) }
    static var plain: Bool { CommandLine.arguments.contains(Keeper.plainArgument) }
    /// A copy in a build folder never becomes the one the Mac opens at login.
    static var inApplications: Bool { Bundle.main.bundlePath.contains("/Applications/") }

    /// What "Open at login" was last set to; never set = what the Mac's login list says.
    static var wanted: Bool {
        UserDefaults.standard.object(forKey: LoginItem.wantedKey) as? Bool ?? (SMAppService.mainApp.status == .enabled)
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> (code: Int32, text: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// The Mac knows the start order (for this login).
    static var loaded: Bool { launchctl(["print", service]).code == 0 }
    /// The keeper's own copy of the app is running.
    private static var running: Bool {
        let answer = launchctl(["print", service])
        return answer.code == 0 && answer.text.contains("state = running")
    }

    /// Writes the start order if it is missing or out of date. Returns: is it right now, and was it rewritten.
    @discardableResult
    static func writeFile() -> (right: Bool, changed: Bool) {
        guard inApplications, let executable = Bundle.main.executablePath, let id = Bundle.main.bundleIdentifier else {
            return (false, false)
        }
        let order = Keeper.plist(executable: executable, bundleID: id) as NSDictionary
        if let now = NSDictionary(contentsOf: file), now.isEqual(order) { return (true, false) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: order, format: .xml, options: 0),
              (try? data.write(to: file, options: .atomic)) != nil else { return (false, false) }
        return (true, true)
    }

    /// "Open at login" was switched off: the start order goes too.
    static func remove() {
        // Telling the Mac to forget it would stop the copy the keeper itself opened — that copy only removes
        // the file; the Mac forgets the rest at the next login.
        if !openedByKeeper { launchctl(["bootout", service]) }
        try? FileManager.default.removeItem(at: file)
    }

    /// A copy opened by hand asks the keeper to open its own copy. True when that copy is running, so this one
    /// can quit; false when the keeper did not answer, so this one carries on by itself.
    static func handOver() -> Bool {
        let written = writeFile()
        guard written.right else { return false }
        if written.changed, loaded { launchctl(["bootout", service]) }
        if !loaded { launchctl(["bootstrap", domain, file.path]) }   // the Mac opens the copy at once
        launchctl(["kickstart", service])                             // … or now, when it already knew the order
        for _ in 0..<15 {
            if running { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// One part of the diary's start line.
    static func stateLine() -> String {
        guard wanted else { return "keeper: off" }
        guard inApplications else { return "keeper: not used outside Applications" }
        let fileThere = FileManager.default.fileExists(atPath: file.path)
        return fileThere && loaded ? "keeper: in place" : "keeper: could not be set up"
    }

    // MARK: Only one copy

    /// When a program started, from the Mac itself (process numbers start again from the bottom, so they
    /// cannot say which copy is older).
    static func started(pid: pid_t) -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let time = info.kp_proc.p_starttime
        return Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }

    /// The other copies of this app that started before this one.
    static func earlierCopies() -> [OneCopy.Copy] {
        let mine = getpid()
        guard let id = Bundle.main.bundleIdentifier, let myStart = started(pid: mine) else { return [] }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .map(\.processIdentifier).filter { $0 != mine && $0 > 0 }
            .compactMap { pid in started(pid: pid).map { OneCopy.Copy(started: $0, pid: pid) } }
        return OneCopy.earlier(than: OneCopy.Copy(started: myStart, pid: mine), among: others)
    }

    /// True when this copy has to quit because an earlier one stays. The keeper's copy first gives an earlier
    /// copy 3 seconds to make way (a copy opened by hand quits as soon as it sees the keeper's copy run).
    static func mustQuitForEarlierCopy() -> Bool {
        var earlier = earlierCopies()
        guard !earlier.isEmpty else { return false }
        guard openedByKeeper else { return true }
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.2)
            earlier = earlier.filter { kill($0.pid, 0) == 0 }
            if earlier.isEmpty { return false }
        }
        return true
    }
}
