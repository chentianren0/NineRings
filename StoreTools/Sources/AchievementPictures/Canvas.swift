import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Shared by every art direction. Read it once, then put your own helpers in your own file.
//
// The canvas is 1024 × 1024, opaque, sRGB. Its origin is the top left corner and y grows downwards, as in SVG.
// Angles are in degrees: 0 points right, 90 down, 180 left, 270 up. An arc from a smaller angle to a larger one runs
// clockwise on the screen.
//
// CoreGraphics itself is all yours as well: CGMutablePath, CGPath's union, intersection and subtracting,
// CGAffineTransform, and anything on CGContext.

/// The four pictures, named by each achievement's identifier in Game Center.
enum Picture: String, CaseIterable {
    case allNineOff = "all_nine_off"
    case shortestWay = "shortest_way"
    case allNineBackOn = "all_nine_back_on"
    case farEnd = "far_end"
}

let side: CGFloat = 1024
let middle = CGPoint(x: 512, y: 512)
/// Game Center cuts the picture to a circle of radius 512. What matters stays within this distance of the middle.
let safeRadius: CGFloat = 470

// MARK: Colours

/// A colour from a hex value, such as `rgb(0xA3ACB8)`.
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A colour between two others: 0 gives `a`, 1 gives `b`.
func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let x = a.converted(to: space, intent: .defaultIntent, options: nil)!.components!
    let y = b.converted(to: space, intent: .defaultIntent, options: nil)!.components!
    return CGColor(
        srgbRed: x[0] + (y[0] - x[0]) * t, green: x[1] + (y[1] - x[1]) * t, blue: x[2] + (y[2] - x[2]) * t,
        alpha: x[3] + (y[3] - x[3]) * t)
}

/// The same colour with another opacity.
func faded(_ color: CGColor, _ alpha: CGFloat) -> CGColor { color.copy(alpha: alpha)! }

// MARK: Points

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// The point at `radius` from `center` in the direction `degrees`.
func polar(_ center: CGPoint, _ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
}

// MARK: Paths

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
}

/// An ellipse, turned clockwise by `rotation` degrees about its centre.
func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation * .pi / 180)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, corner: CGFloat = 0) -> CGPath {
    let r = min(corner, width / 2, height / 2)
    return CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// An open line through the points.
func line(_ points: CGPoint...) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    return path
}

/// A closed shape through the points.
func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

/// An open arc, clockwise on the screen from `from` to `to` (degrees; `to` larger than `from`).
func arc(_ center: CGPoint, _ radius: CGFloat, from: CGFloat, to: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addArc(center: center, radius: radius, startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: false)
    return path
}

/// The shape a line of this width covers when it is drawn along `path`. Fill it to paint a line with a gradient,
/// clip to it, or clip outside it to break another line where this one passes over.
func outline(_ path: CGPath, width: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: cap, lineJoin: join, miterLimit: 10)
}

/// A line with round ends from `a` to `b`, as a shape to fill.
func capsule(_ a: CGPoint, _ b: CGPoint, width: CGFloat) -> CGPath { outline(line(a, b), width: width) }

/// The band between two radii, as a shape to fill.
func annulus(_ center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    outline(circle(center, (outer + inner) / 2), width: outer - inner, cap: .butt)
}

func moved(_ path: CGPath, by t: CGAffineTransform) -> CGPath {
    var t = t
    return path.copy(using: &t) ?? path
}

// MARK: Painting

/// Gradient stops: where along the gradient (0 to 1), and the colour there.
typealias Stops = [(CGFloat, CGColor)]

private func gradient(_ stops: Stops) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor, evenOdd: Bool = false) {
        saveGState()
        setFillColor(color)
        addPath(path)
        fillPath(using: evenOdd ? .evenOdd : .winding)
        restoreGState()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round, dash: [CGFloat] = []) {
        saveGState()
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap)
        setLineJoin(join)
        if !dash.isEmpty { setLineDash(phase: 0, lengths: dash) }
        addPath(path)
        strokePath()
        restoreGState()
    }

    /// Fills `path` with a gradient that runs along the line from `from` to `to`.
    func fillLinear(_ path: CGPath, from: CGPoint, to: CGPoint, _ stops: Stops, evenOdd: Bool = false) {
        clipped(to: path, evenOdd: evenOdd) {
            drawLinearGradient(gradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// Fills `path` with a gradient that runs outwards from `focus` (or from `center`) to the circle of `radius`.
    func fillRadial(_ path: CGPath, center: CGPoint, radius: CGFloat, _ stops: Stops, focus: CGPoint? = nil, evenOdd: Bool = false) {
        clipped(to: path, evenOdd: evenOdd) {
            drawRadialGradient(
                gradient(stops), startCenter: focus ?? center, startRadius: 0, endCenter: center, endRadius: radius,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// Fills the whole square.
    func background(_ color: CGColor) { fill(rect(0, 0, side, side), color) }

    /// Runs `body` with drawing kept to the inside of `path`.
    func clipped(to path: CGPath, evenOdd: Bool = false, _ body: () -> Void) {
        saveGState()
        addPath(path)
        clip(using: evenOdd ? .evenOdd : .winding)
        body()
        restoreGState()
    }

    /// Runs `body` with drawing kept to the outside of `path`: the way to break a line where another passes over it.
    func clipped(outside path: CGPath, _ body: () -> Void) {
        saveGState()
        addRect(CGRect(x: -side, y: -side, width: 3 * side, height: 3 * side))
        addPath(path)
        clip(using: .evenOdd)
        body()
        restoreGState()
    }

    /// Runs `body` as one layer of this opacity, so that shapes inside it do not show through each other.
    func layer(opacity: CGFloat, _ body: () -> Void) {
        saveGState()
        setAlpha(opacity)
        beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        endTransparencyLayer()
        restoreGState()
    }

    /// Runs `body` with a transform applied to everything it draws.
    func transformed(_ t: CGAffineTransform, _ body: () -> Void) {
        saveGState()
        concatenate(t)
        body()
        restoreGState()
    }

    /// Runs `body` with one soft shadow under everything it draws together. `dx` and `dy` are in canvas points, y down.
    func shadowed(dx: CGFloat, dy: CGFloat, blur: CGFloat, _ color: CGColor, _ body: () -> Void) {
        saveGState()
        // A shadow's offset is not in the canvas's flipped coordinates, so y is turned back here.
        setShadow(offset: CGSize(width: dx, height: -dy), blur: blur, color: color)
        beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        endTransparencyLayer()
        restoreGState()
    }
}

// MARK: The canvas and its file

func makeCanvas() -> CGContext {
    let context = CGContext(
        data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    context.background(rgb(0xFFFFFF))
    return context
}

/// Writes the canvas as an opaque PNG marked 72 ppi.
func writePNG(_ context: CGContext, to url: URL) throws {
    struct Unwritable: Error { let url: URL }
    guard let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Unwritable(url: url) }
    let properties = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { throw Unwritable(url: url) }
}
