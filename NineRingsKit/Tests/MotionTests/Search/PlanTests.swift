import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

/// Finds a move again from where it begins and ends: the path planner finds a way, the fit writes it as keys, and
/// the tuner widens its room. Run optimized with `NINE_RINGS_PLAN=1` for ring 1's drop, from its two ends only.
/// `NINE_RINGS_SECONDS` is the tuner's time, `NINE_RINGS_SEED` the seed.
@Suite struct PlanTests {
    static let environment = ProcessInfo.processInfo.environment

    /// Ring 1 standing on its eye along the sword, then tipped, tilted and swung, its eye at a height: the drop's
    /// numbers, with every other ring on and the sword at home.
    static let ringOneDrop = ConfigSpace(
        names: ["tip", "tilt", "swing", "eye"],
        scales: [10, 10, 10, 1],
        lower: [-30, -90, -90, Layout.eyeHeightHanging],
        upper: [180, 180, 90, Layout.eyeHeightOn],
        room: FastRoom(moving: [1], swordMoves: false, mayBeOff: [1]),
        pose: { q in
            let degree = Double.pi / 180
            let turns = RingTurns(
                lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2),
                tip: Curve(constant: q[0] * degree), tilt: Curve(constant: q[1] * degree),
                swing: Curve(constant: q[2] * degree), eyeHeight: Curve(constant: q[3])
            )
            var rings = PuzzleState.rings.map(RestPoses.on)
            rings[0] = turns.held(1, at: 0)
            return RestPoses.pose(holding: rings, swordSlide: Layout.swordHome)
        }
    )

    /// A move for the tuner whose curves have the keys `keys` has, every key free but the ends' places and values.
    static func fitted(_ keys: KeyedMove.Keys, space: ConfigSpace, span: ClosedRange<Double>, base: KeyedMove) -> KeyedMove {
        var move = base
        move.span = span
        move.bounds = Dictionary(uniqueKeysWithValues: space.names.indices.map { (space.names[$0], space.lower[$0]...space.upper[$0]) })
        move.channels = space.names.map { name in
            let count = keys[name]!.count
            let interior = (0..<count).map { $0 != 0 && $0 != count - 1 }
            let lengths = name.hasSuffix("eye") || name == "sword"
            return KeyedMove.Channel(name: name, freeProgress: interior, freeValue: interior, valueStep: lengths ? 0.8 : 8)
        }
        return move
    }

    @Test(.enabled(if: environment["NINE_RINGS_PLAN"] == "1"))
    func planRingOneDrop() {
        let clock = DispatchTime.now().uptimeNanoseconds
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - clock) / 1e9 }
        let seed = Tuner.seed
        let space = Self.ringOneDrop
        let start = [0, 0, 0, Layout.eyeHeightOn]
        let goal = [180 - RingTurns.leanHangingDegrees, 90, 0, Layout.eyeHeightHanging]
        guard let plan = Planner.plan(space, from: start, to: goal, needs: [0.4, 0.3, 0.2, 0.1, 0], seed: seed) else {
            print("no path found")
            return
        }
        for q in plan.path { print(q.map { String(format: "%8.2f", $0) }.joined() + String(format: "   room %.3f", space.clearance(q))) }
        let span = 0.56...1.0
        let keys = CurveFit.keys(plan.path, space: space, span: span)
        var full = KeyedMove.ringOneWritten
        for name in space.names { full[name] = keys[name] }
        let move = Self.fitted(full, space: space, span: span, base: .ringOne)
        print(String(format: "%6.1f s  fitted %d keys: ", elapsed(), keys.values.reduce(0) { $0 + $1.count }) + "\(move.score(full, samples: 480, detail: true))")
        print(move.text(full))
        let seconds = Double(Self.environment["NINE_RINGS_SECONDS"] ?? "30") ?? 30
        let result = Tuner.run(move, from: full, seconds: seconds, seed: seed)
        print(String(format: "%6.1f s in all", elapsed()))
        print(move.swift(result.keys))
        print("full check: \(FullCheck.run(move.path(result.keys), mayBeOff: [1]))")
    }
}
