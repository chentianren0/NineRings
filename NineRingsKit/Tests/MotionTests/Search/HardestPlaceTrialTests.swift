import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// A trial of the tools at the hardest place known: ring 2 stepping aside, carrying ring 1 that hangs from it,
/// while ring 3 lifts over the tip, from ring 1 off and every other ring on. Run optimized with
/// `NINE_RINGS_TRIAL=1`; `NINE_RINGS_BAR_RAISE` holds the bar that many millimetres higher, as an experiment in
/// this test only (no committed rule changes).
///
/// First the tuner looks for the pose with the most room in which ring 3 is off the rails over the tip; then the
/// planner looks for a way to it from the rest pose.
@Suite struct HardestPlaceTrialTests {
    static let environment = ProcessInfo.processInfo.environment

    static func space(raise: Double) -> ConfigSpace {
        let bar = PartPose(position: Layout.bar.position + SIMD3(0, raise, 0), orientation: Layout.bar.orientation)
        let ringTwoAtRest = RestPoses.on(2), ringOneAtRest = RestPoses.hanging(1)
        return ConfigSpace(
            names: ["ring2.lid", "ring2.tilt", "ring2.swing", "ring3.tip", "sword"],
            scales: [10, 10, 10, 10, 2],
            lower: [20, -90, -90, 80, 0],
            upper: [140, 90, 90, 140, 46],
            room: FastRoom(moving: [1, 2, 3], swordMoves: true, mayBeOff: [1, 2, 3], bar: bar),
            pose: { q in
                let degree = Double.pi / 180
                let two = RingTurns(
                    lid: Curve(constant: q[0] * degree), turn: Curve(constant: 0), tip: Curve(constant: 0),
                    tilt: Curve(constant: q[1] * degree), swing: Curve(constant: q[2] * degree),
                    eyeHeight: Curve(constant: Layout.eyeHeightOn)
                ).held(2, at: 0)
                let three = RingTurns(
                    lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2), tip: Curve(constant: q[3] * degree),
                    tilt: Curve(constant: .pi / 2), swing: Curve(constant: 0), eyeHeight: Curve(constant: Layout.eyeHeightOn)
                ).held(3, at: 0)
                // Ring 1 is carried with ring 2 as one piece, as `HangingChain` on the ring 3 branch carries it.
                let before = ringTwoAtRest.ringPose, after = two.ringPose
                let turn = after.orientation * before.orientation.inverse
                let one = HeldRing(
                    eye: after.position + turn.act(ringOneAtRest.eye - before.position),
                    towardCenter: turn.act(ringOneAtRest.towardCenter), alongWire: turn.act(ringOneAtRest.alongWire)
                )
                var rings = PuzzleState.rings.map(RestPoses.on)
                (rings[0], rings[1], rings[2]) = (one, two, three)
                return ToyPose(
                    rings: rings.map(\.ringPose),
                    rods: zip(PuzzleState.rings, rings).map { ring, held in
                        held.rodPose(hole: bar.worldPoint(SIMD3(Dimensions.Bar.holeX(ring), 0, 0)))
                    },
                    bar: bar, swordSlide: q[4]
                )
            }
        )
    }

    @Test(.enabled(if: environment["NINE_RINGS_TRIAL"] != nil))
    func stepAsideWhileRingThreeLifts() {
        let raise = Double(Self.environment["NINE_RINGS_BAR_RAISE"] ?? "0") ?? 0
        let space = Self.space(raise: raise)
        let start = [RingTurns.leanOnDegrees, 0, 0, 180 - RingTurns.leanOnDegrees, 0]
        print(String(format: "bar raised %.1f mm; room at rest %.3f", raise, space.clearance(start)))
        print("\(space.room.room(space.pose(start)))")

        // The pose with the most room with ring 3 off the rails: CMA-ES over the five numbers, from several starts.
        let clock = DispatchTime.now().uptimeNanoseconds
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - clock) / 1e9 }
        @Sendable func score(_ q: [Double]) -> Double {
            let clamped = q.indices.map { min(max(q[$0], space.lower[$0]), space.upper[$0]) }
            let pose = space.pose(clamped)
            let off = Relations.isRoundTheRails(3, in: pose) ? -1.0 : 0
            return space.room.room(pose).value + off
        }
        var best: (q: [Double], value: Double) = (start, -.infinity)
        var random = SeededRandom(seed: Tuner.seed)
        let starts: [[Double]] = [[90, 0, 30, 95, 43], [90, 0, -30, 95, 43], [100, 0, 45, 95, 43], [100, 0, -45, 95, 43], [80, 20, 0, 100, 42], [110, -20, 20, 95, 44]]
        for initial in starts {
            var strategy = CMAES(mean: initial.indices.map { initial[$0] / space.scales[$0] }, sigma: 0.5, population: 20)
            for _ in 0..<150 {
                let points = strategy.ask(using: &random)
                let values = Sweep.inParallel(points.count) { index in score(points[index].indices.map { points[index][$0] * space.scales[$0] }) }
                strategy.tell(points, values)
                if let top = values.indices.max(by: { values[$0] < values[$1] }), values[top] > best.value {
                    best = (points[top].indices.map { points[top][$0] * space.scales[$0] }, values[top])
                }
                if strategy.spread < 0.005 { break }
            }
            print(String(format: "%6.1f s  from %@: best so far %.3f at %@", elapsed(), "\(initial)", best.value,
                         best.q.map { String(format: "%.2f", $0) }.joined(separator: ", ")))
        }
        let goal = best.q.indices.map { min(max(best.q[$0], space.lower[$0]), space.upper[$0]) }
        print("best pose: \(space.room.room(space.pose(goal)))")
        guard best.value > 0 else { return }

        // A way to it from the rest pose.
        let needs = [0.4, 0.3, 0.25, 0.2, 0.1, 0.0].filter { $0 < min(best.value, space.clearance(start)) }
        if let plan = Planner.plan(space, from: start, to: goal, needs: needs, step: 0.5, nodes: 40000, seed: Tuner.seed) {
            for q in plan.path { print(q.map { String(format: "%8.2f", $0) }.joined() + String(format: "   room %.3f", space.clearance(q))) }
            print(String(format: "%6.1f s in all", elapsed()))
        }
    }
}
