import Foundation
import Geometry
import Motion
import Toy
import simd

/// What passes through what, read from a pose.
///
/// Each count is how many times a centreline goes through the flat disc that a ring's centreline spans. Two
/// closed loops are linked when one goes through the other's disc an odd number of times.
enum Relations {
    /// The places where a path of straight pieces goes through the disc of `circle`.
    static func crossings(of path: [Vector], through circle: Circle) -> [Vector] {
        let normal = circle.normal
        var places: [Vector] = []
        for (start, end) in zip(path, path.dropFirst()) {
            let startSide = simd_dot(start - circle.center, normal)
            let endSide = simd_dot(end - circle.center, normal)
            guard (startSide < 0) != (endSide < 0) else { continue }
            let point = start + (end - start) * (startSide / (startSide - endSide))
            if simd_distance(point, circle.center) < circle.radius {
                places.append(point)
            }
        }
        return places
    }

    /// A circle as a closed path of `pieces` straight pieces.
    static func loop(_ circle: Circle, pieces: Int = 360) -> [Vector] {
        (0...pieces).map { circle.point(at: Double($0 % pieces) / Double(pieces)) }
    }

    /// Whether two closed loops are linked.
    static func areLinked(_ first: Circle, _ second: Circle) -> Bool {
        crossings(of: loop(first), through: second).count % 2 == 1
    }

    /// Where each side of the sword goes through ring `number`'s disc, in the sword's own frame.
    static func swordCrossings(of number: Int, in pose: ToyPose) -> (near: [Vector], far: [Vector]) {
        let circle = pose.ring(number).circle
        let offset = pose.swordOffset
        let near = crossings(of: pose.swordCenterline(side: 1), through: circle).map { $0 - offset }
        let far = crossings(of: pose.swordCenterline(side: -1), through: circle).map { $0 - offset }
        return (near, far)
    }

    /// Whether ring `number` goes round both rails: each side of the sword goes through it once.
    static func isRoundTheRails(_ number: Int, in pose: ToyPose) -> Bool {
        let (near, far) = swordCrossings(of: number, in: pose)
        return near.count % 2 == 1 && far.count % 2 == 1
    }

    /// How far from the tip's end, along the sword, the sword may go through a ring that is leaving or joining the
    /// rails.
    static let tipEnd = Dimensions.Sword.railOffset / 2

    /// A ring leaves the rails, or joins them, only over the tip end. Whether a ring goes round the rails can
    /// change only where an end of a side of the sword's centreline passes through the ring's disc, or where the
    /// sword's wire passes through the ring's wire, which the gaps forbid. A side has two ends: the tip's end,
    /// where the two sides meet, and the end of its grip loop, which lies against the side's own wire, so that no
    /// ring can pass over it without its wire meeting the sword's. So between two poses one after the other, a
    /// ring may stop or start going round the rails only if, in the pose where it does go round them, the sword
    /// goes through it nowhere but near the tip's end. Each failure is a sentence.
    static func railChangeFailures(from before: ToyPose, to after: ToyPose) -> [String] {
        var failures: [String] = []
        for ring in 1...9 {
            let wasRound = isRoundTheRails(ring, in: before)
            guard wasRound != isRoundTheRails(ring, in: after) else { continue }
            let (near, far) = swordCrossings(of: ring, in: wasRound ? before : after)
            if (near + far).contains(where: { $0.x >= tipEnd }) {
                failures.append("ring \(ring) \(wasRound ? "leaves" : "joins") the rails away from the tip end")
            }
        }
        return failures
    }

    /// The facts about one pose that must hold at every instant. Each is a sentence when it fails.
    ///
    /// Every ring must go round both rails except those in `mayBeOff`, which may go round both or neither, and those
    /// in `mustStayOff`, which must go round neither: the rings that are off before a move and after it, which have no
    /// part in it.
    static func failures(in pose: ToyPose, mayBeOff: Set<Int> = [1], mustStayOff: Set<Int> = []) -> [String] {
        var failures: [String] = []
        let rings = (1...9).map { pose.ring($0).circle }

        for ring in 1...9 {
            // The sword: round both rails or round neither, never one.
            let (near, far) = swordCrossings(of: ring, in: pose)
            if near.count % 2 != far.count % 2 {
                failures.append("ring \(ring) goes round one rail of the sword but not the other")
            }
            if mustStayOff.contains(ring) {
                if isRoundTheRails(ring, in: pose) { failures.append("ring \(ring) has got onto the rails") }
            } else if !mayBeOff.contains(ring) && !isRoundTheRails(ring, in: pose) {
                failures.append("ring \(ring) has left the rails")
            }

            // Rods through rings: rod k−1 through ring k, and no other.
            // A ring's own rod is linked with it through the eye, which the check of the eyes covers.
            for rod in 1...9 where rod != ring {
                let through = crossings(of: threadPath(of: pose.rod(rod)), through: rings[ring - 1]).count % 2 == 1
                if through != (rod == ring - 1) {
                    failures.append(through ? "rod \(rod) passes through ring \(ring)" : "rod \(rod) has come out of ring \(ring)")
                }
            }
            for rod in 1...9 {
                let eyeLinked = areLinked(pose.rod(rod).eye, rings[ring - 1])
                if eyeLinked != (rod == ring) {
                    failures.append(eyeLinked ? "eye \(rod) is linked with ring \(ring)" : "ring \(ring) has come out of its eye")
                }
            }

            // Rings never linked.
            for other in (ring + 1)..<10 where areLinked(rings[ring - 1], rings[other - 1]) {
                failures.append("rings \(ring) and \(other) are linked")
            }

            failures += rodFailures(ring, in: pose)
        }

        if !isClose(pose.bar, Layout.bar) {
            failures.append("the bar has moved")
        }
        return failures
    }

    /// The path along which a ring is threaded on a rod: from the bead up the shaft to the foot of the eye, then
    /// round one side of the eye to its top. A ring is on the rod when this path goes through it an odd number of
    /// times. Which side of the eye makes no difference, because the eye is a closed loop that no ring is
    /// linked with but its own; and the path must include the eye, because a ring can sit round the rod at the
    /// foot of the eye, as ring k+1 does round rod k when ring k hangs off the sword.
    static func threadPath(of rod: PartPose) -> [Vector] {
        let radius = Dimensions.Rod.eyeRadius
        let halfEye = (0...90).map { step in
            let angle = -Double.pi / 2 + Double.pi * Double(step) / 90
            return rod.worldPoint(SIMD3(radius * cos(angle), radius * sin(angle), 0))
        }
        return [rod.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0))] + halfEye
    }

    /// The rod rule: the shaft runs through its own hole, the eye sits on its ring's wire with the wire through
    /// it, and the bead is below the bar.
    private static func rodFailures(_ number: Int, in pose: ToyPose) -> [String] {
        var failures: [String] = []
        let rod = pose.rod(number)
        let ring = pose.ring(number).circle

        switch holeRoom(number, in: pose) {
        case nil: failures.append("rod \(number) does not reach through the bar")
        case let room? where room < 0: failures.append("rod \(number) does not fit through its hole")
        default: break
        }

        if simd_distance(ring.nearestPoint(to: rod.position), rod.position) > 1e-9 {
            failures.append("eye \(number) is off its ring's wire")
        }
        // The ring's wire and the eye's wire may touch, but not pass through each other.
        var approaches: [Approach] = []
        Approaches.find(rod.eye, ring, within: .infinity, samples: 64, into: &approaches)
        let closest = approaches.map(\.distance).min() ?? 0
        if closest < Dimensions.Rod.wireRadius + Dimensions.Ring.wireRadius {
            failures.append("ring \(number)'s wire cuts through its eye")
        }

        let hole = pose.bar.worldPoint(SIMD3(Dimensions.Bar.holeX(number), 0, 0))
        let up = pose.bar.worldDirection(SIMD3(0, 1, 0))
        let beadTop = simd_dot(rod.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0)) - hole, up) + Dimensions.Rod.beadRadius
        if beadTop > -Dimensions.Bar.thickness / 2 {
            failures.append("bead \(number) is not below the bar")
        }
        return failures
    }

    /// How much room rod `number`'s shaft has in its own hole: the least distance from the shaft's surface to the
    /// bar's material round the hole, through the bar's thickness and at any tilt. Negative where the shaft cuts
    /// into the bar; nil where it does not reach from above the bar to below it.
    ///
    /// The bar round the hole is taken as a sheet one thickness deep that goes on for ever, with sharp-edged
    /// rims, which is never less material than the bar has. The shaft is straight, so it is inside the sheet only
    /// between the two places where its axis crosses the faces, and fits only if both are inside the hole.
    /// Between them, its axis is furthest from the hole's axis at one of those places, because a point running
    /// along one straight line is nearest another at one place and gets steadily further away either side of it;
    /// so the nearest the shaft comes to the hole's wall is at a face. Outside the sheet, the nearest material is the rim of the hole, or a face beyond
    /// the rim, which the shaft can only reach by passing nearer the rim. So the room is the distance from the
    /// shaft to the nearer of the two rims, less the shaft's radius, and the shaft may touch the hole.
    static func holeRoom(_ number: Int, in pose: ToyPose) -> Double? {
        typealias Bar = Dimensions.Bar
        let shaft = pose.rod(number).shaft
        let hole = pose.bar.worldPoint(SIMD3(Bar.holeX(number), 0, 0))
        let up = pose.bar.worldDirection(SIMD3(0, 1, 0))
        var room = Double.infinity
        for face in [-Bar.thickness / 2, Bar.thickness / 2] {
            let startHeight = simd_dot(shaft.start - hole, up) - face
            let endHeight = simd_dot(shaft.end - hole, up) - face
            guard startHeight > 0, endHeight < 0 else { return nil }
            let point = shaft.start + (shaft.end - shaft.start) * (startHeight / (startHeight - endHeight))
            let offAxis = simd_length((point - hole) - simd_dot(point - hole, up) * up)
            if offAxis >= Bar.holeRadius {
                // The axis goes through the bar's material, or past its edge: through the sheet outside the hole.
                room = min(room, -(offAxis - Bar.holeRadius) - Dimensions.Rod.wireRadius)
                continue
            }
            let rim = Circle(center: hole + face * up, normal: up, radius: Bar.holeRadius)
            let (onShaft, onRim) = Gaps.nearest(.segment(shaft), .circle(rim))
            room = min(room, simd_distance(onShaft, onRim) - Dimensions.Rod.wireRadius)
        }
        return room
    }

    static func isClose(_ a: PartPose, _ b: PartPose, tolerance: Double = 1e-9) -> Bool {
        simd_distance(a.position, b.position) <= tolerance
            && rotationAngle(from: a.orientation, to: b.orientation) <= tolerance
    }

    static func isClose(_ a: ToyPose, _ b: ToyPose, tolerance: Double = 1e-9) -> Bool {
        zip(a.rings, b.rings).allSatisfy { isClose($0, $1, tolerance: tolerance) }
            && zip(a.rods, b.rods).allSatisfy { isClose($0, $1, tolerance: tolerance) }
            && isClose(a.bar, b.bar, tolerance: tolerance)
            && simd_distance(a.swordOffset, b.swordOffset) <= tolerance
    }

    /// The angle of the rotation that takes one orientation to the other.
    static func rotationAngle(from a: simd_quatd, to b: simd_quatd) -> Double {
        let relative = b * a.inverse
        return 2 * atan2(simd_length(relative.imag), abs(relative.real))
    }

    /// The most that any point of any part moves from one pose to the other: for each rigid part, how far its
    /// origin moves, plus how far its farthest point from the axis of its turn is carried round that axis.
    static func largestStep(from a: ToyPose, to b: ToyPose) -> (distance: Double, part: String) {
        /// `reach` gives, for a turn about a unit axis in the part's local frame, the farthest any of its points
        /// lies from that axis through its origin.
        func step(_ first: PartPose, _ second: PartPose, reach: (SIMD3<Double>) -> Double) -> Double {
            let turn = first.orientation.inverse * second.orientation
            let angle = 2 * atan2(simd_length(turn.imag), abs(turn.real))
            let axis = simd_length(turn.imag) > 1e-15 ? simd_normalize(turn.imag) : SIMD3(0, 1, 0)
            return simd_distance(first.position, second.position) + 2 * sin(angle / 2) * reach(axis)
        }
        let ringReach = { (_: SIMD3<Double>) in Dimensions.Ring.radius + Dimensions.Ring.wireRadius }
        // A rod lies within its eye, close round its origin, and a cylinder round its axis as wide as the bead.
        let rodReach = { (axis: SIMD3<Double>) -> Double in
            typealias Rod = Dimensions.Rod
            let beadCenter = SIMD3(0, Rod.beadCenterY, 0)
            let beadOffAxis = simd_length(simd_cross(beadCenter, axis))
            return max(Rod.eyeRadius + Rod.wireRadius, beadOffAxis + Rod.beadRadius)
        }
        var largest = (distance: simd_distance(a.swordOffset, b.swordOffset), part: "sword")
        for number in 1...9 {
            let ring = step(a.ring(number), b.ring(number), reach: ringReach)
            if ring > largest.distance { largest = (ring, "ring \(number)") }
            let rod = step(a.rod(number), b.rod(number), reach: rodReach)
            if rod > largest.distance { largest = (rod, "rod \(number)") }
        }
        let bar = step(a.bar, b.bar, reach: { _ in Dimensions.Bar.length / 2 })
        if bar > largest.distance { largest = (bar, "bar") }
        return largest
    }
}
