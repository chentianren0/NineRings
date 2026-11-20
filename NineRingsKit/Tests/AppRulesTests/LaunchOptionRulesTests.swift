import Foundation
import Testing

/// Which builds read the app's own launch options, checked in the app's sources in this repository.
///
/// A build that ships reads none of them. Whatever it is launched with, it starts as the person left it. A launch
/// option that set up the toy in such a build would replace the person's toy and record plays they never played. Only
/// a debug build reads the launch options, and a measuring build reads its own `-measure` (`MeasureScript`). Settings
/// given as `-key value` are the system's, not the app's options.
@Suite struct LaunchOptionRulesTests {
    /// The repository's root: this file is in NineRingsKit/Tests/AppRulesTests.
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// How the app reads its launch arguments.
    private static let reads = ["ProcessInfo.processInfo.arguments", "CommandLine.arguments"]

    /// The conditions under which reading them is allowed: a debug build and a measuring build.
    private static let builds = ["DEBUG", "MEASURE"]

    @Test func onlyDebugAndMeasuringBuildsReadTheLaunchArguments() throws {
        let app = Self.root.appending(path: "NineRings")
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty, "the app's sources are where this test looks for them")
        var reading = 0
        var unguarded: [String] = []
        for url in files {
            // The open conditional blocks: each one's condition, and whether its #else branch is the one open.
            var open: [(condition: String, isElse: Bool)] = []
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let code = String(line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                let directive = code.trimmingCharacters(in: .whitespaces)
                if directive.hasPrefix("#if ") {
                    open.append((String(directive.dropFirst(4)), false))
                } else if directive.hasPrefix("#elseif "), !open.isEmpty {
                    open[open.count - 1] = (String(directive.dropFirst(8)), false)
                } else if directive.hasPrefix("#else"), !open.isEmpty {
                    open[open.count - 1].isElse = true
                } else if directive.hasPrefix("#endif"), !open.isEmpty {
                    open.removeLast()
                } else if Self.reads.contains(where: code.contains) {
                    reading += 1
                    let isGuarded = open.contains { block in
                        !block.isElse && Self.builds.contains { build in
                            block.condition.contains(build) && !block.condition.contains("!\(build)")
                        }
                    }
                    if !isGuarded { unguarded.append("\(url.lastPathComponent):\(index + 1)") }
                }
            }
        }
        #expect(reading > 0, "the app reads its launch arguments somewhere, or this test looks for the wrong thing")
        #expect(unguarded.isEmpty, "a build that ships reads the launch arguments at \(unguarded)")
    }
}
