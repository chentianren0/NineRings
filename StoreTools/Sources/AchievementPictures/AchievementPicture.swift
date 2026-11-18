import CoreGraphics
import Foundation

/// The pictures of the app's four Game Center achievements, in the Bauhaus style chosen on 18 November: All Nine Off
/// and The Far End drawn in `Bauhaus.swift`, The Shortest Way and All Nine Back On in `ShortestWayAndBackOn.swift`,
/// all on the canvas in `Canvas.swift`, and made again with `swift run --package-path StoreTools achievement-pictures`.
///
/// App Store Connect asks for a `.png` or `.jpeg` of 1024 × 1024 pixels, at least 72 ppi, RGB. These are sRGB PNGs with
/// no alpha channel, marked 72 ppi.
public enum AchievementPicture: String, CaseIterable, Sendable {
    case allNineOff = "all_nine_off"
    case shortestWay = "shortest_way"
    case allNineBackOn = "all_nine_back_on"
    case farEnd = "far_end"

    /// The picture's file name: the achievement's identifier in Game Center.
    public var fileName: String { "\(rawValue).png" }

    /// The picture, 1024 × 1024, opaque, sRGB.
    public func image() -> CGImage {
        let canvas = makeCanvas()
        draw(self, in: canvas)
        return canvas.makeImage()!
    }

    /// Draws the picture and writes it into `folder` as `fileName`. Returns the file.
    @discardableResult
    public func write(into folder: URL) throws -> URL {
        let url = folder.appending(path: fileName)
        try writePNG(image(), to: url)
        return url
    }
}
