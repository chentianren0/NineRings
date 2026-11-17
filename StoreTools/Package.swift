// swift-tools-version: 6.2
import PackageDescription

// The tools that make the App Store pictures. Nothing here is part of the app: the Xcode project does not refer to
// this package, and the app does not link it. See README.md.
let package = Package(
    name: "StoreTools",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Only for the tests, which check that each moment of the series is a state the rules allow.
        .package(path: "../NineRingsKit"),
    ],
    targets: [
        // The app's own reading of the store-capture launch arguments: its files in NineRings/Store, linked here, so
        // that the tests check the code the app runs.
        .target(
            name: "StoreLaunch",
            swiftSettings: [.define("STORE_TOOLS")]
        ),
        .target(name: "StoreComposer"),
        .executableTarget(name: "store-compose", dependencies: ["StoreComposer"]),
        .testTarget(name: "StoreComposerTests", dependencies: ["StoreComposer"]),
        .testTarget(
            name: "StoreLaunchTests",
            dependencies: [
                "StoreLaunch",
                "StoreComposer",
                .product(name: "Puzzle", package: "NineRingsKit"),
                .product(name: "Motion", package: "NineRingsKit"),
                .product(name: "Session", package: "NineRingsKit"),
            ]
        ),
    ]
)
