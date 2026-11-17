import XCTest
#if os(iOS)
import UIKit
#endif

/// Captures the App Store pictures: one test per moment of the series, the same on every device.
///
/// Run by `scripts/store-assets.sh`, never with the app's or the package's tests: it launches the app in the
/// store-capture mode (NineRings/Store), waits for its ready signal and keeps a screenshot of the screen as an
/// attachment named `<moment>-<appearance>`, which the script exports and composes. What to capture comes from the
/// environment the script sets, through `xcodebuild`'s `TEST_RUNNER_` variables:
///
/// - `STORE_MANIFEST`: the path of StoreTools/Shots.json, the series (a simulator reads the Mac's files).
/// - `STORE_DEVICE`: the device's id in it, such as `iphone-6.3` or `duo-inner`.
/// - `STORE_LANGUAGE`: the App Store language, such as `fr`; the app runs in it.
/// - `STORE_APPEARANCE`: `plan` for each moment's own, or `light` or `dark` for all.
/// - On the Mac, `STORE_APP`: the path of the app built for the pictures, so that no other copy is launched.
///
/// On a simulator the app is launched by its bundle identifier: the script installs its own build first.
@MainActor
final class StoreShots: XCTestCase {
    private struct Setup {
        var moment: [String: Any]
        var device: [String: Any]
        var language: String
        var appearance: String
        var size: (width: Int, height: Int)
    }

    override func setUp() {
        continueAfterFailure = false
    }

    func test01() throws { try capture("01") }
    func test02() throws { try capture("02") }
    func test03() throws { try capture("03") }
    func test04() throws { try capture("04") }
    func test05() throws { try capture("05") }
    func test06() throws { try capture("06") }

    private func capture(_ id: String) throws {
        let setup = try setup(for: id)
        let app = try application()
        let isLandscape = setup.size.width > setup.size.height

        #if os(iOS)
        let device = XCUIDevice.shared
        device.appearance = setup.appearance == "dark" ? .dark : .light
        // The Duo: closed shows the outer display; half folded, the laptop pose, splits the inner one.
        let angle: Double? = switch setup.device["hinge"] as? String {
        case "closed": 0
        case "half-open": .pi * 110 / 180
        case "open": .pi
        default: nil
        }
        if let angle, let hinge = device.hinge, abs(hinge.angle - angle) > 0.01 {
            hinge.angle = angle
            // While the displays change over, the main screen can be the one going dark, which refuses a screenshot.
            Thread.sleep(forTimeInterval: 3)
        }
        // The orientation that gives the store picture's shape. A device's portrait is not always tall: the Duo's inner
        // display is wide in portrait, and its half-folded laptop pose is tall in landscape.
        // The display the hinge lights takes a moment to become the main screen.
        let deadline = Date.now.addingTimeInterval(20)
        while !Self.isStoreScreen(XCUIScreen.main.screenshot(), size: setup.size), Date.now < deadline {
            Thread.sleep(forTimeInterval: 1)
        }
        device.orientation = isLandscape ? .landscapeLeft : .portrait
        if Self.isWide(XCUIScreen.main.screenshot()) != isLandscape {
            device.orientation = isLandscape ? .portrait : .landscapeLeft
        }
        #endif

        // The system's options first, the store-capture options last (see NineRings/Store/StoreLaunch.swift).
        var arguments = ["-AppleLanguages", "(\(setup.language))", "-appearance", setup.appearance]
        if let window = setup.device["window"] as? [Int], window.count == 2 {
            arguments += ["-window-size", "\(window[0])x\(window[1])"]
        }
        arguments += (setup.moment["arguments"] as? [String] ?? []) + ["-store-capture"]
        app.launchArguments = arguments
        app.launch()
        app.activate()

        let ready = app.descendants(matching: .any)["store-capture-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 300), "the app did not say it was ready")

        let screenshot = try screenshot(of: app, size: setup.size)
        #if os(iOS)
        // A turned device's screenshot keeps its pixels as the screen scans them and says how to turn them; the PNG of
        // the attachment would drop that. Drawn upright first, the pixels are the picture as it looks.
        let attachment = XCTAttachment(data: try XCTUnwrap(upright(screenshot.image).pngData()), uniformTypeIdentifier: "public.png")
        #else
        let attachment = XCTAttachment(screenshot: screenshot)
        #endif
        attachment.name = "\(id)-\(setup.appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    private func setup(for id: String) throws -> Setup {
        let environment = ProcessInfo.processInfo.environment
        let path = try XCTUnwrap(environment["STORE_MANIFEST"], "STORE_MANIFEST is not set: run this from scripts/store-assets.sh")
        let series = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: path))) as? [String: Any])
        let moments = try XCTUnwrap(series["moments"] as? [[String: Any]])
        let moment = try XCTUnwrap(moments.first { $0["id"] as? String == id }, "no moment \(id)")
        let deviceID = try XCTUnwrap(environment["STORE_DEVICE"], "STORE_DEVICE is not set")
        let devices = try XCTUnwrap(series["devices"] as? [[String: Any]])
        let device = try XCTUnwrap(devices.first { $0["id"] as? String == deviceID }, "no device \(deviceID)")
        let size = try XCTUnwrap(device["size"] as? [Int])
        let choice = environment["STORE_APPEARANCE"] ?? "plan"
        let appearance = choice == "plan" ? (moment["appearance"] as? String ?? "light") : choice
        return Setup(
            moment: moment, device: device, language: environment["STORE_LANGUAGE"] ?? "en",
            appearance: appearance, size: (size[0], size[1])
        )
    }

    private func application() throws -> XCUIApplication {
        #if os(macOS)
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["STORE_APP"], "STORE_APP is not set")
        return XCUIApplication(url: URL(filePath: path))
        #else
        return XCUIApplication(bundleIdentifier: "com.chentianren.PlayNineRings")
        #endif
    }

    #if os(iOS)
    /// The image drawn as it looks, at its own scale, without transparency.
    private func upright(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
    }
    #endif

    /// On the Mac, the app's window. On a device, its main screen, which is the lit one: on the Duo, the outer display
    /// closed and the inner one open (the unlit one cannot be captured, and the app's own screenshot can be a pixel
    /// short where a screen is not a whole number of points).
    private func screenshot(of app: XCUIApplication, size: (width: Int, height: Int)) throws -> XCUIScreenshot {
        #if os(macOS)
        return app.windows.firstMatch.screenshot()
        #else
        let shot = XCUIScreen.main.screenshot()
        let pixels = Self.pixels(shot)
        // Within a pixel: the Duo's inner display comes as 2006 x 2852 of its 2007 x 2853.
        guard abs(pixels.0 - size.width) <= 1, abs(pixels.1 - size.height) <= 1 else {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "unmatched-\(pixels.0)x\(pixels.1)"
            add(attachment)
            return try XCTUnwrap(nil as XCUIScreenshot?, "the screen is \(pixels.0)x\(pixels.1), not \(size.width)x\(size.height)")
        }
        return shot
        #endif
    }

    #if os(iOS)
    private static func pixels(_ shot: XCUIScreenshot) -> (Int, Int) {
        let image = shot.image
        return (Int((image.size.width * image.scale).rounded()), Int((image.size.height * image.scale).rounded()))
    }

    /// Whether the screenshot has the store picture's size, within a pixel, either way round.
    private static func isStoreScreen(_ shot: XCUIScreenshot, size: (width: Int, height: Int)) -> Bool {
        let (width, height) = pixels(shot)
        let near = { (a: Int, b: Int) in abs(a - b) <= 1 }
        return (near(width, size.width) && near(height, size.height)) || (near(width, size.height) && near(height, size.width))
    }

    private static func isWide(_ shot: XCUIScreenshot) -> Bool {
        let (width, height) = pixels(shot)
        return width > height
    }
    #endif
}
