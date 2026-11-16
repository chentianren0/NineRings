import Foundation
@testable import Motion
import Testing

/// The new tuner on the two written moves, to prove it against today's tuners. Run optimized with
/// `NINE_RINGS_SEARCH=1` (ring 1's drop from the hand guess `TuneTests` starts from) or `NINE_RINGS_SEARCH=2`
/// (ring 2's move from its keys rounded as a first guess would be). `NINE_RINGS_SECONDS` sets the time budget,
/// `NINE_RINGS_SEED` the seed, `NINE_RINGS_FROM` keys to start from instead, and `NINE_RINGS_SHAKE=scale` shakes
/// the written keys by that many steps to make the start. Each run ends with the checker's full tests of the
/// path it found, and prints its keys.
@Suite struct RingSearchTests {
    static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["NINE_RINGS_SEARCH"] != nil))
    func search() {
        let ring = Int(Self.environment["NINE_RINGS_SEARCH"]!) ?? 1
        let move = ring == 1 ? KeyedMove.ringOne : KeyedMove.ringTwo
        let written = ring == 1 ? KeyedMove.ringOneWritten : RingTwoOff.keys
        let seed = Tuner.seed
        var start = ring == 1 ? KeyedMove.ringOneHandGuess : KeyedMove.ringTwoRounded
        if let scale = Self.environment["NINE_RINGS_SHAKE"].flatMap(Double.init) {
            start = move.shaken(written, scale: scale, seed: seed)
        }
        if let text = Self.environment["NINE_RINGS_FROM"], let parsed = KeyedMove.parse(text, into: written) { start = parsed }
        let seconds = Double(Self.environment["NINE_RINGS_SECONDS"] ?? "120") ?? 120
        let target = Double(Self.environment["NINE_RINGS_TARGET"] ?? "") ?? .infinity
        print("ring \(ring): \(move.dimension) free numbers; written path: \(move.score(written, samples: 480, detail: true))")
        print("start keys: '\(move.text(start))'")
        let result = Tuner.run(move, from: start, seconds: seconds, seed: seed, stopAt: target)
        print("NINE_RINGS_FROM='\(move.text(result.keys))'")
        print(move.swift(result.keys))
        let check = FullCheck.run(move.path(result.keys), mayBeOff: move.room.mayBeOff)
        print(String(format: "full check after %.1f s: ", result.seconds) + "\(check)")
    }
}
