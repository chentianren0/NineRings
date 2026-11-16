#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Lays captured frames out on one image, in rows of four, each with a caption under it.
enum ContactSheet {
    struct Frame {
        var image: CGImage
        var caption: String
    }

    static func write(_ frames: [Frame], title: String, appearance: Backdrop.Appearance, to url: URL) throws {
        guard let first = frames.first else { return }
        let columns = min(4, frames.count)
        let rows = (frames.count + columns - 1) / columns
        let tileWidth = 640.0
        let tileHeight = tileWidth * Double(first.image.height) / Double(first.image.width)
        let captionHeight = 34.0, titleHeight = 56.0, margin = 16.0
        let width = margin + Double(columns) * (tileWidth + margin)
        let height = titleHeight + Double(rows) * (tileHeight + captionHeight + margin) + margin

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = unsafe CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Capture.CaptureError.noSheet }

        let dark = appearance == .dark
        context.setFillColor(dark ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ink = dark ? CGColor(gray: 0.92, alpha: 1) : CGColor(gray: 0.12, alpha: 1)

        // Core Graphics counts y from the bottom.
        draw(title, size: 26, color: ink, at: CGPoint(x: margin, y: height - titleHeight + 16), in: context)
        for (index, frame) in frames.enumerated() {
            let column = Double(index % columns), row = Double(index / columns)
            let x = margin + column * (tileWidth + margin)
            let top = height - titleHeight - row * (tileHeight + captionHeight + margin)
            let rect = CGRect(x: x, y: top - tileHeight, width: tileWidth, height: tileHeight)
            context.draw(frame.image, in: rect)
            context.setStrokeColor(dark ? CGColor(gray: 0.3, alpha: 1) : CGColor(gray: 0.8, alpha: 1))
            context.stroke(rect, width: 1)
            draw(frame.caption, size: 18, color: ink, at: CGPoint(x: x + 4, y: top - tileHeight - 24), in: context)
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Capture.CaptureError.noSheet }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Capture.CaptureError.noSheet }
    }

    private static func draw(_ text: String, size: CGFloat, color: CGColor, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
#endif
