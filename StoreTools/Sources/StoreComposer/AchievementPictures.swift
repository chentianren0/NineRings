import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pictures of the app's four Game Center achievements, drawn here as a few flat shapes, so that they can be made
/// again: `swift run --package-path StoreTools achievement-pictures`.
///
/// They speak the ring buttons' language: a ring that is on is a filled disc and a ring that is off is an outline, in
/// the blue of a ring that is on. The nine rings stand in three rows of three, ring 1 at the top left and ring 9 at the
/// bottom right, so that each is large enough to read when the picture is small; The Shortest Way is one straight arrow
/// from a filled ring to an outline. Game Center cuts each picture to a circle as wide as it is, so everything stays
/// well inside one.
///
/// App Store Connect asks for a `.png` or `.jpeg` of 1024 × 1024 pixels, at least 72 ppi, RGB. These are sRGB PNGs with
/// no alpha channel, marked 72 ppi.
public enum AchievementPictures {
    /// One picture for each achievement, named by the achievement's identifier in Game Center.
    public enum Picture: String, CaseIterable, Sendable {
        case allNineOff = "all_nine_off"
        case shortestWay = "shortest_way"
        case allNineBackOn = "all_nine_back_on"
        case farEnd = "far_end"
    }

    public static let size = 1024
    /// The background, and the blue of a ring that is on.
    static let background = CGColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1)
    /// The ring buttons' disc for a ring that is on: the system blue, #007AFF, darkened by 30% (see `RingButtons.onFill`).
    static let ring = CGColor(srgbRed: 0, green: 0.335, blue: 0.7, alpha: 1)
    /// How far from the middle anything is drawn: the circle Game Center keeps has a radius of 512.
    public static let contentRadius = 470.0

    public static func draw(_ picture: Picture) throws -> CGImage {
        let context = try Composer.makeOpaqueContext(PixelSize(size, size))
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        switch picture {
        case .allNineOff: drawGrid(on: [], in: context)
        case .allNineBackOn: drawGrid(on: Set(1...9), in: context)
        case .farEnd: drawGrid(on: [9], in: context)
        case .shortestWay: drawStraightThere(in: context)
        }
        guard let image = context.makeImage() else { throw ComposerError.unwritable(URL(filePath: "/")) }
        return image
    }

    /// Writes `image` as a PNG marked 72 ppi.
    public static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ComposerError.unwritable(url)
        }
        let properties = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw ComposerError.unwritable(url) }
    }

    // MARK: Drawing

    private static let middle = Double(size) / 2

    /// The nine rings as three rows of three, ring 1 at the top left and ring 9 at the bottom right, in reading order;
    /// those in `on` are filled. In a row of nine across the circle a ring could be no wider than about 100 pixels;
    /// three rows let each be twice that, as heavy as the two rings of The Shortest Way, so that on and off still read
    /// when the picture is small.
    private static func drawGrid(on: Set<Int>, in context: CGContext) {
        let diameter = 204.0
        let gap = 46.0
        let width = 3 * diameter + 2 * gap
        let left = middle - width / 2
        let top = middle + width / 2
        for ring in 1...9 {
            let column = Double((ring - 1) % 3)
            let row = Double((ring - 1) / 3)
            let x = left + column * (diameter + gap)
            // The context's y grows upwards: row 0 is at the top.
            let y = top - diameter - row * (diameter + gap)
            drawRing(in: CGRect(x: x, y: y, width: diameter, height: diameter), isOn: on.contains(ring), context: context)
        }
    }

    /// The shortest way: from every ring on, a filled ring, straight to every ring off, an outline.
    private static func drawStraightThere(in context: CGContext) {
        let diameter = 230.0
        let span = 800.0
        let left = middle - span / 2
        let right = middle + span / 2
        drawRing(in: CGRect(x: left, y: middle - diameter / 2, width: diameter, height: diameter), isOn: true, context: context)
        drawRing(in: CGRect(x: right - diameter, y: middle - diameter / 2, width: diameter, height: diameter), isOn: false, context: context)
        // One straight arrow between them.
        let gap = 38.0
        let start = left + diameter + gap
        let end = right - diameter - gap
        let shaft = 36.0
        let headLength = 92.0
        let headHeight = 132.0
        context.setFillColor(ring)
        context.fill(CGRect(x: start, y: middle - shaft / 2, width: end - headLength - start + 1, height: shaft))
        context.move(to: CGPoint(x: end, y: middle))
        context.addLine(to: CGPoint(x: end - headLength, y: middle + headHeight / 2))
        context.addLine(to: CGPoint(x: end - headLength, y: middle - headHeight / 2))
        context.closePath()
        context.fillPath()
    }

    /// A ring, as a ring button shows it: a filled disc when on, an outline when off, its line nearly a quarter of its
    /// width so that it still reads when the picture is small.
    private static func drawRing(in rect: CGRect, isOn: Bool, context: CGContext) {
        if isOn {
            context.setFillColor(ring)
            context.fillEllipse(in: rect)
        } else {
            let line = rect.width * 0.22
            context.setStrokeColor(ring)
            context.setLineWidth(line)
            context.strokeEllipse(in: rect.insetBy(dx: line / 2, dy: line / 2))
        }
    }
}
