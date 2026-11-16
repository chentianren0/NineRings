import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// A tool for the pair move (``PairMoveOff``): sweeps it for a few rings and states and prints the room, the
/// tightest place in each tenth of the path and the first relation that fails. Run with `NINE_RINGS_PAIR=1`,
/// optimized. `NINE_RINGS_KEYS` replaces some curves' keys, written as the tuners print them;
/// `NINE_RINGS_CASES` lists cases as `ring:state` with the state written ring 1 first, such as `3:011111111`;
/// `NINE_RINGS_DETAIL` adds the tightest place round the moving ring in each hundredth of the drop.
@Suite struct PairMoveTrialTests {
    static let environment = ProcessInfo.processInfo.environment

    /// A state written ring 1 first, `1` for on.
    static func state(_ text: some StringProtocol) -> PuzzleState {
        var bits: UInt16 = 0
        for (index, character) in text.enumerated() where character == "1" { bits |= 1 << index }
        return PuzzleState(bits: bits)
    }

    @Test(.enabled(if: environment["NINE_RINGS_PAIR"] != nil))
    func sweepThePairMove() throws {
        var keys = PairMoveOff.keys
        if let text = Self.environment["NINE_RINGS_KEYS"] {
            keys = try #require(KeyedMove.parse(text, into: keys))
        }
        let cases = (Self.environment["NINE_RINGS_CASES"] ?? "2:111111111,3:011111111").split(separator: ",").map { item in
            let parts = item.split(separator: ":")
            return (Int(parts[0])!, Self.state(parts[1]))
        }
        let samples = Int(Self.environment["NINE_RINGS_SAMPLES"] ?? "1000") ?? 1000
        for (ring, from) in cases {
            let move = try #require(Move(ring: ring, from: from))
            let paced = PairMoveOff.Paced(PairMoveOff(ring: ring, from: from, keys: keys))
            let sweep = Sweep(move, samples: samples, pose: paced.pose(atProgress:))
            let label = "ring \(ring) from \(from)"
            let records = Sweep.inParallel(sweep.poses.count) { index -> Gap in
                Gaps.smallest(in: sweep.poses[index].shapes.filter { $0.name != .bar })!
            }
            let worst = records.indices.min { records[$0].distance < records[$1].distance }!
            func parameter(_ index: Int) -> Double { paced.pacing.pathParameter(atProgress: sweep.progress[index]) }
            print("\(label): smallest gap \(sweep.smallestGap.gap) at progress \(sweep.smallestGap.progress)")
            print("\(label): leaving out the bar \(records[worst]) at path \(String(format: "%.4f", parameter(worst)))")
            print("\(label): largest step \(sweep.largestStep)")
            for tenth in 0..<10 {
                let indices = records.indices.filter { parameter($0) >= Double(tenth) / 10 && parameter($0) < Double(tenth + 1) / 10 }
                guard let index = indices.min(by: { records[$0].distance < records[$1].distance }) else { continue }
                print("\(label):   path \(tenth)/10: \(records[index]) at \(String(format: "%.4f", parameter(index)))")
            }
            if Self.environment["NINE_RINGS_DETAIL"] != nil {
                let moving: Set<PartName> = [.ring(ring), .eye(ring), .shaft(ring), .bead(ring)]
                let detail = Sweep.inParallel(sweep.poses.count) { index -> Gap in
                    Gaps.smallest(in: sweep.poses[index].shapes.filter { $0.name != .bar }, reach: 30, involving: moving)!
                }
                for step in 40..<84 {
                    let indices = records.indices.filter { parameter($0) >= Double(step) / 100 && parameter($0) < Double(step + 1) / 100 }
                    guard let index = indices.min(by: { detail[$0].distance < detail[$1].distance }) else { continue }
                    print("\(label):     path \(step)/100: \(detail[index])")
                }
            }
            if let failure = sweep.firstRelationFailure {
                let index = sweep.progress.firstIndex(of: failure.progress)!
                print("\(label): at path \(String(format: "%.4f", parameter(index))): \(failure.failures.joined(separator: "; "))")
            } else {
                print("\(label): every relation holds")
            }
        }
    }
}
