import AppKit
import ServiceManagement
import SwiftUI
import TriaMenuCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var status: StatusItemController?
    private var settingsWindow: NSWindow?
    private var stopSignal: DispatchSourceSignal?

    private static let refreshName = Notification.Name("com.schabbauer.AMSTriaMenu.refresh")

    /// Tells the running copy something, then quits. A moment for the message to leave: quitting at once lost it.
    private func tellRunningCopy(_ name: Notification.Name, _ word: String?) {
        DistributedNotificationCenter.default().postNotificationName(name, object: word, userInfo: nil, deliverImmediately: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        // For checks: pictures of every screen with invented values, by day and by night.
        if let index = arguments.firstIndex(of: "--snapshots"), index + 1 < arguments.count {
            Snapshots.write(to: URL(fileURLWithPath: arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }
        // For checks: prints the titles of the right-click menu, then quits.
        if arguments.contains("--right-menu-items") {
            print(StatusItemController.rightMenuTitles.joined(separator: "\n"))
            NSApp.terminate(nil)
            return
        }
        // For checks: prints what the app reads right now (the note, the Board), then quits. Opens nothing.
        if arguments.contains("--read") {
            UserDefaults.standard.register(defaults: [:])
            print(AppModel.readout())
            Diary.finish()
            NSApp.terminate(nil)
            return
        }
        // For checks: tells the running copy to refresh now, then quits.
        if arguments.contains("--refresh") {
            tellRunningCopy(Self.refreshName, nil)
            return
        }
        // Switches "Open at login" on or off from outside, then quits: "--open-at-login on". "status" only looks.
        if let index = arguments.firstIndex(of: "--open-at-login"), index + 1 < arguments.count {
            if arguments[index + 1] == "on" {
                try? SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: LoginItem.wantedKey)
                KeeperJob.writeFile()
            } else if arguments[index + 1] == "off" {
                try? SMAppService.mainApp.unregister()
                UserDefaults.standard.set(false, forKey: LoginItem.wantedKey)
                KeeperJob.remove()
            }
            print("open at login:", SMAppService.mainApp.status == .enabled ? "on" : "off",
                  "· asked for:", UserDefaults.standard.object(forKey: LoginItem.wantedKey) as? Bool ?? "never said",
                  "·", KeeperJob.stateLine())
            NSApp.terminate(nil)
            return
        }
        if KeeperJob.mustQuitForEarlierCopy() {
            NSApp.terminate(nil)
            return
        }
        var keeperNote = ""
        if Keeper.handsOver(wanted: KeeperJob.wanted, openedByKeeper: KeeperJob.openedByKeeper,
                            plain: KeeperJob.plain, inApplications: KeeperJob.inApplications) {
            if KeeperJob.handOver() {
                Diary.note("Opened by hand or by the Mac's login list; handed over to the keeper")
                Diary.finish()
                NSApp.terminate(nil)
                return
            }
            keeperNote = "; the keeper did not answer in 3 s, carrying on without it"
        } else if KeeperJob.openedByKeeper {
            KeeperJob.writeFile()
        }
        // A polite stop from outside ends the app cleanly, so the keeper does not open it again.
        signal(SIGTERM, SIG_IGN)
        let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        stop.setEventHandler { NSApp.terminate(nil) }
        stop.resume()
        stopSignal = stop

        let model = AppModel()
        self.model = model
        Diary.note("Started \(AppInfo.version) (\(AppInfo.build)); "
                   + (KeeperJob.openedByKeeper ? "opened by the keeper" : "opened by hand or by the Mac's login list") + keeperNote + "; "
                   + LoginItem.checkAtStart() + "; " + KeeperJob.stateLine())
        status = StatusItemController(model: model, openSettings: { [weak self] in self?.openSettings() })

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(showSettings),
                           name: Notification.Name("com.schabbauer.AMSTriaMenu.openSettings"), object: nil)
        center.addObserver(self, selector: #selector(showRightMenu),
                           name: Notification.Name("com.schabbauer.AMSTriaMenu.showRightMenu"), object: nil)
        center.addObserver(self, selector: #selector(refresh), name: Self.refreshName, object: nil)
        // For checks: the same as a click on the first session row in the panel.
        center.addObserver(self, selector: #selector(openFirst),
                           name: Notification.Name("com.schabbauer.AMSTriaMenu.openFirstSession"), object: nil)
    }

    @objc private func showSettings(_ notification: Notification) {
        let word = notification.object as? String ?? ""
        openSettings(tab: SettingsView.Tab(rawValue: word) ?? .settings, atEnd: word == "end")
    }
    @objc private func showRightMenu() { status?.showMenuForCheck() }
    @objc private func refresh() { model?.refreshNow() }
    @objc private func openFirst() { model?.openTriathlon(model?.note?.sessions.first) }

    private func openSettings(tab: SettingsView.Tab = .settings, atEnd: Bool = false) {
        guard let model else { return }
        let content = NSHostingController(rootView: SettingsView(model: model, close: { [weak self] in
            self?.settingsWindow?.close()
        }, startTab: tab, atEnd: atEnd))
        if let settingsWindow {
            settingsWindow.contentViewController = content
        } else {
            let window = NSWindow(contentViewController: content)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }
}

/// Pictures of every screen with invented values, for looking them over without the real menu bar.
enum Snapshots {
    @MainActor
    static func write(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (scheme, tag) in [(ColorScheme.light, "day"), (ColorScheme.dark, "night")] {
            let back = scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)
            let panels: [(String, AppModel)] = [
                ("panel-todo", .sample(.toDo)),
                ("panel-done", .sample(.allDone)),
                ("panel-rest", .sample(.rest)),
                ("panel-missed", .sample(.missed)),
                ("panel-long", .sample(.long)),
                ("panel-no-note", .sample(.noNote)),
                ("panel-no-body", .sample(.noBody)),
                ("panel-waiting", .sample(.waiting)),
            ]
            for (name, model) in panels {
                save(PanelView(model: model).background(back).environment(\.colorScheme, scheme),
                     folder.appendingPathComponent("\(name)-\(tag).png"))
            }
            for (tab, name) in [(SettingsView.Tab.settings, "settings"), (.guide, "settings-guide"), (.news, "settings-news")] {
                save(SettingsView(model: .sample(.toDo), scrolls: false, startTab: tab).background(back).environment(\.colorScheme, scheme),
                     folder.appendingPathComponent("\(name)-\(tag).png"))
            }
            save(SettingsView(model: .sample(.toDo), scrolls: false, startTab: .guide).frame(height: 3600).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("settings-guide-whole-\(tag).png"))
            save(SettingsView(model: .sample(.toDo), scrolls: false, startTab: .news).frame(height: 900).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("settings-news-whole-\(tag).png"))
            let dark = scheme == .dark
            let faces: [(String, Face, Int?)] = [("todo-run", .toDo(sport: "run"), 44), ("todo-swim", .toDo(sport: "swim"), 80),
                                                  ("todo-bike", .toDo(sport: "bike"), 9), ("todo-strength", .toDo(sport: "strength"), 100),
                                                  ("done", .done, 38), ("rest", .rest, 71), ("missed", .grey(sport: "bike"), 55),
                                                  ("no-note", .grey(sport: nil), nil)]
            save(HStack(spacing: 14) {
                ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                    HStack(spacing: 3) {
                        Image(nsImage: settled(StatusItemController.image(face.1), dark: dark))
                        Text(Words.number(face.2)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                            .foregroundStyle(dark ? Color.white : Color.black)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(dark ? Color(white: 0.2) : Color(white: 0.88)), folder.appendingPathComponent("menubar-\(tag).png"))
        }
        save(Image(nsImage: TileArt.image(size: 256)), folder.appendingPathComponent("tile-256.png"))
    }

    private static func settled(_ image: NSImage, dark: Bool) -> NSImage {
        let out = NSImage(size: image.size)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 4),
                                             pixelsHigh: Int(image.size.height * 4), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = image.size
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            out.addRepresentation(rep)
        }
        return out
    }

    @MainActor
    private static func save<V: View>(_ view: V, _ url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
