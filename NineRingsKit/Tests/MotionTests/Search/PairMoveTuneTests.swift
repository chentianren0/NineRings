import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

/// A tool for the pair move's drop (``PairMoveOff``): tunes the keys of the moving ring's drop, and of its eye's
/// move back, for the most room, with ring 2 coming off every ring on (`KeyedMove.pairDrop`). The drop is the same relative to the sword
/// for every ring, so the keys it finds serve them all; the package's tests judge every ring. Run optimized with
/// `NINE_RINGS_PAIR_TUNE=1`; `NINE_RINGS_SECONDS` is the budget.
@Suite struct PairMoveTuneTests {
    static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["NINE_RINGS_PAIR_TUNE"] != nil))
    func tuneTheDrop() {
        let base = PairMoveOff.keys
        let move = KeyedMove.pairDrop
        let seconds = Double(Self.environment["NINE_RINGS_SECONDS"] ?? "120") ?? 120
        let target = Double(Self.environment["NINE_RINGS_TARGET"] ?? "0.45") ?? 0.45
        let result = Tuner.run(move, from: base, seconds: seconds, samples: 150, seed: Tuner.seed, stopAt: target)
        print(move.swift(result.keys))
        print(move.text(result.keys))
    }
}
