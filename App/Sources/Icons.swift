import AMSIcons
import AppKit
import SwiftUI
import TriaMenuCore

/// The hand-drawn marks, all from the central icon library (AMS-Icons): a 24-point grid, one 1.9 stroke,
/// round ends, no fill. The sport marks are AMS Triathlon Training's own, so both apps show the same drawing.
enum Mark: Equatable {
    case sport(String), tick, moon, gear, wave

    /// The drawing as path data on the 24-point grid.
    var d: String {
        switch self {
        case .sport(let id): return Sport.mark(id).path
        case .tick: return AppMark.triCheck.path
        case .moon: return AppMark.moon.path
        case .gear: return ControlMark.settings.path
        // The training wave: the line of AMS Triathlon Training's app icon.
        case .wave: return AppMark.trainingWave.path
        }
    }

    /// Draws the mark into an AppKit drawing (y pointing up), for the menu bar and the tile.
    func draw(in rect: CGRect, color: NSColor, context: CGContext, stroke: CGFloat = 1.9) {
        let scale = rect.width / 24
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: scale, y: -scale)
        context.addPath(SVGPath.path(d).cgPath)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }
}

/// One mark, drawn as a shape; it takes the colour around it.
struct MarkView: View {
    let mark: Mark
    var size: CGFloat = 18
    var stroke: CGFloat = 1.9

    var body: some View {
        GridShape(d: mark.d)
            .stroke(style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A sport's mark and colour: the same five sport colours as in AMS Triathlon Training.
enum Sport {
    static func hex(_ id: String) -> UInt32 {
        switch id {
        case "swim": return 0x4f87f8
        case "bike", "brick": return 0xffd60a
        case "run": return 0x85ce6c
        case "strength": return 0xff8c1a
        case "rowing": return 0x0d9488
        case "mobility", "yoga", "stretch": return 0x8650fe
        case "race": return 0xef4444
        case "rest", "breathing", "meditation": return 0x64748b
        default: return 0x22d3ee
        }
    }

    static func mark(_ id: String) -> AppMark {
        switch id {
        case "swim": return .triSwim
        case "bike", "brick": return .triBike
        case "run": return .triRun
        case "strength": return .triStrength
        case "rowing": return .triRowing
        case "mobility": return .triMobility
        case "yoga": return .triYoga
        case "stretch": return .triStretch
        case "race": return .triRace
        case "hike": return .triHike
        case "walk": return .triWalk
        case "ski": return .triSki
        case "breathing": return .triBreathing
        case "meditation": return .triMeditation
        case "rest": return .moon
        default: return .triOther
        }
    }

    private static func parts(_ hex: UInt32, _ k: Double = 1) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xff) / 255 * k, Double((hex >> 8) & 0xff) / 255 * k, Double(hex & 0xff) / 255 * k)
    }

    private static func isSlate(_ id: String) -> Bool { hex(id) == 0x64748b }

    /// Readable as a word or a mark: the sport's hue, darker by day (the bike's yellow would not read on white).
    static func ink(_ id: String, _ scheme: ColorScheme) -> Color {
        if scheme == .dark { return Color(hex: isSlate(id) ? 0xA3B1C2 : hex(id)) }
        let p = parts(hex(id), 0.55)
        return Color(.sRGB, red: p.r, green: p.g, blue: p.b)
    }

    /// The same for the menu bar, where the Mac says whether it is day or night up there.
    static func inkNS(_ id: String) -> NSColor {
        let night = parts(isSlate(id) ? 0xA3B1C2 : hex(id))
        let day = parts(hex(id), 0.55)
        return NSColor(name: nil) { appearance in
            let p = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? night : day
            return NSColor(srgbRed: p.r, green: p.g, blue: p.b, alpha: 1)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// The app's colours. Each means one thing: green = today (and the tick: done), blue = tomorrow,
/// purple = this week, raspberry = Body Battery, a sport's colour = that sport still to do, grey = nothing to do
/// or nothing known.
enum Palette {
    static func today(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x00C97B : 0x00875A) }
    /// Behind white words: the main button and the tile.
    static let mainFill = Color(hex: 0x00875A)
    static func tomorrow(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x3B9EFF : 0x1266C8) }
    static func week(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xC084FC : 0x7C3AED) }
    static func weekFill(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x9A5CF0 : 0x7C3AED) }
    static func body(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xF472B6 : 0xC21E6E) }
    /// The Body Battery card: white words stand on it by day and by night.
    static func bodyFill(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xB81868 : 0xC21E6E) }
    /// Yesterday's thin line on the card: a deep plum, darker than the card.
    static func yesterday(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x45082A : 0x4E0A2C) }
    static func pale(_ color: Color, _ scheme: ColorScheme) -> Color { color.opacity(scheme == .dark ? 0.22 : 0.14) }

    /// The wave in the menu bar while the app has today's note: the green of Triathlon's app icon.
    static let waveNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.004, green: 0.79, blue: 0.48, alpha: 1) : NSColor(srgbRed: 0, green: 0.53, blue: 0.35, alpha: 1)
    }
    /// Grey: no note for today.
    static let greyNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.66, alpha: 1) : NSColor(white: 0.45, alpha: 1)
    }
}

/// The app's tile: a flat calm green with the white training wave (0.3.1; the medal before).
enum TileArt {
    static let corner: CGFloat = 0.26
    static let green = NSColor(srgbRed: 0, green: 0x87 / 255.0, blue: 0x5A / 255.0, alpha: 1)

    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let radius = rect.width * corner
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(green.cgColor)
            context.fillPath()
            let inset = rect.width * 0.09
            Mark.wave.draw(in: rect.insetBy(dx: inset, dy: inset), color: .white, context: context, stroke: 2.4)
            return true
        }
    }
}

/// The tile as a view, for the panel's and the Settings window's header.
struct AppTile: View {
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: TileArt.image(size: size)).accessibilityHidden(true)
    }
}

/// A button that gives a little when pressed. Drawn by the app, so it keeps its colour when the panel
/// is not the window in front.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
