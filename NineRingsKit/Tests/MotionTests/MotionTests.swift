import Foundation
import Testing

/// Every motion test, nested here so that one condition covers them all: they run only in an optimized build.
///
/// The motion tests sample whole moves thousands of times. In a release build they take about nine minutes on GitHub;
/// without optimization they take far longer than half an hour. So a plain `swift test` reports each of them as
/// skipped, with the command that runs them, and GitHub runs them all in a release build.
///
/// Each suite of this target is declared in an `extension MotionTests`, and `everyMotionTestIsInsideMotionTests`
/// fails when one is not.
@Suite(.enabled(if: builtWithOptimization, """
    the motion tests need an optimized build: \
    swift test --package-path NineRingsKit -c release -Xswiftc -enable-testing --filter MotionTests
    """))
enum MotionTests {}

/// Whether this target was built with optimization: SwiftPM defines `DEBUG` only in a debug build.
private let builtWithOptimization: Bool = {
    #if DEBUG
    false
    #else
    true
    #endif
}()

/// Every suite and test of this target lies inside `MotionTests`, so that none runs in a debug build, where one motion
/// test can take half an hour. This test is the one left outside, and runs in every build.
///
/// It reads the target's sources by their indentation: a line that declares a suite or a test must be indented, under
/// a top-level line that begins `extension MotionTests`.
@Test func everyMotionTestIsInsideMotionTests() throws {
    let here = URL(filePath: #filePath).standardizedFileURL
    let folder = here.deletingLastPathComponent()
    let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        .map(\.standardizedFileURL)
        .filter { $0.pathExtension == "swift" && $0 != here }
    #expect(files.count > 20, "the target's sources are where this test looks for them")
    var outside: [String] = []
    for file in files {
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        var topLevel = ""
        for (index, line) in lines.enumerated() {
            let code = String(line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)[0])
            guard let first = code.first else { continue }
            if !first.isWhitespace, first != "}", first != "#" { topLevel = code }
            if code.contains(/@(Suite|Test)\b/), !first.isWhitespace || !topLevel.hasPrefix("extension MotionTests") {
                outside.append("\(file.path.dropFirst(folder.path.count + 1)):\(index + 1)")
            }
        }
    }
    #expect(outside.isEmpty, "declared outside `extension MotionTests`, so it would run in a debug build: \(outside)")
}
