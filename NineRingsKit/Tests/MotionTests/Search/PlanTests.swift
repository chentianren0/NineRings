import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

/// Finds a move again from where it begins and ends: the path planner finds a way, the fit writes it as keys, and
/// the tuner widens its room. Run optimized with `NINE_RINGS_PLAN=1` for ring 1's drop, from its two ends only, or
/// `NINE_RINGS_PLAN=2` for ring 2's whole move, from the poses its stages begin and end at.
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

    /// Ring 2's move: ring 1's lid and turn, ring 2's tip, tilt, swing and eye height, and the sword's slide.
    static let ringTwoMove = ConfigSpace(
        names: RingTwoTuneTests.names,
        scales: [10, 10, 10, 10, 10, 1, 2],
        lower: [RingTurns.leanOnDegrees, 0, 80, 30, -60, Layout.eyeHeightHanging, 0],
        upper: [180, 90, 140, 120, 60, Layout.eyeHeightOn, 29.5],
        room: FastRoom(moving: [1, 2], swordMoves: true, mayBeOff: [1, 2]),
        pose: { q in
            let degree = Double.pi / 180
            let one = RingTurns(
                lid: Curve(constant: q[0] * degree), turn: Curve(constant: q[1] * degree), tip: Curve(constant: 0),
                tilt: Curve(constant: 0), swing: Curve(constant: 0), eyeHeight: Curve(constant: Layout.eyeHeightOn)
            )
            let two = RingTurns(
                lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2), tip: Curve(constant: q[2] * degree),
                tilt: Curve(constant: q[3] * degree), swing: Curve(constant: q[4] * degree), eyeHeight: Curve(constant: q[5])
            )
            var rings = PuzzleState.rings.map(RestPoses.on)
            rings[0] = one.held(1, at: 0)
            rings[1] = two.held(2, at: 0)
            return RestPoses.pose(holding: rings, swordSlide: q[6])
        },
        parts: [1, 1, 2, 2, 2, 2, 0]
    )

    @Test(.enabled(if: environment["NINE_RINGS_PLAN"] == "2"))
    func planRingTwoMove() {
        let clock = DispatchTime.now().uptimeNanoseconds
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - clock) / 1e9 }
        let seed = Tuner.seed
        let space = Self.ringTwoMove
        let leanOn = RingTurns.leanOnDegrees, tipOn = 180 - RingTurns.leanOnDegrees, tipHanging = 180 - RingTurns.leanHangingDegrees
        // The poses the stages begin and end at, as the README describes them, in round numbers: ring 1 steps aside
        // (standing on its eye along the sword, the sword drawn back 20 mm); ring 2 lies nearly flat over the tip,
        // the tip just short of rod 1; ring 2 hangs, the sword 15 mm back, one hole's pitch, so that ring 2 has the
        // slot ring 1 had; ring 1 back on.
        let waypoints: [[Double]] = [
            [leanOn, 0, tipOn, 90, 0, Layout.eyeHeightOn, 0],
            [180, 90, tipOn, 90, 0, Layout.eyeHeightOn, 20],
            [180, 90, 94, 90, 0, Layout.eyeHeightOn, 28],
            [180, 90, tipHanging, 90, 0, Layout.eyeHeightHanging, 15],
            [leanOn, 0, tipHanging, 90, 0, Layout.eyeHeightHanging, 0],
        ]
        let spans: [ClosedRange<Double>] = [0...0.22, 0.22...0.40, 0.40...0.82, 0.82...1]
        var legs: [([[Double]], ClosedRange<Double>)] = []
        for index in 0..<4 {
            print("leg \(index + 1)")
            guard let plan = Planner.plan(space, from: waypoints[index], to: waypoints[index + 1], needs: [0.4, 0.3, 0.2, 0.1, 0],
                                          seconds: 120, seed: seed) else {
                print("no path for leg \(index + 1)")
                return
            }
            for q in plan.path { print(q.map { String(format: "%8.2f", $0) }.joined() + String(format: "   room %.3f", space.clearance(q))) }
            legs.append((plan.path, spans[index]))
        }
        let tolerance = Double(Self.environment["NINE_RINGS_FIT"] ?? "0.3") ?? 0.3
        let keys = CurveFit.keys(legs: legs, space: space, tolerance: tolerance)
        let move = Self.fitted(keys, space: space, span: 0...1, base: .ringTwo)
        print(String(format: "%6.1f s  fitted %d keys: ", elapsed(), keys.values.reduce(0) { $0 + $1.count }) + "\(move.score(keys, samples: 480, detail: true))")
        print(move.text(keys))
        let seconds = Double(Self.environment["NINE_RINGS_SECONDS"] ?? "120") ?? 120
        let result = Tuner.run(move, from: keys, seconds: seconds, seed: seed)
        print(String(format: "%6.1f s in all", elapsed()))
        print(move.swift(result.keys))
        print("full check: \(FullCheck.run(move.path(result.keys), mayBeOff: [1, 2]))")
    }
}
