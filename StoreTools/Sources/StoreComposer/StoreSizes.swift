import CoreGraphics

/// A size in pixels.
public struct PixelSize: Hashable, Sendable, Codable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        width = try container.decode(Int.self)
        height = try container.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }

    public var rotated: PixelSize { PixelSize(height, width) }
    public var isPortrait: Bool { height > width }
    public var cgSize: CGSize { CGSize(width: width, height: height) }
    public var description: String { "\(width)x\(height)" }

    public static func * (size: PixelSize, factor: Int) -> PixelSize {
        PixelSize(size.width * factor, size.height * factor)
    }
}

/// The kinds of picture the App Store takes, each with the sizes App Store Connect accepts for it.
///
/// From Apple's screenshot specifications and creative assets specifications, read on 17 November 2026. One set per
/// class is enough: the store scales it for the smaller devices of the class.
public enum DeviceClass: String, Sendable, Codable, CaseIterable {
    /// Mac, 16:10, landscape only.
    case mac
    /// iPhone with Dynamic Island, 6.3 inch: the required iPhone size.
    case iPhone63 = "iphone-6.3"
    /// iPhone with Dynamic Island, 6.9 inch.
    case iPhone69 = "iphone-6.9"
    /// iPad, 13 inch.
    case iPad13 = "ipad-13"
    /// iPhone Duo, closed: its outer display.
    case duoOuter = "duo-outer"
    /// iPhone Duo, open or half folded: its inner display.
    case duoInner = "duo-inner"
    /// The product page header, a creative asset: 21:9, iPhone and iPad only.
    case header

    /// Every size App Store Connect accepts for the class, in each orientation it allows.
    public var acceptedSizes: [PixelSize] {
        switch self {
        case .mac:
            [PixelSize(2880, 1800), PixelSize(2560, 1600), PixelSize(1440, 900), PixelSize(1280, 800)]
        case .iPhone63:
            Self.bothWays([PixelSize(1206, 2622), PixelSize(1179, 2556)])
        case .iPhone69:
            Self.bothWays([PixelSize(1320, 2868), PixelSize(1290, 2796), PixelSize(1260, 2736)])
        case .iPad13:
            Self.bothWays([PixelSize(2064, 2752), PixelSize(2048, 2732)])
        case .duoOuter:
            Self.bothWays([PixelSize(1398, 2034)])
        case .duoInner:
            Self.bothWays([PixelSize(2007, 2853)])
        case .header:
            [PixelSize(3840, 1646)]
        }
    }

    public func accepts(_ size: PixelSize) -> Bool {
        acceptedSizes.contains(size)
    }

    /// For the header: the part of the picture where the key art must sit, as x, y, width and height from the top left.
    public var safeArea: CGRect? {
        self == .header ? CGRect(x: 1097, y: 493, width: 1646, height: 661) : nil
    }

    private static func bothWays(_ sizes: [PixelSize]) -> [PixelSize] {
        sizes + sizes.map(\.rotated)
    }
}
