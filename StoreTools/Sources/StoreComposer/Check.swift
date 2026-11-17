import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reading and writing PNG files.
public enum PNG {
    public static func read(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ComposerError.unreadable(url) }
        return image
    }

    public static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ComposerError.unwritable(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ComposerError.unwritable(url) }
    }
}

/// Checks a finished picture against what App Store Connect accepts, by reading the file back.
public enum Check {
    public struct Report: Sendable {
        public var size: PixelSize
        public var problems: [String]
        /// For the header: where the toy is, as x, y, width and height from the top left.
        public var content: CGRect?
    }

    /// What is wrong with the picture at `url` as one of `deviceClass`'s.
    public static func check(_ url: URL, as deviceClass: DeviceClass) throws -> Report {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ComposerError.unreadable(url) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let size = PixelSize(image.width, image.height)
        var problems: [String] = []

        if type != UTType.png.identifier && type != UTType.jpeg.identifier {
            problems.append("is \(type), not PNG or JPEG")
        }
        if !deviceClass.accepts(size) {
            problems.append("is \(size), not one of \(deviceClass.rawValue)'s sizes (\(deviceClass.acceptedSizes.map(\.description).joined(separator: ", ")))")
        }
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) ?? false
        if hasAlpha || ![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo) {
            problems.append("has an alpha channel")
        }
        if image.colorSpace?.model != .rgb {
            problems.append("is not RGB")
        }

        var content: CGRect?
        if let safe = deviceClass.safeArea {
            let bounds = contentBounds(image)
            content = bounds
            // The toy's soft floor shadow may reach a little past its ends.
            if let bounds, !safe.insetBy(dx: -safe.width * 0.03, dy: -safe.height * 0.03).contains(bounds) {
                problems.append("its content \(describe(bounds)) leaves the safe area \(describe(safe))")
            }
        }
        return Report(size: size, problems: problems, content: content)
    }

    /// The smallest rectangle holding every pixel that differs from the top-left corner's colour by more than a few
    /// levels, from the top left; nil for a plain picture.
    public static func contentBounds(_ image: CGImage, tolerance: Int = 10) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let background = (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width {
                let i = row + x * 4
                let difference = max(abs(Int(pixels[i]) - background.0), abs(Int(pixels[i + 1]) - background.1), abs(Int(pixels[i + 2]) - background.2))
                if difference > tolerance {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        // The bitmap's first row is the picture's top.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }
}
