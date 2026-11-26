import CoreGraphics
import Foundation

// Prints the "triathlon" mark (a medal on its ribbon) as ONE filled outline (SVG path data) on a square canvas:
// the drawn line turned into a shape. The Mac's layered app icon fills whatever it is given, so a plain
// line drawing would come out as blobs.
// Used by make-icon.py:  swift Tools/mark-outline.swift <canvas> <share of the canvas> <line weight on the 24 grid>
// The numbers are the AMS Icon Library mark "triathlon": M7.5 3.5 10.6 10 M16.5 3.5 13.4 10 M7.5 3.5h9 and a circle at 12,15 radius 5.

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Double(arguments[1]), let share = Double(arguments[2]), let weight = Double(arguments[3]) else {
    FileHandle.standardError.write("usage: mark-outline.swift <canvas> <share> <line weight>\n".data(using: .utf8)!)
    exit(2)
}

let mark = CGMutablePath()
mark.move(to: CGPoint(x: 7.5, y: 3.5)); mark.addLine(to: CGPoint(x: 10.6, y: 10))
mark.move(to: CGPoint(x: 16.5, y: 3.5)); mark.addLine(to: CGPoint(x: 13.4, y: 10))
mark.move(to: CGPoint(x: 7.5, y: 3.5)); mark.addLine(to: CGPoint(x: 16.5, y: 3.5))
mark.addEllipse(in: CGRect(x: 7, y: 10, width: 10, height: 10))

// The mark's drawn extent is 2.5...21 high (centre 11.75): shift it so it sits in the middle of the grid.
let k = CGFloat(size * share / 24)
let o = CGFloat(size) / 2 - 12 * k
var place = CGAffineTransform(translationX: o, y: o + 0.25 * k).scaledBy(x: k, y: k)
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
