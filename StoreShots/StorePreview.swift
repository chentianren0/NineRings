import XCTest

/// Plays the App Store preview's sequence on a simulator while `scripts/store-preview.sh` records its screen: the app used
/// as a person uses it, through its own controls, at its own pace. It writes when each tap is made, and where it lands,
/// so the script can cut the recording and draw the touches; the script finds where each move ends in the recording. Never run with the app's tests or the pictures.
///
/// The environment, through `xcodebuild`'s `TEST_RUNNER_` variables:
/// - `STORE_MARKS`: the file to write the steps to, one per line: `<name> <seconds since 1970>` and, for a tap,
///   `<x> <y>` in points of the screen as it is turned.
/// - `STORE_LANDSCAPE`: `1` for a landscape preview.
///
/// The buttons are found by their English names: the preview is made in English.
@MainActor
final class StorePreview: XCTestCase {
    private var lines: [String] = []

    override func setUp() {
        continueAfterFailure = false
    }

    func testPreview() throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try XCTUnwrap(environment["STORE_MARKS"], "STORE_MARKS is not set: run this from scripts/store-preview.sh")
        let device = XCUIDevice.shared
        device.appearance = .light
        device.orientation = environment["STORE_LANDSCAPE"] == "1" ? .landscapeLeft : .portrait
        let app = XCUIApplication(bundleIdentifier: "com.chentianren.PlayNineRings")
        defer { try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8) }

        // Every ring on. Ring 1 comes off, then ring 3; ring 5 is refused, with the reason; then solve at 4x.
        try launch(app, state: "111111111")
        let size = app.frame.size
        lines.append("screen 0 \(size.width) \(size.height)")
        mark("start")
        // Each tap comes about as the move before it ends: sending a tap takes over a second, and the app keeps a tap
        // made during a move for when the move ends.
        try tap(app.buttons["Ring 1"], "ring1")
        pause(1.9)
        try tap(app.buttons["Ring 3"], "ring3")
        pause(2.6)
        try tap(app.buttons["Ring 5"], "refuse")
        pause(3)
        try tap(app.buttons["Speed"], "speed")
        try tap(app.buttons["4×"], "speed4")
        pause(1)
        try tap(app.buttons["Solve"], "solve")
        pause(8)
        mark("solving")
        app.terminate()

        // The last ring comes off, the congratulation, and every ring back on: the start again.
        try launch(app, state: "100000000")
        mark("start2")
        try tap(app.buttons["Ring 1"], "last")
        pause(5)
        try tap(app.buttons["Put Every Ring Back On"], "reset")
        pause(3.5)
        mark("end")
        app.terminate()
    }

    private func launch(_ app: XCUIApplication, state: String) throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-state", state, "-store-capture"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["store-capture-ready"].waitForExistence(timeout: 300), "the app did not say it was ready")
        pause(1)
    }

    private func mark(_ name: String, at point: CGPoint? = nil) {
        let time = String(format: "%.3f", Date.now.timeIntervalSince1970)
        lines.append(point.map { "\(name) \(time) \($0.x) \($0.y)" } ?? "\(name) \(time)")
    }

    private func tap(_ element: XCUIElement, _ name: String) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(name) button")
        let frame = element.frame
        // Just before the tap, which follows at once.
        mark(name, at: CGPoint(x: frame.midX, y: frame.midY))
        element.tap()
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
