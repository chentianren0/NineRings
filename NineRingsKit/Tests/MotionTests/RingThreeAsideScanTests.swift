import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Scans the pose ring 2 could step aside to, with ring 1 carried along, for room while ring 3 lifts over the
/// tip. Run with `NINE_RINGS_ASIDE=1`, optimized.
@Suite struct RingThreeAsideScanTests {
    static func aside(lid: Double, tilt: Double, swing: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: lid * .pi / 180), turn: Curve(constant: 0), tip: Curve(constant: 0),
            tilt: Curve(constant: tilt * .pi / 180), swing: Curve(constant: swing * .pi / 180),
            eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(2, at: 0)
    }

    /// Ring 3 lifting: tipped from on toward `droop` above flat, with the sword at `sword`.
    static func ringThree(tip: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2), tip: Curve(constant: tip * .pi / 180),
            tilt: Curve(constant: .pi / 2), swing: Curve(constant: 0), eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(3, at: 0)
    }

    static let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2)]

    static func room(_ two: HeldRing, tips: [Double], swords: [Double]) -> (Double, String) {
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = RingThreeOff.ringOneHanging.chain(carriedBy: two)[0]
        rings[1] = two
        var worst = (10.0, "")
        for (tip, sword) in zip(tips, swords) {
            rings[2] = ringThree(tip: tip)
            let pose = RestPoses.pose(holding: rings, swordSlide: sword)
            let failures = Relations.failures(in: pose, mayBeOff: [1, 2, 3])
            let shapes = pose.shapes
            let gap = Gaps.smallest(in: shapes.filter { $0.name != .bar }, involving: moving)!
            let bead = Gaps.smallest(in: shapes.filter { $0.name == .bar || $0.name == .bead(1) })!.distance - Layout.restingGap
            let hole = Relations.holeRoom(1, in: pose) ?? -1
            var room = min(gap.distance, bead * 4 + 0.2, hole * 4 + 0.2)
            if !failures.isEmpty { room = min(room, 0) - Double(failures.count) }
            if tip == tips.last, Relations.isRoundTheRails(3, in: pose) { room = min(room, 0) - 1 }
            if room < worst.0 { worst = (room, "tip \(tip) sword \(sword): \(gap) bead \(bead) hole \(hole) \(failures)") }
        }
        return worst
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_ASIDE"] != nil))
    func scan() {
        let lowest = Double(ProcessInfo.processInfo.environment["NINE_RINGS_TIP"] ?? "100")!
        let tips = stride(from: 137.0, through: lowest, by: -1.5).map { $0 } + [lowest]
        let swords = tips.map { 40.0 + min(1, (137 - $0) / 36) * 2.4 }
        var combos: [(Double, Double, Double)] = []
        let broad = ProcessInfo.processInfo.environment["NINE_RINGS_BROAD"] != nil
        for lid in broad ? Array(stride(from: 56.0, through: 128.0, by: 4)) : Array(stride(from: 74.0, through: 88.0, by: 1)) {
            for tilt in broad ? Array(stride(from: -60.0, through: 60.0, by: 10)) : Array(stride(from: -12.0, through: 12.0, by: 3)) {
                for swing in broad ? Array(stride(from: -180.0, to: 180.0, by: 10)) : Array(stride(from: -30.0, through: 30.0, by: 5)) { combos.append((lid, tilt, swing)) }
            }
        }
        let all = combos
        let results = Sweep.inParallel(all.count) { index in
            let (lid, tilt, swing) = all[index]
            return Self.room(Self.aside(lid: lid, tilt: tilt, swing: swing), tips: tips, swords: swords)
        }
        let order = results.indices.sorted { results[$0].0 > results[$1].0 }
        for index in order.prefix(40) {
            let (lid, tilt, swing) = combos[index]
            print(String(format: "lid %5.0f tilt %5.0f swing %5.0f room %7.3f  ", lid, tilt, swing, results[index].0) + results[index].1)
        }
    }
}
