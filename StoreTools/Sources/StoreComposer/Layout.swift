import CoreGraphics

/// A device frame (bezel) to draw around the capture: an image, and where its screen is in it.
///
/// Apple's marketing guidelines allow only Apple's own bezels, used as they are: no tilt, crop, shadow or reflection,
/// and text beside the device, not on it. None is kept in the repository; the owner downloads them from Apple Design
/// Resources if the series uses them, and describes each in a small JSON file (see `Bezel.load`).
public struct BezelGeometry: Sendable, Equatable {
    /// The bezel image's size in pixels.
    public var size: PixelSize
    /// The screen's rectangle in the bezel image, in pixels from the top left.
    public var screen: CGRect
    /// The screen's corner radius in the bezel image's pixels.
    public var screenCornerRadius: Double

    public init(size: PixelSize, screen: CGRect, screenCornerRadius: Double = 0) {
        self.size = size
        self.screen = screen
        self.screenCornerRadius = screenCornerRadius
    }
}

/// Where everything goes on one store picture. Rectangles are in pixels from the top left.
///
/// The rules:
/// - With no caption and no bezel, a capture the size of the picture is the picture, untouched.
/// - Otherwise the capture (or the bezel around it) is as large as fits in the picture less a margin, under the caption
///   when there is one, centred; a capture is never enlarged, since that would blur it.
/// - The caption is one line in a band across the top, never over the app; a long one gets smaller, then two lines.
public struct Layout: Sendable, Equatable {
    public var canvas: PixelSize
    /// The band the caption is set in, or nil without a caption.
    public var captionBand: CGRect?
    /// The largest size the caption's type may have.
    public var captionFontSize: Double
    /// Where the capture's pixels go.
    public var capture: CGRect
    /// The corner radius to round the capture with, in the picture's pixels; 0 for none.
    public var captureCornerRadius: Double
    /// Where the bezel image goes, when there is one.
    public var bezel: CGRect?

    /// The margin around everything, as a share of the picture's shorter side.
    public static let marginShare = 0.05
    /// The caption band's height, as a share of the picture's height.
    public static func captionShare(portrait: Bool) -> Double { portrait ? 0.14 : 0.16 }
    /// The caption's largest type size, as a share of the picture's shorter side.
    public static let fontShare = 0.062

    public init(canvas: PixelSize, capture size: PixelSize, caption: Bool, bezel: BezelGeometry?, cornerRadius: Double = 0) {
        self.canvas = canvas
        let width = Double(canvas.width), height = Double(canvas.height)
        let shorter = min(width, height)
        captionFontSize = (shorter * Self.fontShare).rounded()

        if !caption, bezel == nil, size == canvas {
            captionBand = nil
            capture = CGRect(origin: .zero, size: canvas.cgSize)
            captureCornerRadius = 0
            self.bezel = nil
            return
        }

        let margin = (shorter * Self.marginShare).rounded()
        let top: Double
        if caption {
            let band = (height * Self.captionShare(portrait: canvas.isPortrait)).rounded()
            captionBand = CGRect(x: margin, y: 0, width: width - 2 * margin, height: band)
            top = band
        } else {
            captionBand = nil
            top = margin
        }
        let room = CGRect(x: margin, y: top, width: width - 2 * margin, height: height - top - margin)

        if let bezel {
            let scale = min(room.width / Double(bezel.size.width), room.height / Double(bezel.size.height))
            let frame = Self.centred(CGSize(width: Double(bezel.size.width) * scale, height: Double(bezel.size.height) * scale), in: room)
            self.bezel = frame
            capture = CGRect(
                x: frame.minX + bezel.screen.minX * scale, y: frame.minY + bezel.screen.minY * scale,
                width: bezel.screen.width * scale, height: bezel.screen.height * scale
            )
            captureCornerRadius = bezel.screenCornerRadius * scale
        } else {
            let scale = min(room.width / Double(size.width), room.height / Double(size.height), 1)
            capture = Self.centred(CGSize(width: Double(size.width) * scale, height: Double(size.height) * scale), in: room)
            captureCornerRadius = cornerRadius * scale
            self.bezel = nil
        }
    }

    /// `size` centred in `room`, on whole pixels.
    static func centred(_ size: CGSize, in room: CGRect) -> CGRect {
        let width = size.width.rounded(), height = size.height.rounded()
        return CGRect(x: (room.midX - width / 2).rounded(), y: (room.midY - height / 2).rounded(), width: width, height: height)
    }
}

/// The colours of a store picture.
public struct Palette: Sendable, Equatable {
    public var background: CGColor
    public var text: CGColor

    public static func `for`(_ appearance: Manifest.Appearance) -> Palette {
        switch appearance {
        // Apple's own light gray and near-black, which sit quietly around the app's white or near-black backdrop.
        case .light: Palette(background: CGColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1), text: CGColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1))
        case .dark: Palette(background: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), text: CGColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1))
        }
    }
}
