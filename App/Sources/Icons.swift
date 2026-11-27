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
/// purple = this week, pink = Body Battery, a sport's colour = that sport still to do, grey = nothing to do
/// or nothing known.
enum Palette {
    static func today(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x00C97B : 0x00875A) }
    /// Behind white words: the main button and the tile.
    static let mainFill = Color(hex: 0x00875A)
    static func tomorrow(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x3B9EFF : 0x1266C8) }
    static func week(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xC084FC : 0x7C3AED) }
    static func weekFill(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x9A5CF0 : 0x7C3AED) }
    static func body(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xF472B6 : 0xC21E6E) }
    /// The Body Battery card: a pale, bright pink (0.3.3, his ask "a bit paler still"; EC4899 / E0408C in 0.3.2,
    /// deep raspberry C21E6E / B81868 before). White words stand on it by day and by night.
    static func bodyFill(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xE35A9D : 0xF06AAB) }
    /// Yesterday's thin line on the card: a deep plum, darker than the card.
    static func yesterday(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x45082A : 0x4E0A2C) }
    static func pale(_ color: Color, _ scheme: ColorScheme) -> Color { color.opacity(scheme == .dark ? 0.22 : 0.14) }

    /// The wave in the menu bar while the app has today's note: a pale green (0.4, his pick 3 of four;
    /// the green of Triathlon's app icon, 01C97B / 00875A, before).
    static let waveNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x8B / 255.0, green: 0xE8 / 255.0, blue: 0xC2 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0x35 / 255.0, green: 0xA8 / 255.0, blue: 0x82 / 255.0, alpha: 1)
    }
    static func wave(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x8BE8C2 : 0x35A882) }
    /// Words in the menu bar (the peek).
    static let inkNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.92) : NSColor(white: 0, alpha: 0.85)
    }
    /// Body Battery's pink, for its number in the menu bar.
    static let bodyNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xF4 / 255.0, green: 0x72 / 255.0, blue: 0xB6 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xC2 / 255.0, green: 0x1E / 255.0, blue: 0x6E / 255.0, alpha: 1)
    }
    /// Grey: no note for today.
    static let greyNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.66, alpha: 1) : NSColor(white: 0.45, alpha: 1)
    }
}

/// The wave of the menu bar item (0.4): two blocks of the training wave, a thin line. It is drawn from its
/// corner points, so it can roll: a small lift runs through it from left to right.
/// (A mark for this one screen; the three-block wave of the tile comes from the icon library.)
enum MenuWave {
    /// The corners on the 24-point grid (y pointing down), centred on 12.
    static let points: [CGPoint] = [
        CGPoint(x: 5.92, y: 16.05), CGPoint(x: 7.31, y: 7.95), CGPoint(x: 9.85, y: 7.95), CGPoint(x: 11.24, y: 16.05),
        CGPoint(x: 12.76, y: 16.05), CGPoint(x: 14.15, y: 7.95), CGPoint(x: 16.69, y: 7.95), CGPoint(x: 18.08, y: 16.05),
    ]
    static let stroke: CGFloat = 1.5
    /// Points on the screen for one grid step: the same size as the three-block wave had.
    static let unit: CGFloat = 20.0 / 24.0
    /// Room the wave takes, its line included.
    static let width: CGFloat = 12

    /// The corners while the wave rolls (`roll` from 0 to 1), or at rest.
    static func corners(roll: CGFloat?) -> [CGPoint] {
        guard let roll else { return points }
        let crest = (5.92 - 4) + roll * (18.08 - 5.92 + 8)
        return points.map { point in
            let away = (point.x - crest) / 2.6
            return CGPoint(x: point.x, y: point.y - 2.4 * exp(-away * away))
        }
    }

    /// Draws it into an AppKit drawing (y pointing up): `x` is its left edge, `midY` its middle line.
    static func draw(x: CGFloat, midY: CGFloat, color: NSColor, roll: CGFloat? = nil, context: CGContext) {
        let left = x + (width - (18.08 - 5.92) * unit) / 2
        let spots = corners(roll: roll).map { CGPoint(x: left + ($0.x - 5.92) * unit, y: midY + (12 - $0.y) * unit) }
        context.saveGState()
        context.addLines(between: spots)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(stroke * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }
}

/// The same wave as a view, for "Signs in this app".
struct MenuWaveView: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let u = MenuWave.unit
            let spots = MenuWave.points.map { CGPoint(x: size.width / 2 + ($0.x - 12) * u, y: size.height / 2 + ($0.y - 12) * u) }
            path.addLines(spots)
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: MenuWave.stroke * u, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 18)
        .accessibilityHidden(true)
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
