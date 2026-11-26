import AppKit
import Combine
import SwiftUI
import TriaMenuCore

/// The item in the menu bar: the mark of today's session and the Body Battery number, and the panel under it.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem!
    private var placeTimer: Timer?
    /// Since when the item has been out of sight (nil while it is seen).
    private var unseenSince: Date?
    private var repairing = false
    private let popover = NSPopover()
    private let model: AppModel
    private var bag = Set<AnyCancellable>()
    private var drawnFace: Face?
    private var drawnNumber: String?
    /// The app that had the keyboard when the panel opened; it gets it back when the panel closes.
    private var previousApp: NSRunningApplication?
    private var outsideClicks: Any?
    private let openSettingsAction: () -> Void

    static let autosaveName = "triaMenu"
    static let placeKey = "NSStatusItem Preferred Position \(autosaveName)"

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettingsAction = openSettings
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(model: model, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }, close: { [weak self] in
            self?.popover.performClose(nil)
        }))
        // The panel grows and shrinks with its sessions and stays under the menu bar.
        host.sizingOptions = [.preferredContentSize]
        // The panel opens without coming to the front, so its very first click must already count
        // (by default a first click only wakes a window up).
        if let viewClass = object_getClass(host.view) {
            let always: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            class_replaceMethod(viewClass, #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(always), "B@:@")
        }
        popover.contentViewController = host
        // The very first start: a place in sight, not behind the notch where a new item would land.
        if UserDefaults.standard.object(forKey: Self.placeKey) == nil {
            UserDefaults.standard.set(BarPlace.home, forKey: Self.placeKey)
        }
        makeItem()
        let placeTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.keepInSight() }
        placeTimer.tolerance = 1
        RunLoop.main.add(placeTimer, forMode: .common)
        self.placeTimer = placeTimer
        // Every redraw of a menu bar item costs the Mac a little, so it is drawn only when the mark or the
        // number really changes.
        model.$face.map { _ in () }.merge(with: model.$body.map { _ in () }, model.$note.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw(force: false) }
            .store(in: &bag)
        redraw(force: true)
        // Lets a check from outside open the panel, so the real thing can be photographed.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(toggle),
                                                            name: Notification.Name("com.schabbauer.AMSTriaMenu.togglePanel"), object: nil)
    }

    private func makeItem() {
        // The new item gets its name before the old one (after a repair) is let go:
        // letting go of an old item whose name is not in use any more makes the Mac forget the saved place.
        let fresh = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        fresh.autosaveName = Self.autosaveName
        item = fresh
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityIdentifier("triaMenuStatusItem")
        }
    }

    /// The Mac can move the item's saved place to the far left of the bar, where it is out of sight
    /// (behind the notch or in AMS Tidy Bar's hidden part). After 10 seconds unseen it goes back.
    private func keepInSight() {
        guard !repairing else { return }
        guard !popover.isShown else { unseenSince = nil; return }
        let visible = item.button?.window?.occlusionState.contains(.visible) == true
        if visible { unseenSince = nil } else if unseenSince == nil { unseenSince = Date() }
        let saved = (UserDefaults.standard.object(forKey: Self.placeKey) as? NSNumber)?.doubleValue
        let unseen = unseenSince.map { Date().timeIntervalSince($0) } ?? 0
        guard BarPlace.needsRepair(saved: saved, visible: visible, unseenSeconds: unseen) else { return }
        Diary.note("The menu bar item was out of sight (saved place \(Int(saved ?? 0))); putting it back")
        NSStatusBar.system.removeStatusItem(item)
        repairing = true
        unseenSince = nil
        // The Mac forgets a removed item's place a moment after removing it; write the place after that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            // Let go of the old item first: that is when the Mac forgets its place.
            autoreleasepool { self.item = nil }
            UserDefaults.standard.set(BarPlace.home, forKey: Self.placeKey)
            self.makeItem()
            self.repairing = false
            self.redraw(force: true)
        }
    }

    /// A left click opens the panel; a right click or control-click shows the short menu.
    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if popover.isShown { popover.performClose(nil) }
            item.menu = makeMenu()
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            toggle()
        }
    }

    /// For checks: the right-click menu, closed again by itself after four seconds.
    func showMenuForCheck() {
        let menu = makeMenu()
        let close = Timer(timeInterval: 4, repeats: false) { _ in menu.cancelTracking() }
        RunLoop.main.add(close, forMode: .common)
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    /// Titles of the right-click menu, in order (a separator between the second and the third).
    static let rightMenuTitles = ["Open Triathlon", "Refresh now", "Settings\u{2026}"]

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let t = Self.rightMenuTitles
        let open = NSMenuItem(title: t[0], action: #selector(rightOpen), keyEquivalent: "")
        open.setAccessibilityIdentifier("triaMenuRightOpen")
        let refresh = NSMenuItem(title: t[1], action: #selector(rightRefresh), keyEquivalent: "")
        refresh.setAccessibilityIdentifier("triaMenuRightRefresh")
        let settings = NSMenuItem(title: t[2], action: #selector(rightSettings), keyEquivalent: "")
        settings.setAccessibilityIdentifier("triaMenuRightSettings")
        for entry in [open, refresh, .separator(), settings] {
            entry.target = self
            menu.addItem(entry)
        }
        return menu
    }

    @objc private func rightOpen() { model.openTriathlon() }
    @objc private func rightRefresh() { model.refreshNow() }
    @objc private func rightSettings() { openSettingsAction() }

    /// Opens or closes the panel. The panel does not come to the front: the app you work in keeps the keyboard.
    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button, button.window != nil {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            model.panelOpen = popover.isShown
            guard popover.isShown, outsideClicks == nil else { return }
            // Not in front, the panel does not hear about clicks elsewhere by itself.
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelOpen = false
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        // A click in the panel brought this app to the front: hand the keyboard back, unless Settings is open.
        let ownWindowOpen = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if NSApp.isActive, !ownWindowOpen { previousApp?.activate() }
        previousApp = nil
    }

    private func redraw(force: Bool) {
        guard let button = item?.button else { return }
        let words = Words.hover(note: model.note, battery: model.body.latest)
        if button.toolTip != words { button.toolTip = words }
        button.setAccessibilityLabel(words.replacingOccurrences(of: "\n", with: ". "))
        let face = model.face
        let number = Words.number(model.body.latest)
        if force || drawnFace != face {
            drawnFace = face
            button.image = Self.image(face)
        }
        if force || drawnNumber != number {
            drawnNumber = number
            // No colour of its own: the Mac draws it black or white like the clock beside it.
            button.attributedTitle = NSAttributedString(string: number, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .baselineOffset: -0.5,
            ])
        }
    }

    static func look(_ face: Face) -> (mark: Mark, colour: NSColor) {
        switch face {
        case .toDo(let sport): return (.sport(sport), Sport.inkNS(sport))
        case .done: return (.tick, Palette.tickNS)
        case .rest: return (.moon, Palette.moonNS)
        case .grey(let sport): return (sport.map { .sport($0) } ?? .medal, Palette.greyNS)
        }
    }

    /// The mark for the menu bar. Its colour settles when the Mac draws it, so one picture is right by day
    /// and by night.
    static func image(_ face: Face) -> NSImage {
        let side: CGFloat = 18
        let look = look(face)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // A slightly heavier line than in the panel, so the small mark stays clear.
            look.mark.draw(in: rect.insetBy(dx: 0.5, dy: 0.5), color: look.colour, context: context, stroke: 2.0)
            return true
        }
        image.isTemplate = false
        return image
    }
}
