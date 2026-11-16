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
        .testTarget(name: "PuzzleTests", dependencies: ["Puzzle"]),
        .testTarget(name: "GeometryTests", dependencies: ["Geometry"]),
        .testTarget(name: "MotionTests", dependencies: ["Motion", "Toy", "Puzzle", "Geometry"]),
    ]
)
