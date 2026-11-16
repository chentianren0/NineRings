import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// The pieces the step-aside scans share: the ring in front of ring `n` turned about its eye, ring `n` lifting
/// over the tip, the relations among rings 1 to `n`, and the gaps.
enum StepAsideScanTests {
    static func turns(_ ring: Int, lid: Double, tilt: Double, swing: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: lid * .pi / 180), turn: Curve(constant: 0), tip: Curve(constant: 0),
            tilt: Curve(constant: tilt * .pi / 180), swing: Curve(constant: swing * .pi / 180),
            eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(ring, at: 0)
    }

    /// Ring `n` tipped toward the tip, as ring 3 lifts in its move.
    static func lifting(_ n: Int, tip: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2), tip: Curve(constant: tip * .pi / 180),
            tilt: Curve(constant: .pi / 2), swing: Curve(constant: 0), eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(n, at: 0)
    }

    static func pose(_ held: [Int: HeldRing], sword: Double, raise: Double) -> ToyPose {
        let rings = PuzzleState.rings.map { held[$0] ?? RestPoses.on($0) }
        return RestPoses.pose(holding: rings, swordSlide: sword, barRaise: raise)
    }

    /// The relations that must hold among rings 1 to `n` and their rods, as one sentence each when they fail.
    static func failures(_ pose: ToyPose, n: Int, rods: Bool) -> [String] {
        var failures: [String] = []
        let circles = (1...9).map { pose.ring($0).circle }
        for ring in 1...min(n + 1, 9) {
            let (near, far) = Relations.swordCrossings(of: ring, in: pose)
            if near.count % 2 != far.count % 2 { failures.append("ring \(ring) on one rail") }
            for other in (ring + 1)..<10 where ring <= n && Relations.areLinked(circles[ring - 1], circles[other - 1]) {
                failures.append("rings \(ring) and \(other) linked")
            }
        }
        guard rods else { return failures }
        for rod in 1..<n {
            let thread = Relations.threadPath(of: pose.rod(rod))
            for ring in 1...min(n + 1, 9) where ring != rod {
                let through = Relations.crossings(of: thread, through: circles[ring - 1]).count % 2 == 1
                if through != (ring == rod + 1) { failures.append("rod \(rod) and ring \(ring)") }
            }
            for ring in 1...min(n + 1, 9) where ring != rod && Relations.areLinked(pose.rod(rod).eye, circles[ring - 1]) {
                failures.append("eye \(rod) linked with ring \(ring)")
            }
            if (Relations.holeRoom(rod, in: pose) ?? -1) < 0 { failures.append("rod \(rod) does not fit its hole") }
        }
        // Rod n-1 through ring n is the relation the lift keeps.
        if Relations.crossings(of: Relations.threadPath(of: pose.rod(n - 1)), through: circles[n - 1]).count % 2 != 1 {
            failures.append("rod \(n - 1) out of ring \(n)")
        }
        return failures
    }

    /// The smallest gap between a shape in `first` and any other shape not joined to it.
    static func gap(_ shapes: [Shape], _ first: Set<PartName>) -> (Double, String) {
        var smallest = (Double.infinity, "")
        for (index, a) in shapes.enumerated() {
            for b in shapes[(index + 1)...] where (first.contains(a.name) || first.contains(b.name)) && !a.name.isJoined(to: b.name) {
                if simd_distance(a.boundCenter, b.boundCenter) > a.boundRadius + b.boundRadius + 1 { continue }
                let (p, q) = Gaps.nearest(a.core, b.core)
                let distance = simd_distance(p, q) - a.radius - b.radius
                if distance < smallest.0 { smallest = (distance, "\(a.name) and \(b.name)") }
            }
        }
        return smallest
    }

    struct Lift { var tip: Double; var sword: Double }

    static func lift(_ n: Int) -> [Lift] {
        let shift = 15 * Double(n - 3)
        return stride(from: 137.0, through: 100, by: -2).map { Lift(tip: $0, sword: shift + 40 + min(1, (137 - $0) / 36) * 2.4) }
            + [Lift(tip: 100, sword: shift + 42.4)]
    }


}
