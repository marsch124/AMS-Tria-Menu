import AppKit
import Combine
import SwiftUI
import TriaMenuCore

/// The item in the menu bar: one icon, two blocks of the training wave of AMS Triathlon Training's app icon
/// (0.4: thin and pale green, his pick), and the panel under it. Green while the app has today's note, grey without.
/// A right-click is the peek: the wave rolls once and a few words stand beside it for four seconds.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem!
    private var placeTimer: Timer?
    /// Since when the item has been out of sight (nil while it is seen).
    private var unseenSince: Date?
    private var repairing = false
    private let popover = NSPopover()
    private let model: AppModel
    private var bag = Set<AnyCancellable>()
    private var drawnKey = ""
    /// The peek: words beside the wave until this timer ends.
    private var peekOn = false
    private var peekEnd: Timer?
    private var rollTimer: Timer?
    private var rollPhase: CGFloat?
    private var peekRefreshed: Date?
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
        // Every redraw of a menu bar item costs the Mac a little, so it is drawn only when it turns from
        // green to grey or back; the words under the pointer follow every reading.
        model.$body.map { _ in () }.merge(with: model.$note.map { _ in () })
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
            button.imagePosition = .imageOnly
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

    /// A left click opens the panel; a right click or control-click is the peek.
    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            peek()
        } else {
            toggle()
        }
    }

    /// The peek (0.4; a short menu before): the wave rolls once, the app fetches fresh numbers, and for four
    /// seconds the next session and Body Battery stand beside the wave. Also what the check hook does.
    func peek() {
        if popover.isShown { popover.performClose(nil) }
        let now = Date()
        if Peek.refreshes(lastRefresh: peekRefreshed, now: now) {
            peekRefreshed = now
            model.refreshNow()
        }
        Diary.note("Peek: \(Words.peek(note: model.note, battery: model.body.latest))")
        peekOn = true
        peekEnd?.invalidate()
        let end = Timer(timeInterval: Peek.seconds, repeats: false) { [weak self] _ in
            self?.peekOn = false
            self?.redraw(force: true)
        }
        RunLoop.main.add(end, forMode: .common)
        peekEnd = end
        rollTimer?.invalidate()
        let start = Date()
        rollPhase = 0
        let roll = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let phase = Date().timeIntervalSince(start) / Peek.rollSeconds
            if phase >= 1 {
                timer.invalidate()
                self.rollTimer = nil
                self.rollPhase = nil
            } else {
                self.rollPhase = CGFloat(phase)
            }
            self.redraw(force: true)
        }
        RunLoop.main.add(roll, forMode: .common)
        rollTimer = roll
        redraw(force: true)
    }

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
        let known = model.note != nil
        let shown = peekOn ? (Words.peekSession(model.note), Words.number(model.body.latest)) : nil
        let key = "\(known)|\(shown?.0 ?? "")|\(shown?.1 ?? "")|\(rollPhase.map { Int($0 * 1000) } ?? -1)"
        guard force || key != drawnKey else { return }
        drawnKey = key
        let image = Self.image(known: known, peek: shown, roll: rollPhase)
        button.image = image
        item.length = image.size.width + Self.edgeRoom
    }

    /// Room left and right of the picture, together (0.4: 6; the Mac's own 8 before).
    static let edgeRoom: CGFloat = 6
    static let peekSize: CGFloat = 11

    /// The wave for the menu bar, with the peek words beside it while they show. Its colours settle when the
    /// Mac draws it, so one picture is right by day and by night.
    static func image(known: Bool, peek: (session: String, battery: String)? = nil, roll: CGFloat? = nil) -> NSImage {
        let height: CGFloat = 18, gap: CGFloat = 5
        let font = NSFont.systemFont(ofSize: peekSize, weight: .medium)
        let line = NSMutableAttributedString()
        if let peek {
            line.append(NSAttributedString(string: peek.session, attributes: [.font: font, .foregroundColor: Palette.inkNS]))
            line.append(NSAttributedString(string: " \u{00B7} ", attributes: [.font: font, .foregroundColor: Palette.greyNS]))
            // Body Battery's own colour, as on its card in the panel.
            line.append(NSAttributedString(string: peek.battery, attributes: [.font: NSFont.systemFont(ofSize: peekSize, weight: .semibold),
                                                                               .foregroundColor: Palette.bodyNS]))
        }
        let textSize = line.size()
        let width = MenuWave.width + (peek == nil ? 0 : gap + ceil(textSize.width) + 1)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            MenuWave.draw(x: 0, midY: rect.midY, color: known ? Palette.waveNS : Palette.greyNS, roll: roll, context: context)
            if peek != nil { line.draw(at: NSPoint(x: MenuWave.width + gap, y: (height - textSize.height) / 2)) }
            return true
        }
        image.isTemplate = false
        return image
    }
}
