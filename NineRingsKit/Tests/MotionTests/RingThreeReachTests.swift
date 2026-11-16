import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// A necessary condition for ring 3's move, whatever ring 1 does: while ring 3 lifts over the tip, ring 2 must be
/// out of its way, and rod 1 must still pass through ring 2 and not through ring 3, with its bead under the bar.
/// Scans ring 2's pose and rod 1's eye, leaving ring 1 itself out. Run with `NINE_RINGS_REACH=1`, optimized.
@Suite struct RingThreeReachTests {
    static func turns(lid: Double, tilt: Double, swing: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: lid * .pi / 180), turn: Curve(constant: 0), tip: Curve(constant: 0),
            tilt: Curve(constant: tilt * .pi / 180), swing: Curve(constant: swing * .pi / 180),
            eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(2, at: 0)
    }

    static func ringThree(tip: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2), tip: Curve(constant: tip * .pi / 180),
            tilt: Curve(constant: .pi / 2), swing: Curve(constant: 0), eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(3, at: 0)
    }

    /// Ring 3's lift: from on to 10° short of flat, the sword drawn back from 40 to 42.4 mm.
    static let lift: [(tip: Double, sword: Double)] = stride(from: 137.0, through: 100, by: -1.5).map { tip in
        (tip, 40 + min(1, (137 - tip) / 36) * 2.4)
    } + [(100, 42.4)]

    static func pose(two: HeldRing, three: HeldRing, one: HeldRing, sword: Double) -> ToyPose {
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = one
        rings[1] = two
        rings[2] = three
        return RestPoses.pose(holding: rings, swordSlide: sword)
    }

    /// The smallest gap between shapes of the two named groups.
    static func gap(_ shapes: [Shape], _ first: Set<PartName>, _ second: Set<PartName>) -> Double {
        var smallest = Double.infinity
        for a in shapes where first.contains(a.name) {
            for b in shapes where second.contains(b.name) && !a.name.isJoined(to: b.name) {
                if simd_distance(a.boundCenter, b.boundCenter) > a.boundRadius + b.boundRadius + 3 { continue }
                let (p, q) = Gaps.nearest(a.core, b.core)
                smallest = min(smallest, simd_distance(p, q) - a.radius - b.radius)
            }
        }
        return smallest
    }

    /// How much room ring 2 in this pose leaves ring 3's lift, with ring 1 and rod 1 left where they rest.
    static func ringTwoRoom(_ two: HeldRing) -> Double {
        var room = Double.infinity
        let ringTwo: Set<PartName> = [.ring(2), .eye(2), .shaft(2)]
        let others: Set<PartName> = [.ring(3), .eye(3), .shaft(3), .sword]
        for (index, step) in lift.enumerated() {
            let pose = pose(two: two, three: ringThree(tip: step.tip), one: RestPoses.hanging(1), sword: step.sword)
            let three = pose.ring(3).circle
            if Relations.areLinked(pose.ring(2).circle, three) || Relations.isRoundTheRails(2, in: pose) { return -1 }
            if Relations.crossings(of: Relations.threadPath(of: pose.rod(2)), through: three).count % 2 != 1 { return -1 }
            if index == lift.count - 1, Relations.isRoundTheRails(3, in: pose) { return -1 }
            room = min(room, gap(pose.shapes, ringTwo, others))
        }
        return room
    }

    /// The most room rod 1 can have with its eye anywhere it reaches, ring 2 in this pose; nil when nowhere works.
    static func rodOneRoom(_ two: HeldRing) -> (room: Double, eye: SIMD3<Double>)? {
        let hole = Layout.hole(1)
        let reach = -Dimensions.Rod.beadCenterY - Dimensions.Rod.beadRadius - Dimensions.Bar.thickness / 2 - 0.2
        var best: (room: Double, eye: SIMD3<Double>)?
        // The side of ring 2's plane that ring 1 rests on, carried round with ring 2.
        let rest = RestPoses.on(2).ringPose, now = two.ringPose
        let restNormal = rest.worldDirection(SIMD3(0, 0, 1))
        let restSide = simd_dot(RestPoses.hanging(1).ringPose.position - rest.position, restNormal) > 0 ? restNormal : -restNormal
        let front = (now.orientation * rest.orientation.inverse).act(restSide)
        let frontOnly = ProcessInfo.processInfo.environment["NINE_RINGS_FRONT"] != nil
        let rodOne: Set<PartName> = [.eye(1), .shaft(1), .bead(1)]
        let others: Set<PartName> = [.ring(2), .eye(2), .shaft(2), .ring(3), .eye(3), .shaft(3), .sword, .bar]
        for x in stride(from: 6.0, through: 62.0, by: 1.5) {
            for z in stride(from: -26.0, through: 26.0, by: 1.5) {
                let flat = simd_length(SIMD2(x - hole.x, z))
                guard flat < reach * sin(36 * Double.pi / 180) else { continue }
                let top = hole.y + (reach * reach - flat * flat).squareRoot()
                for drop in stride(from: 0.0, through: 8.0, by: 0.75) {
                    let eye = SIMD3(x, top - drop, z)
                    if frontOnly, simd_dot(eye - now.position, front) <= 0 { continue }
                    for wire in [SIMD3<Double>(0, 0, 1), SIMD3(1, 0, 0)] {
                        let one = HeldRing(eye: eye, towardCenter: SIMD3(0, -1, 0).crossFix(wire), alongWire: wire)
                        var room = Double.infinity
                        for step in [lift[0], lift[lift.count / 2], lift[lift.count - 1]] + lift {
                            let pose = pose(two: two, three: ringThree(tip: step.tip), one: one, sword: step.sword)
                            let thread = Relations.threadPath(of: pose.rod(1))
                            guard Relations.crossings(of: thread, through: pose.ring(2).circle).count % 2 == 1,
                                  Relations.crossings(of: thread, through: pose.ring(3).circle).count % 2 == 0,
                                  !Relations.areLinked(pose.rod(1).eye, pose.ring(2).circle),
                                  !Relations.areLinked(pose.rod(1).eye, pose.ring(3).circle),
                                  let fit = Relations.holeRoom(1, in: pose), fit >= 0
                            else { room = -1; break }
                            room = min(room, gap(pose.shapes, rodOne, others))
                            if room < (best?.room ?? 0) { break }
                        }
                        if room > (best?.room ?? 0) { best = (room, eye) }
                    }
                }
            }
        }
        return best
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_REACH"] != nil))
    func scan() {
        var combos: [(Double, Double, Double)] = []
        for lid in stride(from: 40.0, through: 180.0, by: 5) {
            for tilt in stride(from: -90.0, through: 90.0, by: 10) {
                for swing in stride(from: -180.0, to: 180.0, by: 10) where abs(Self.turns(lid: lid, tilt: tilt, swing: swing).alongWire.y) < 0.9 {
                    combos.append((lid, tilt, swing))
                }
            }
        }
        let all = combos
        let rooms = Sweep.inParallel(all.count) { index in
            let (lid, tilt, swing) = all[index]
            return Self.ringTwoRoom(Self.turns(lid: lid, tilt: tilt, swing: swing))
        }
        let clear = rooms.indices.filter { rooms[$0] >= 0.2 }
        print("ring 2 poses that leave ring 3's lift room: \(clear.count) of \(all.count)")
        let reached = Sweep.inParallel(clear.count) { index -> (Double, SIMD3<Double>)? in
            let (lid, tilt, swing) = all[clear[index]]
            return Self.rodOneRoom(Self.turns(lid: lid, tilt: tilt, swing: swing)).map { ($0.room, $0.eye) }
        }
        let order = clear.indices.sorted { (reached[$0]?.0 ?? -1) > (reached[$1]?.0 ?? -1) }
        print("of those, rod 1 can reach through ring 2 in \(reached.compactMap { $0 }.count)")
        for index in order.prefix(25) {
            let (lid, tilt, swing) = all[clear[index]]
            let text = reached[index].map { String(format: "rod 1 room %.3f, eye 1 at (%.1f, %.1f, %.1f)", $0.0, $0.1.x, $0.1.y, $0.1.z) } ?? "rod 1 cannot reach"
            print(String(format: "lid %4.0f tilt %4.0f swing %5.0f ring 2 room %.3f  ", lid, tilt, swing, rooms[clear[index]]) + text)
        }
        // The nearest misses among the poses ring 3's lift rules out, for the record.
        let misses = rooms.indices.filter { rooms[$0] < 0.2 }.sorted { rooms[$0] > rooms[$1] }
        for index in misses.prefix(8) {
            let (lid, tilt, swing) = all[index]
            print(String(format: "near miss: lid %4.0f tilt %4.0f swing %5.0f ring 2 room %.3f", lid, tilt, swing, rooms[index]))
        }
    }
}

private extension SIMD3 where Scalar == Double {
    /// A unit vector at right angles to `wire`, as near this one as can be.
    func crossFix(_ wire: SIMD3<Double>) -> SIMD3<Double> {
        let v = self - simd_dot(self, wire) * wire
        return simd_normalize(v)
    }
}
