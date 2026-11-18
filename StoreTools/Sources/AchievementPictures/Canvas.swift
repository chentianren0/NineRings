import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The canvas the pictures are drawn on, and the few helpers they use.
//
// The canvas is 1024 × 1024, opaque, sRGB. Its origin is the top left corner and y grows downwards, as in SVG.
// Angles are in degrees: 0 points right, 90 down, 180 left, 270 up.
// CoreGraphics itself is all there as well: CGMutablePath, CGAffineTransform, and anything on CGContext.

let side: CGFloat = 1024
let middle = CGPoint(x: 512, y: 512)

// MARK: Colours

/// A colour from a hex value, such as `rgb(0xA3ACB8)`.
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

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

/// The shape a line of this width covers when it is drawn along `path`. Fill it to paint the line, clip to it, or clip
/// outside it to break another line where this one passes over.
func outline(_ path: CGPath, width: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: cap, lineJoin: join, miterLimit: 10)
}

/// The band between two radii, as a shape to fill.
func annulus(_ center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    outline(circle(center, (outer + inner) / 2), width: outer - inner, cap: .butt)
}

// MARK: Painting

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

    /// Runs `body` with a transform applied to everything it draws.
    func transformed(_ t: CGAffineTransform, _ body: () -> Void) {
        saveGState()
        concatenate(t)
        body()
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

/// Writes the image as an opaque PNG marked 72 ppi.
func writePNG(_ image: CGImage, to url: URL) throws {
    struct Unwritable: Error { let url: URL }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Unwritable(url: url) }
    let properties = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { throw Unwritable(url: url) }
}
