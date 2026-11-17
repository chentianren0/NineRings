// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NineRingsKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Puzzle", targets: ["Puzzle"]),
        .library(name: "Toy", targets: ["Toy"]),
        .library(name: "Motion", targets: ["Motion"]),
        .library(name: "Geometry", targets: ["Geometry"]),
        .library(name: "Session", targets: ["Session"]),
    ],
    targets: [
        .target(
            name: "Puzzle",
            swiftSettings: [.strictMemorySafety()]
        ),
        .target(
            name: "Toy",
            dependencies: ["Puzzle"],
            swiftSettings: [.strictMemorySafety()]
        ),
        .target(
            name: "Motion",
            dependencies: ["Puzzle", "Toy"],
            swiftSettings: [.strictMemorySafety()]
        ),
        .target(
            name: "Geometry",
            swiftSettings: [.strictMemorySafety()]
        ),
        .target(
            name: "Session",
            dependencies: ["Puzzle", "Toy", "Motion"],
            swiftSettings: [.strictMemorySafety()]
        ),
        .testTarget(name: "PuzzleTests", dependencies: ["Puzzle"]),
        .testTarget(name: "GeometryTests", dependencies: ["Geometry"]),
        .testTarget(name: "MotionTests", dependencies: ["Motion", "Toy", "Puzzle", "Geometry"]),
        .testTarget(name: "SessionTests", dependencies: ["Session", "Motion", "Puzzle", "Toy"]),
        // Rules the app's own code must keep, read from its sources in this repository.
        .testTarget(name: "AppRulesTests"),
    ]
)
