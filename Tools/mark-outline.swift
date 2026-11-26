import CoreGraphics
import Foundation

// Prints the training wave (three blocks of work on a rest line) as ONE filled outline (SVG path data) on a square
// canvas: the drawn line turned into a shape. The Mac's layered app icon fills whatever it is given, so a plain
// line drawing would come out as blobs.
// Used by make-icon.py:  swift Tools/mark-outline.swift <canvas> <share of the canvas> <line weight on the 24 grid>
// The numbers are the AMS Icon Library app mark "trainingWave".

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Double(arguments[1]), let share = Double(arguments[2]), let weight = Double(arguments[3]) else {
    FileHandle.standardError.write("usage: mark-outline.swift <canvas> <share> <line weight>\n".data(using: .utf8)!)
    exit(2)
}

let wave: [(CGFloat, CGFloat)] = [(2.5, 16.05), (3.89, 7.95), (6.43, 7.95), (7.82, 16.05), (9.34, 16.05), (10.73, 7.95), (13.27, 7.95),
                                  (14.66, 16.05), (16.18, 16.05), (17.57, 7.95), (20.11, 7.95), (21.5, 16.05)]
let mark = CGMutablePath()
mark.move(to: CGPoint(x: wave[0].0, y: wave[0].1))
for point in wave.dropFirst() { mark.addLine(to: CGPoint(x: point.0, y: point.1)) }

// The wave is centred on the grid already (7.95 to 16.05 high, 2.5 to 21.5 wide).
let k = CGFloat(size * share / 24)
let o = CGFloat(size) / 2 - 12 * k
var place = CGAffineTransform(translationX: o, y: o).scaledBy(x: k, y: k)
guard let placed = mark.copy(using: &place) else { exit(1) }
let outline = placed.copy(strokingWithWidth: CGFloat(weight) * k, lineCap: .round, lineJoin: .round, miterLimit: 10)
    .normalized(using: .winding)

var d = ""
func p(_ point: CGPoint) -> String { String(format: "%.2f %.2f", point.x, point.y) }
outline.applyWithBlock { element in
    let points = element.pointee.points
    switch element.pointee.type {
    case .moveToPoint: d += "M" + p(points[0])
    case .addLineToPoint: d += "L" + p(points[0])
    case .addQuadCurveToPoint: d += "Q" + p(points[0]) + " " + p(points[1])
    case .addCurveToPoint: d += "C" + p(points[0]) + " " + p(points[1]) + " " + p(points[2])
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}
print(d)
