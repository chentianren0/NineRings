import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pictures of the app's four Game Center achievements, drawn here as a few flat shapes, so that they can be made
/// again: `swift run --package-path StoreTools achievement-pictures`.
///
/// They speak the ring buttons' language: a ring that is on is a filled disc, a ring that is off is an outline, ring 1
/// on the left and ring 9 on the right, in the blue of a ring that is on. The sword is a bar in a lighter blue behind the
/// row. Game Center cuts each picture to a circle as wide as it is, so everything stays well inside one.
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
    /// The background, the blue of a ring that is on, and the sword's lighter blue.
    static let background = CGColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1)
    /// The ring buttons' disc for a ring that is on: the system blue, #007AFF, darkened by 30% (see `RingButtons.onFill`).
    static let ring = CGColor(srgbRed: 0, green: 0.335, blue: 0.7, alpha: 1)
    static let sword = CGColor(srgbRed: 0.62, green: 0.75, blue: 0.9, alpha: 1)
    /// How far from the middle anything is drawn: the circle Game Center keeps has a radius of 512.
    public static let contentRadius = 470.0

    public static func draw(_ picture: Picture) throws -> CGImage {
        let context = try Composer.makeOpaqueContext(PixelSize(size, size))
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        switch picture {
        case .allNineOff: drawRow(on: [], in: context)
        case .allNineBackOn: drawRow(on: Set(1...9), in: context)
        case .farEnd: drawRow(on: [9], in: context)
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

    /// Nine rings on the sword, ring 1 on the left; those in `on` are filled.
    private static func drawRow(on: Set<Int>, in context: CGContext) {
        let diameter = 90.0
        let gap = 13.0
        let width = 9 * diameter + 8 * gap
        let left = middle - width / 2
        // The sword: a bar through the rings' middles, a little longer than the row, its ends rounded.
        let swordHeight = 22.0
        let overhang = 10.0
        let swordRect = CGRect(x: left - overhang, y: middle - swordHeight / 2, width: width + 2 * overhang, height: swordHeight)
        context.setFillColor(sword)
        context.addPath(CGPath(roundedRect: swordRect, cornerWidth: swordHeight / 2, cornerHeight: swordHeight / 2, transform: nil))
        context.fillPath()
        for ring in 1...9 {
            let x = left + Double(ring - 1) * (diameter + gap)
            drawRing(in: CGRect(x: x, y: middle - diameter / 2, width: diameter, height: diameter), isOn: on.contains(ring), context: context)
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
            // A ring that is off is off the sword: its hole shows the background, not the bar.
            context.setFillColor(background)
            context.fillEllipse(in: rect)
            context.setStrokeColor(ring)
            context.setLineWidth(line)
            context.strokeEllipse(in: rect.insetBy(dx: line / 2, dy: line / 2))
        }
    }
}
