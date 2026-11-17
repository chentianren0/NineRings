# StoreShots: the UI test target that would capture the iPhone, iPad and Duo pictures

Not built yet. Adding a target changes the Xcode project, which is the owner's. This file says exactly what it would add,
so it can be added quickly once he agrees. Everything else it needs already exists: the store-capture mode in the app
(`NineRings/Store/`), the series (`Shots.json`), the composer and the script.

## What it adds to the project

1. **A UI testing bundle target, `StoreShots`**, made with Xcode's "UI Testing Bundle" template:
   - Target to be tested: `NineRings`.
   - Supported platforms: iOS (iPhone and iPad) and macOS, as the app.
   - Its sources: a new synchronized folder `StoreShots/` at the top of the repository, with one file,
     `StoreShotsTests.swift` (below). Nothing else.
   - Build settings: the template's, with the project's own Swift version and deployment targets. No code signing
     change for the simulator; on the Mac the template's "Sign to Run Locally" as for the app.
2. **A scheme of its own, `StoreShots`**, whose test action runs only this target, so that the `NineRings` scheme and
   the checks on GitHub (`checks.yml`, which only builds) are untouched.
3. **A test plan, `StoreShots/StoreShots.xctestplan`**, with one configuration per App Store language, each setting
   "Application Language" and "Application Region": `en` (English, United States), `fr` (French, France), `zh-Hans`
   (Chinese, Simplified; China mainland), `zh-Hant` (Chinese, Traditional; Taiwan), `ja` (Japanese, Japan). Test
   timeouts on, at 10 minutes per test: the simulator's first frame can take a minute.

Nothing in the app target changes, and nothing of the test target ships.

## The tests

One test per moment of `Shots.json`, the same on every device. The test reads the series from the file the script
names in the environment (`TEST_RUNNER_STORE_MANIFEST`, which `xcodebuild` passes to the test runner as
`STORE_MANIFEST`; a simulator can read the Mac's files), so a moment changed in `Shots.json` needs no change here.

```swift
import XCTest

final class StoreShotsTests: XCTestCase {
    struct Moment: Decodable { var id: String; var appearance: String; var arguments: [String] }
    struct Series: Decodable { var moments: [Moment] }

    /// Set by the script for the device being captured.
    var device: String { ProcessInfo.processInfo.environment["STORE_DEVICE"] ?? "" }

    func moment(_ id: String) throws -> Moment {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["STORE_MANIFEST"])
        let series = try JSONDecoder().decode(Series.self, from: Data(contentsOf: URL(filePath: path)))
        return try XCTUnwrap(series.moments.first { $0.id == id })
    }

    func capture(_ id: String) throws {
        let moment = try moment(id)
        let appearance = ProcessInfo.processInfo.environment["STORE_APPEARANCE"].flatMap { $0 == "plan" ? nil : $0 } ?? moment.appearance
        #if os(iOS)
        let ui = XCUIDevice.shared
        ui.appearance = appearance == "dark" ? .dark : .light
        switch device {
        case "ipad-13": ui.orientation = .landscapeLeft
        case "duo-outer": ui.hinge?.angle = 0                    // closed: the outer display
        case "duo-inner": ui.hinge?.angle = .pi * 110 / 180      // half folded, the laptop pose
        default: ui.orientation = .portrait
        }
        #endif
        let app = XCUIApplication()
        // The system's options first, the store-capture options last (see NineRings/Store/StoreLaunch.swift).
        app.launchArguments = ["-appearance", appearance, "-window-size", "1280x800"] + moment.arguments + ["-store-capture"]
        app.launch()
        app.activate()                                            // on the Mac, the window in front
        XCTAssertTrue(app.descendants(matching: .any)["store-capture-ready"].waitForExistence(timeout: 300))
        // The Duo's displays are separate screens; the lit one is the one to keep.
        let screen = device == "duo-inner" ? XCUIScreen.screens.last! : XCUIScreen.main
        let shot = XCTAttachment(screenshot: screen.screenshot())
        shot.name = "\(moment.id)-\(appearance)"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    func test01() throws { try capture("01") }
    func test02() throws { try capture("02") }
    func test03() throws { try capture("03") }
    func test04() throws { try capture("04") }
    func test05() throws { try capture("05") }
    func test06() throws { try capture("06") }
}
```

To check when it is built: which entry of `XCUIScreen.screens` is the Duo's inner display on 27.3 (the interface
session found that `simctl` calls the outer one display 1 and the inner one display 3), and the hinge angle at which
the app's layout splits (it is the half-folded laptop pose the plan wants).

## What the script then does for each simulator device

In `scripts/store-assets.sh`, replacing today's "skipping" note, one device after another (one simulator at a time):

1. `xcrun simctl boot "<simulator>"` (the name from `Shots.json`), then a clean status bar:
   `xcrun simctl status_bar "<simulator>" override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4 --operatorName ''`.
2. For each language:
   `TEST_RUNNER_STORE_MANIFEST=<StoreTools/Shots.json> TEST_RUNNER_STORE_DEVICE=<id> TEST_RUNNER_STORE_APPEARANCE=<plan|light|dark> xcodebuild test -project NineRings.xcodeproj -scheme StoreShots -testPlan StoreShots -only-test-configuration <language> -destination "platform=iOS Simulator,name=<simulator>" -derivedDataPath scratch/store-build/app -resultBundlePath <out>/captures/<language>/<id>.xcresult CODE_SIGNING_ALLOWED=NO`.
3. `xcrun xcresulttool export attachments --path <result bundle> --output-path <out>/captures/<language>/<id>`, then
   rename each exported file to its attachment name (`01-light.png`; the export writes a `manifest.json` that maps them).
4. The same composer step as the Mac's: `store-compose compose --device <id> …`. The composer refuses a capture that is
   not exactly the device's store size, so a wrong simulator or orientation stops here.
5. `xcrun simctl shutdown "<simulator>"`.

The Mac could move to the same test later (`-destination 'platform=macOS'`): `activate()` brings the window in front,
which the background launch today cannot. Today's Mac path already draws the window as active
(`appearsActive`), except that the congratulation card's Done button still comes out gray.
