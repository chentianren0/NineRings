# StoreShots: the UI tests that capture the iPhone, iPad and Duo pictures

`StoreShots` is a UI testing bundle in the Xcode project, added with the owner's agreement: the one change to the
project for the store pictures. Its one source file is `StoreShots/StoreShots.swift`. It is built, but has not yet been
run: on a simulator it waits until the simulator is free, and on the Mac a UI test takes over the screen, so the Mac's
pictures stay on the window capture (`scripts/store-assets.sh` captures its own app's window).

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
3. For each language, `xcodebuild test-without-building -scheme StoreShots`, then
   `xcrun xcresulttool export attachments` and `store-compose collect`, which copies each screenshot to
   `<moment>-<appearance>.png` by its attachment name.
4. Composes and checks the pictures as for the Mac: the composer refuses a capture that is not exactly the store size.
5. Clears the status bar, and shuts the simulator down if it booted it.

## Not yet tried, to check on the first run

- Whether the simulator runs the unsigned UI test runner (`CODE_SIGNING_ALLOWED=NO`, as for every build here).
- The layout of `xcresulttool`'s export manifest: `collect` looks for `exportedFileName` and the attachment's name
  anywhere in it, and is tested against a guess of that layout.
- The Duo: that the hinge angles give the closed and the half-folded layouts, and that the inner display's screenshot is
  2007 × 2853 in the laptop pose.
- On the Mac, if ever run there: the window in front, which would make the congratulation's Done button blue.
