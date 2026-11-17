import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Rules about the app's icon that its code must keep, read from the app's sources in this repository.
///
/// An iOS app cannot load its own icon. `UIImage(named: "AppIcon")` works in a local build, whose asset catalog holds
/// the icon as flat images, but it crashed the app from TestFlight on iPhone and iPad as soon as About appeared: there
/// the icon is processed again for each device, and UIKit raised an exception making an image of it. So the About
/// page shows a copy, rendered from the app icon by `scripts/render-about-icon.sh`.
@Suite struct AppIconRulesTests {
    /// The repository's root: this file is in NineRingsKit/Tests/AppRulesTests.
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let aboutIcon = root.appending(path: "NineRings/Assets.xcassets/AboutIcon.imageset")

    /// Every Swift file of the app, with its lines of code: comments are left out.
    private static func appCode() throws -> [(file: String, line: Int, code: String)] {
        let app = root.appending(path: "NineRings")
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty, "the app's sources are where this test looks for them")
        return try files.flatMap { url in
            try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { (url.lastPathComponent, $0.offset + 1, String($0.element.split(separator: "//", maxSplits: 1).first ?? "")) }
        }
    }

    @Test func theAppNeverLoadsItsOwnIcon() throws {
        let forbidden = ["CFBundleIcon", "CFBundlePrimaryIcon", "named: \"AppIcon", "Image(\"AppIcon"]
        let found = try Self.appCode().filter { line in forbidden.contains { line.code.contains($0) } }
        #expect(found.isEmpty, "the app loads its own icon at \(found.map { "\($0.file):\($0.line)" })")
    }

    @Test func theAboutIconHasALightAndADarkRendition() throws {
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.aboutIcon.appending(path: "Contents.json"))) as? [String: Any]
        let images = contents?["images"] as? [[String: Any]] ?? []
        let files = images.compactMap { $0["filename"] as? String }
        #expect(files.count == 2)
        #expect(images.contains { $0["appearances"] != nil }, "one rendition is for the dark appearance")
        for file in files {
            let size = try FileManager.default.attributesOfItem(atPath: Self.aboutIcon.appending(path: file).path)[.size] as? Int
            #expect((size ?? 0) > 0, "\(file) is there")
        }
    }

    /// The copy follows the icon: when the icon changes, run scripts/render-about-icon.sh again.
    @Test func theAboutIconWasRenderedFromTheCurrentAppIcon() throws {
        #if canImport(CryptoKit)
        let recorded = try String(contentsOf: Self.root.appending(path: "scripts/about-icon-source.sha256"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(recorded == (try Self.appIconDigest()), "the app icon has changed since the About icon was rendered: run scripts/render-about-icon.sh")
        #endif
    }

    #if canImport(CryptoKit)
    /// The same digest as the script's: `shasum -a 256` of each file of AppIcon.icon, sorted by path, then of that list.
    private static func appIconDigest() throws -> String {
        let base = root.appending(path: "NineRings")
        let icon = base.appending(path: "AppIcon.icon")
        let paths = (FileManager.default.enumerator(at: icon, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && $0.lastPathComponent != ".DS_Store" }
            .map { String($0.standardizedFileURL.path.dropFirst(base.standardizedFileURL.path.count + 1)) }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let list = try paths.map { path in
            let data = try Data(contentsOf: base.appending(path: path))
            return "\(hex(SHA256.hash(data: data)))  \(path)\n"
        }.joined()
        return hex(SHA256.hash(data: Data(list.utf8)))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
    #endif
}
