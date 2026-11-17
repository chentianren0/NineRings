# StoreShots: the UI tests that capture the iPhone, iPad and Duo pictures

`StoreShots` is a UI testing bundle in the Xcode project, added with the owner's agreement: the one change to the
project for the store pictures. Its source files are `StoreShots/StoreShots.swift` (the pictures) and
`StoreShots/StorePreview.swift` (the preview video). It runs on the simulators; on the Mac a UI test would take over the
screen, so the Mac's pictures stay on the window capture (`scripts/store-assets.sh` captures its own app's window).

## What it added to the project

Added with Xcode's own tools (the Xcode MCP's new-target and build-setting tools), from the multiplatform "UI Testing
Bundle" template, Swift and XCTest:

- In `NineRings.xcodeproj/project.xcproj`: a synchronized folder `StoreShots` belonging to the target `StoreShots`;
  its product `StoreShots.xctest` in Products; and the target, of type `bundle.ui-testing`, with the template's build
  settings, of which these were set to match the app: `PRODUCT_BUNDLE_IDENTIFIER` `com.chentianren.PlayNineRings.StoreShots`,
  `SUPPORTED_PLATFORMS` `iphoneos iphonesimulator macosx`, `TARGETED_DEVICE_FAMILY` `1,2`, deployment targets 27.2,
  `SWIFT_VERSION` 6.0 (the template's visionOS setting removed). Xcode also changed the project's `last-swift-update`
  from 27.2 to 27.3 on its own.
- No scheme file: the project's schemes are made automatically, and Xcode made one named `StoreShots` for the target.
  The `NineRings` scheme does not include it, so the app's builds, its tests and GitHub's checks never build or run it.
- No test plan: the language is passed to the app as a launch argument.
- No target to be tested: this project format has no such setting, and Xcode's tool does not offer one. The tests
  launch the app explicitly instead: on a simulator by its bundle identifier, after the script has installed its own
  build; on the Mac by the path of the app the script built. Neither can start another session's copy.

Nothing of it is part of the app.

## The tests

One test per moment of `Shots.json`, `test01` to `test06`, the same on every device. Each reads what to capture from the
environment the script sets through `xcodebuild`'s `TEST_RUNNER_` variables (`STORE_MANIFEST`, `STORE_DEVICE`,
`STORE_LANGUAGE`, `STORE_APPEARANCE`, and on the Mac `STORE_APP`), sets the device (light or dark; landscape for a
landscape store size; on the Duo the hinge closed for the outer display or at 110° for the half-folded laptop pose),
launches the app with the moment's arguments and `-store-capture`, waits up to five minutes for the element
`store-capture-ready`, and keeps a screenshot as the attachment `<moment>-<appearance>`. On a device it keeps the screen
whose size is the store size, so the Duo's lit display is found by its size, and a wrong device or orientation fails the
test with the sizes it found.

## What the script does for a simulator device

`scripts/store-assets.sh --devices iphone-6.3` (or `iphone-6.9`, `ipad-13`, `duo-outer`, `duo-inner`, several with
commas), one simulator at a time:

1. Builds the app (`NineRings`, Debug) and the tests (`StoreShots`, build for testing) for that simulator.
2. Boots it if it is not running, sets a clean status bar (9:41, full battery, full signal, no carrier), installs the
   app it built.
3. For each language, `xcodebuild test-without-building -scheme StoreShots -only-testing:StoreShots/StoreShots`, then
   `xcrun xcresulttool export attachments` and `store-compose collect`, which copies each screenshot to
   `<moment>-<appearance>.png` by its attachment name.
4. Composes and checks the pictures as for the Mac: the composer refuses a capture that is not the store size, upright
   (within a pixel, see below).
5. Clears the status bar, and shuts the simulator down if it booted it.

## The simulators

`Shots.json` names them: "iPhone 18 Pro", "iPhone 18 Pro Max", "iPad Pro 13-inch (M5)", "iPhone Duo", on iOS 27.3. The
script finds them by that exact name and stops if one is missing; make it with
`xcrun simctl create "iPhone 18 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro` (and `iPhone-18-Pro-Max`,
`iPad-Pro-13-inch-M5-12GB`, `iPhone-Duo`). Start a device from Device Hub before running the script: booted with
`simctl boot`, the iPad's home screen has failed to launch apps. The script then leaves it running.

## What the first run found (17 November 2026)

- The simulator runs the unsigned test runner, and `collect` reads `xcresulttool`'s export as it is.
- A turned device's screenshot keeps its pixels as the display scans them, with a note of how to turn them, which an
  attachment's PNG drops: the iPad's landscape pictures came out on their side inside the picture. The test draws each
  screenshot upright before keeping it, and the composer refuses a turned capture.
- The Duo refuses a screenshot of its unlit display ("Cannot screenshot inactive display"), and nothing says which display
  is lit. `XCUIScreen.main` is the lit one; the test waits after moving the hinge until it has the store size.
- The Duo's inner display is wide in portrait: the half-folded laptop pose is tall in landscape. The test picks the
  orientation from the lit screen's shape.
- The UI test's screenshot of the Duo's inner display is 2006 × 2852, a pixel short of 2007 × 2853 each way; the test and
  the composer accept a capture within a pixel (the composer scales the capture into its place anyway).
- A test with an expected failure (`XCTExpectFailure`) is left out of `xcresulttool export attachments`.

## The preview video

`scripts/store-preview.sh` (iPhone 6.3", 886 × 1920, and iPad 13", 1600 × 1200 landscape, in English) records the
simulator's screen with `simctl io recordVideo` while `StorePreview.testPreview` plays the plan's sequence with the
app's own buttons: ring 1 off, ring 3 off, ring 5 refused, Solve at 4×; then, launched again, the last ring off, the
congratulation and Put Every Ring Back On, which brings back the first frame. The test writes the time of each tap and
where it lands; the script cuts three pieces, joins them with half-second dissolves, draws a touch point at each tap,
and writes H.264 at 30 frames a second with a silent stereo AAC track, and the poster frame (ring 3 going down through
the slot). Measured on the iPhone recording: during a move a new frame comes at least every 1/30 s, but for one or two
repeated frames about every second or two.

Found on the way: a tap returns at once and the app keeps a tap made during a move for when it ends, so the test's
pauses set the pace; sending a tap takes over a second. The recorder's frames come out of order, and part-way through
ffmpeg would time them by their decoding times, about 5 s behind: the script decodes with `-fflags +igndts`.
