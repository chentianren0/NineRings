import Foundation

/// The series of store pictures, as `Shots.json` describes it: the moments, in order, and the devices they are taken on.
/// The script and the composer both read it, so a moment is changed in one place.
public struct Manifest: Sendable, Codable {
    public enum Appearance: String, Sendable, Codable, CaseIterable {
        case light, dark
    }

    /// One moment of the series: the same on every device.
    public struct Moment: Sendable, Codable, Equatable {
        /// Its number in the series, as a file name: `01` is the first picture.
        public var id: String
        /// What it shows, for people.
        public var name: String
        /// The key of its caption in `Captions.xcstrings`.
        public var caption: String
        /// The appearance the series takes it in.
        public var appearance: Appearance
        /// The launch arguments that set the app up for it, after `-store-capture`.
        public var arguments: [String]
        /// A caption for this moment on one device only, by device id, such as the half-folded Duo's own.
        public var captionOn: [String: String]?

        public func captionKey(on device: String) -> String {
            captionOn?[device] ?? caption
        }
    }

    /// How a device's pictures are captured.
    public enum CaptureMethod: String, Sendable, Codable {
        /// The Mac app's window, by `screencapture`, placed on the store canvas.
        case macWindow = "mac-window"
        /// A simulator's screen, by the StoreShots UI test (not built yet).
        case simulator
    }

    public struct Device: Sendable, Codable, Equatable {
        public var id: String
        public var `class`: DeviceClass
        /// The store picture's size.
        public var size: PixelSize
        public var capture: CaptureMethod
        /// For the Mac: the window's size in points.
        public var window: PixelSize?
        /// For a simulator: its name, as `xcrun simctl list` gives it.
        public var simulator: String?
        /// For a simulator with several displays: which one, and how the hinge is set.
        public var display: String?
        public var hinge: String?
        /// The display's corner radius in the capture's pixels, for rounding a plain capture placed on a canvas.
        public var cornerRadius: Double?
    }

    /// The product page header: one still of the toy alone, from the app's offscreen renderer.
    public struct Header: Sendable, Codable, Equatable {
        public var size: PixelSize
        public var safeArea: [Double]
        public var move: Int
        public var progress: Double
        public var view: String
    }

    public var moments: [Moment]
    public var devices: [Device]
    public var header: Header

    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(Manifest.self, from: data)
    }

    public func device(_ id: String) throws -> Device {
        guard let device = devices.first(where: { $0.id == id }) else { throw ComposerError.unknownDevice(id) }
        return device
    }
}

public enum ComposerError: Error, CustomStringConvertible {
    case unknownDevice(String)
    case unreadable(URL)
    case unwritable(URL)
    case wrongCaptureSize(URL, PixelSize, expected: String)
    case missingCaption(String)
    case badBezel(String)

    public var description: String {
        switch self {
        case .unknownDevice(let id): "no device \(id) in the manifest"
        case .unreadable(let url): "cannot read \(url.lastPathComponent)"
        case .unwritable(let url): "cannot write \(url.lastPathComponent)"
        case .wrongCaptureSize(let url, let size, let expected): "\(url.lastPathComponent) is \(size), expected \(expected)"
        case .missingCaption(let key): "no caption \(key) in the catalog"
        case .badBezel(let reason): "bezel: \(reason)"
        }
    }
}
