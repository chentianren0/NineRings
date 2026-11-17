import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A bezel image with its geometry, read from a JSON file such as
/// `{"image": "iPhone Duo - Silver.png", "screen": [x, y, width, height], "screenCornerRadius": 0}`, the image's
/// path relative to the JSON file.
public struct Bezel {
    public var image: CGImage
    public var geometry: BezelGeometry

    public static func load(_ url: URL) throws -> Bezel {
        struct File: Decodable {
            var image: String
            var screen: [Double]
            var screenCornerRadius: Double?
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard file.screen.count == 4 else { throw ComposerError.badBezel("screen needs x, y, width and height") }
        let image = try PNG.read(url.deletingLastPathComponent().appending(path: file.image))
        let screen = CGRect(x: file.screen[0], y: file.screen[1], width: file.screen[2], height: file.screen[3])
        guard CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(screen) else {
            throw ComposerError.badBezel("the screen lies outside the image")
        }
        return Bezel(image: image, geometry: BezelGeometry(size: PixelSize(image.width, image.height), screen: screen, screenCornerRadius: file.screenCornerRadius ?? 0))
    }
}

/// Draws store pictures.
public enum Composer {
    /// One store picture: `capture` on a canvas of `canvas`'s size, with `caption` above it if given, in a bezel if
    /// given. The result has no transparency.
    public static func compose(
        capture: CGImage, canvas: PixelSize, caption: String?, language: String,
        appearance: Manifest.Appearance, bezel: Bezel?, cornerRadius: Double
    ) throws -> CGImage {
        let layout = Layout(
            canvas: canvas, capture: PixelSize(capture.width, capture.height), caption: caption != nil,
            bezel: bezel?.geometry, cornerRadius: cornerRadius
        )
        let palette = Palette.for(appearance)
        let context = try makeOpaqueContext(canvas)
        context.interpolationQuality = .high
        context.setFillColor(palette.background)
        context.fill(CGRect(origin: .zero, size: canvas.cgSize))

        // Core Graphics counts y from the bottom; the layout from the top.
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: Double(canvas.height) - rect.maxY, width: rect.width, height: rect.height)
        }

        let captureRect = flipped(layout.capture)
        context.saveGState()
        if layout.captureCornerRadius > 0 {
            context.addPath(CGPath(roundedRect: captureRect, cornerWidth: layout.captureCornerRadius, cornerHeight: layout.captureCornerRadius, transform: nil))
            context.clip()
        }
        context.draw(capture, in: captureRect)
        context.restoreGState()
        if let bezel, let frame = layout.bezel {
            context.draw(bezel.image, in: flipped(frame))
        }
        if let caption, let band = layout.captionBand {
            let set = CaptionText.fit(caption, language: language, maxFontSize: layout.captionFontSize, width: band.width, height: band.height * 0.8)
            set.draw(in: flipped(band), color: palette.text, context: context)
        }
        guard let image = context.makeImage() else { throw ComposerError.unwritable(URL(filePath: "/")) }
        return image
    }

    /// A finished picture from one that may carry transparency, such as the offscreen renderer's: drawn on
    /// `background` at the same size.
    public static func flatten(_ image: CGImage, background: CGColor) throws -> CGImage {
        let size = PixelSize(image.width, image.height)
        let context = try makeOpaqueContext(size)
        context.setFillColor(background)
        context.fill(CGRect(origin: .zero, size: size.cgSize))
        context.draw(image, in: CGRect(origin: .zero, size: size.cgSize))
        guard let flat = context.makeImage() else { throw ComposerError.unwritable(URL(filePath: "/")) }
        return flat
    }

    /// An sRGB context with no alpha channel, so that the PNG written from it has none.
    static func makeOpaqueContext(_ size: PixelSize) throws -> CGContext {
        guard let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ComposerError.unwritable(URL(filePath: "/")) }
        return context
    }
}

/// A caption set to fit its band: one line, smaller if it must be, or two lines if one would be too small.
public struct CaptionText {
    public let lines: [CTLine]
    public let fontSize: Double
    public let lineHeight: Double

    /// The smallest the type may get on one line, as a share of the largest, before the caption takes two lines.
    public static let smallestShare = 0.72

    public var width: Double {
        lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
    }

    public var height: Double { lineHeight * Double(lines.count) }

    public static func font(size: Double) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
    }

    public static func fit(_ text: String, language: String, maxFontSize: Double, width: Double, height: Double) -> CaptionText {
        var size = maxFontSize
        while size >= maxFontSize * smallestShare {
            let line = makeLine(text, language: language, size: size)
            if CTLineGetTypographicBounds(line, nil, nil, nil) <= width {
                return CaptionText(lines: [line], fontSize: size, lineHeight: lineHeight(size))
            }
            size -= max(1, maxFontSize * 0.02)
        }
        // Two lines, broken where the text allows, at a size where both fit across and together fit down.
        size = min(maxFontSize * smallestShare, height / 2 / 1.2)
        while size > 8 {
            let lines = wrap(text, language: language, size: size, width: width)
            if lines.count <= 2, lines.allSatisfy({ CTLineGetTypographicBounds($0, nil, nil, nil) <= width }) {
                return CaptionText(lines: lines, fontSize: size, lineHeight: lineHeight(size))
            }
            size -= 1
        }
        return CaptionText(lines: [makeLine(text, language: language, size: 8)], fontSize: 8, lineHeight: lineHeight(8))
    }

    static func lineHeight(_ size: Double) -> Double { (size * 1.2).rounded() }

    static func attributed(_ text: String, language: String, size: Double) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: size),
            // The language picks the right forms where scripts share characters, as Chinese and Japanese do.
            NSAttributedString.Key(kCTLanguageAttributeName as String): language,
            // Drawn in the context's fill colour, set for the appearance.
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
    }

    static func makeLine(_ text: String, language: String, size: Double) -> CTLine {
        CTLineCreateWithAttributedString(attributed(text, language: language, size: size))
    }

    static func wrap(_ text: String, language: String, size: Double, width: Double) -> [CTLine] {
        let string = attributed(text, language: language, size: size)
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        var lines: [CTLine] = []
        var start = 0
        while start < string.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, width)
            guard count > 0 else { break }
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    /// Draws the lines centred in `band`, a rectangle in Core Graphics' coordinates (y from the bottom).
    func draw(in band: CGRect, color: CGColor, context: CGContext) {
        context.saveGState()
        context.setFillColor(color)
        let font = Self.font(size: fontSize)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        // The block of lines, centred: the first baseline sits one ascent below its top, less the line gap shared out.
        var baseline = band.midY + height / 2 - (lineHeight - (ascent + descent)) / 2 - ascent
        for line in lines {
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: band.midX - lineWidth / 2, y: baseline)
            CTLineDraw(line, context)
            baseline -= lineHeight
        }
        context.restoreGState()
    }
}
