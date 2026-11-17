import XCTest

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
        switch setup.device["hinge"] as? String {
        case "closed": device.hinge?.angle = 0
        case "half-open": device.hinge?.angle = .pi * 110 / 180
        case "open": device.hinge?.angle = .pi
        default: break
        }
        device.orientation = isLandscape ? .landscapeLeft : .portrait
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
        let attachment = XCTAttachment(screenshot: screenshot)
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

    /// On the Mac, the app's window. On a device, the screen that has the store picture's size: the Duo's displays
    /// are separate screens, and which one is lit depends on the hinge.
    private func screenshot(of app: XCUIApplication, size: (width: Int, height: Int)) throws -> XCUIScreenshot {
        #if os(macOS)
        return app.windows.firstMatch.screenshot()
        #else
        let shots = XCUIScreen.screens.map { $0.screenshot() }
        func pixels(_ shot: XCUIScreenshot) -> (Int, Int) {
            let image = shot.image
            return (Int((image.size.width * image.scale).rounded()), Int((image.size.height * image.scale).rounded()))
        }
        if let match = shots.first(where: { pixels($0) == (size.width, size.height) }) {
            return match
        }
        for shot in shots {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "unmatched-\(pixels(shot).0)x\(pixels(shot).1)"
            add(attachment)
        }
        return try XCTUnwrap(nil as XCUIScreenshot?, "no screen is \(size.width)x\(size.height); the screens are \(shots.map { "\(pixels($0).0)x\(pixels($0).1)" })")
        #endif
    }
}
