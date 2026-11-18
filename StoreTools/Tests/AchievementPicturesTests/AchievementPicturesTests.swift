import AchievementPictures
import CoreGraphics
import Foundation
import ImageIO
import Session
import Testing

/// The pictures in StoreTools/AchievementPictures/, as they are uploaded to App Store Connect.
@Suite struct AchievementPicturesTests {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "AchievementPictures")

    private func source(_ picture: AchievementPicture) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithURL(Self.folder.appending(path: picture.fileName) as CFURL, nil))
    }

    /// The image's pixels, as sRGB bytes, four per pixel, the fourth unused.
    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    @Test func eachPictureIsNamedByOneOfTheAppsAchievements() throws {
        let identifiers = Set(Achievement.allCases.map(\.rawValue))
        #expect(Set(AchievementPicture.allCases.map(\.rawValue)) == identifiers)
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
        #expect(Set(files) == Set(identifiers.map { "\($0).png" }))
    }

    /// What App Store Connect asks of an achievement's image: a `.png` or `.jpeg` of 1024 × 1024 pixels, at least
    /// 72 ppi, RGB. Game Center shows it in a circle, so it has no transparency.
    @Test(arguments: AchievementPicture.allCases)
    func eachIsWhatAppStoreConnectAsksFor(_ picture: AchievementPicture) throws {
        let source = try source(picture)
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1024)
        #expect(properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String)
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool != true)
        #expect((properties[kCGImagePropertyDPIWidth] as? Double ?? 0) >= 72)
        #expect((properties[kCGImagePropertyDPIHeight] as? Double ?? 0) >= 72)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))
    }

    /// The files are what the code draws, so that a change to a picture is made in the code and drawn again with
    /// `swift run --package-path StoreTools achievement-pictures`. On the Mac they were drawn on they are the same pixel
    /// for pixel; another version of CoreGraphics may smooth an edge a little differently, which this allows.
    @Test(arguments: AchievementPicture.allCases)
    func eachFileIsWhatTheCodeDraws(_ picture: AchievementPicture) throws {
        let file = pixels(try #require(CGImageSourceCreateImageAtIndex(try source(picture), 0, nil)))
        let drawn = pixels(picture.image())
        try #require(file.count == drawn.count)
        var different = 0
        for pixel in stride(from: 0, to: file.count, by: 4) {
            let apart = (0..<3).map { abs(Int(file[pixel + $0]) - Int(drawn[pixel + $0])) }.max()!
            if apart > 32 { different += 1 }
        }
        #expect(different <= file.count / 4 / 500, "\(different) pixels differ")
    }

    @Test func theFourAreDifferent() {
        #expect(Set(AchievementPicture.allCases.map { pixels($0.image()) }).count == 4)
    }
}
