import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

/// A tool for the pair move's drop (``PairMoveOff``): tunes the keys of the moving ring's drop, and of its eye's
/// move back, for the most room, with ring 2 coming off every ring on. The drop is the same relative to the sword
/// for every ring, so the keys it finds serve them all; the package's tests judge every ring. Run optimized with
/// `NINE_RINGS_PAIR_TUNE=1`; `NINE_RINGS_SECONDS` is the budget.
@Suite struct PairMoveTuneTests {
    static let environment = ProcessInfo.processInfo.environment

    /// The curves the search changes, each with the step one unit of the search moves a value.
    static let free: [(name: String, step: Double)] = [
        ("ring.back", 0.4), ("ring.swing", 3), ("ring.tilt", 3), ("ring.tip", 3),
    ]

    static func move(base: KeyedMove.Keys) -> KeyedMove {
        var move = KeyedMove(
            channels: free.map { name, step in
                let count = base[name]!.count
                // Every key inside the drop's span may move; only the values of the keys between a curve's first and
                // last, which hold the two rest poses, may change.
                let progress = base[name]!.map { $0.0 > 0.455 && $0.0 < 0.815 }
                let value = base[name]!.indices.map { index in progress[index] && index != 0 && index != count - 1 }
                return KeyedMove.Channel(name: name, freeProgress: progress, freeValue: value, valueStep: step)
            },
            span: 0.45...0.82,
            room: FastRoom(moving: [2], swordMoves: true, mayBeOff: [1, 2]),
            bounds: ["ring.back": 0...4.5],
            path: { keys in
                let path = PairMoveOff(ring: 2, from: .allOn, keys: keys)
                return { path.pose(at: $0) }
            }
        )
        // Keys well apart, so that no curve changes abruptly: the eye's move back above all.
        move.spacing = 0.035
        return move
    }

    @Test(.enabled(if: environment["NINE_RINGS_PAIR_TUNE"] != nil))
    func tuneTheDrop() {
        let base = PairMoveOff.keys
        let move = Self.move(base: base)
        let seconds = Double(Self.environment["NINE_RINGS_SECONDS"] ?? "120") ?? 120
        let target = Double(Self.environment["NINE_RINGS_TARGET"] ?? "0.45") ?? 0.45
        let result = Tuner.run(move, from: base, seconds: seconds, samples: 150, seed: Tuner.seed, stopAt: target)
        print(move.swift(result.keys))
        print(move.text(result.keys))
    }
}
