import Foundation
import Geometry
@testable import Motion
import Puzzle
import Toy
import simd

/// How much room one pose has, for a search: the smallest gap between parts that can matter, and the relations
/// that can fail, with the same meaning as the checker's (`Gaps`, `Relations`).
///
/// It is quicker than the checker for three reasons, none of which changes what is measured:
///
/// - Only pairs that can change are looked at: a pair with a part that moves, and, when the sword moves, the sword
///   against every ring and rod. Two parts that are not in `moving` are taken to keep the gap they have to each other
///   wherever the span searched holds them: at rest, which the rest poses' own checks cover, or, for the rings that
///   ride down with the sword in the second ring's drop, at the one height they keep through it. Only `FullCheck`
///   measures every pair.
/// - Before measuring a pair it takes a lower bound of their gap that costs a few multiplications (how far one
///   shape's bounding sphere is from the other's centreline circle, for instance), and skips the pair when that
///   bound is already above the smallest gap found so far, or above `cap`. The search only needs the smallest gap,
///   and nothing above `cap` counts.
/// - The nearest points of a circle and another shape are found from the exact distance of a point to a circle,
///   sampled along one shape and refined by a golden-section search, with no arrays made on the way.
///
/// A test (`SearchToolTests`) holds it to the checker's smallest gap and relations over many poses of both
/// written moves.
struct FastRoom: Sendable {
    /// The rings that move, with their rods.
    var moving: [Int]
    /// Whether the sword moves during the move: slides, or goes down and up.
    var swordMoves: Bool
    /// The rings that may be off the rails during the move.
    var mayBeOff: Set<Int>
    /// Gaps above this are reported as this.
    var cap: Double = 1.5
    /// A bead rests a hair under the bar by design (0.25 mm), which a search should not try to widen: only the bead
    /// and the bar are left out, and only while the bead is no nearer the bar than it rests.
    var ignoreRestingBead = true
    /// Whether, when the sword slides, its gaps to the rings and rods that stay still count. They are part of the
    /// checker's room, but in a search for a pose they can hide differences: the rings that stay on keep about
    /// 0.5 mm to the rails wherever the sword is along them.
    var stillAgainstSword = true
    /// Where the bar is held. Only an experiment changes it.
    var bar: PartPose = Layout.bar

    /// The room of one pose: the smallest gap (at most `cap`) and how many relations fail.
    struct Room: CustomStringConvertible {
        var gap: Double
        var between: (PartName, PartName)?
        var failures: [String]

        /// One number for a search: the gap when nothing fails, otherwise a penalty below zero.
        var value: Double { failures.isEmpty ? gap : min(gap, 0) - Double(failures.count) }

        var description: String {
            let pair = between.map { " between \($0.0) and \($0.1)" } ?? ""
            return String(format: "%.3f", gap) + pair + (failures.isEmpty ? "" : "; " + failures.joined(separator: ", "))
        }
    }

    func room(_ pose: ToyPose, relations: Bool = true) -> Room {
        let (gap, between) = smallestGap(pose)
        return Room(gap: gap, between: between, failures: relations ? failures(pose) : [])
    }

    // MARK: Shapes

    struct Piece {
        enum Kind { case circle(Circle), segment(Segment), point(Vector), stadium(Stadium) }
        var name: PartName
        var kind: Kind
        /// The radius swept round the core.
        var radius: Double
        /// A sphere round the core (not the swept shape).
        var center: Vector
        var reach: Double
    }

    static func pieces(of number: Int, in pose: ToyPose) -> [Piece] {
        typealias Rod = Dimensions.Rod
        let ring = pose.ring(number).circle
        let rod = pose.rod(number)
        let shaft = rod.shaft
        let bead = rod.worldPoint(SIMD3(0, Rod.beadCenterY, 0))
        return [
            Piece(name: .ring(number), kind: .circle(ring), radius: Dimensions.Ring.wireRadius, center: ring.center, reach: ring.radius),
            Piece(name: .eye(number), kind: .circle(rod.eye), radius: Rod.wireRadius, center: rod.position, reach: Rod.eyeRadius),
            Piece(name: .shaft(number), kind: .segment(shaft), radius: Rod.wireRadius, center: (shaft.start + shaft.end) / 2,
                  reach: simd_distance(shaft.start, shaft.end) / 2),
            Piece(name: .bead(number), kind: .point(bead), radius: Rod.beadRadius, center: bead, reach: 0),
        ]
    }

    static func barPiece(_ pose: ToyPose) -> Piece {
        let stadium = pose.bar.stadium
        return Piece(name: .bar, kind: .stadium(stadium), radius: Dimensions.Bar.thickness / 2, center: stadium.center,
                     reach: stadium.halfLength + stadium.radius)
    }

    /// The sword's straight pieces in its own frame, both sides.
    static let swordPieces: [Segment] = [1.0, -1.0].flatMap { side in
        let points = SwordShape.centerline(side: side)
        return zip(points, points.dropFirst()).map { Segment(start: $0, end: $1) }
    }

    static func swordPieces(_ pose: ToyPose) -> [Piece] {
        // The sword's whole offset: its slide and, where a move lowers it, its height.
        let slide = pose.swordOffset
        return swordPieces.map { piece in
            let segment = Segment(start: piece.start + slide, end: piece.end + slide)
            return Piece(name: .sword, kind: .segment(segment), radius: Dimensions.Sword.wireRadius,
                         center: (segment.start + segment.end) / 2, reach: simd_distance(segment.start, segment.end) / 2)
        }
    }

    // MARK: The smallest gap

    func smallestGap(_ pose: ToyPose) -> (Double, (PartName, PartName)?) {
        let movingSet = Set(moving)
        let movingPieces = moving.flatMap { Self.pieces(of: $0, in: pose) }
        let stillPieces = (1...9).filter { !movingSet.contains($0) }.flatMap { Self.pieces(of: $0, in: pose) } + [Self.barPiece(pose)]
        let sword = Self.swordPieces(pose)

        var best = cap
        var between: (PartName, PartName)?
        func consider(_ a: Piece, _ b: Piece) {
            if a.name.isJoined(to: b.name) { return }
            if ignoreRestingBead, isRestingBead(a, b, pose) { return }
            let bound = Self.lowerBound(a, b) - a.radius - b.radius
            if bound >= best { return }
            let gap = Self.distance(a, b, below: best + a.radius + b.radius) - a.radius - b.radius
            if gap < best {
                best = gap
                between = (a.name, b.name)
            }
        }
        for (index, a) in movingPieces.enumerated() {
            for b in movingPieces[(index + 1)...] { consider(a, b) }
            for b in stillPieces { consider(a, b) }
            for b in sword { consider(a, b) }
        }
        if swordMoves && stillAgainstSword {
            for a in stillPieces where a.name != .bar {
                for b in sword { consider(a, b) }
            }
        }
        return (best, between)
    }

    private func isRestingBead(_ a: Piece, _ b: Piece, _ pose: ToyPose) -> Bool {
        let bead: Piece
        switch (a.name, b.name) {
        case (.bead, .bar): bead = a
        case (.bar, .bead): bead = b
        default: return false
        }
        // No nearer the bar than a bead at rest: the bead's top no higher than at rest.
        let restTop = Layout.eyeHeightOn + Dimensions.Rod.beadCenterY + Dimensions.Rod.beadRadius
        return bead.center.y + Dimensions.Rod.beadRadius <= restTop + 1e-9 && pose.bar == Layout.bar
            && bar == Layout.bar
    }

    /// A lower bound of the distance between two cores, from a few dot products.
    static func lowerBound(_ a: Piece, _ b: Piece) -> Double {
        var bound = simd_distance(a.center, b.center) - a.reach - b.reach
        if case .circle(let circle) = a.kind { bound = max(bound, distance(b.center, circle) - b.reach) }
        if case .circle(let circle) = b.kind { bound = max(bound, distance(a.center, circle) - a.reach) }
        return bound
    }

    /// The exact distance from a point to a circle.
    @inline(__always)
    static func distance(_ point: Vector, _ circle: Circle) -> Double {
        let offset = point - circle.center
        let normal = circle.normal
        let height = simd_dot(offset, normal)
        let inPlane = simd_length(offset - height * normal)
        let off = inPlane - circle.radius
        return (height * height + off * off).squareRoot()
    }

    /// The distance between two cores. Where it is clearly more than `below`, any number above `below` may come
    /// back.
    static func distance(_ a: Piece, _ b: Piece, below: Double) -> Double {
        switch (a.kind, b.kind) {
        case (.circle(let first), .circle(let second)):
            return circleToCircle(first, second)
        case (.circle(let circle), .segment(let segment)), (.segment(let segment), .circle(let circle)):
            return circleToSegment(circle, segment, within: below)
        case (.circle(let circle), .point(let point)), (.point(let point), .circle(let circle)):
            return distance(point, circle)
        case (.segment(let first), .segment(let second)):
            return Approaches.nearest(first, second).distance
        case (.segment(let segment), .point(let point)), (.point(let point), .segment(let segment)):
            return simd_distance(segment.nearestPoint(to: point), point)
        case (.point(let first), .point(let second)):
            return simd_distance(first, second)
        default:
            let (pointA, pointB) = Gaps.nearest(a.core, b.core)
            return simd_distance(pointA, pointB)
        }
    }

    /// The least of a function of an angle round a circle: sampled, then each sampled dip refined.
    static func leastRound(samples: Int, _ function: (Double) -> Double) -> Double {
        let step = 2 * Double.pi / Double(samples)
        var values = [Double](repeating: 0, count: samples)
        for index in 0..<samples { values[index] = function(Double(index) * step) }
        var best = Double.infinity
        for index in 0..<samples {
            let before = values[(index + samples - 1) % samples], here = values[index], after = values[(index + 1) % samples]
            guard here <= before && here <= after else { continue }
            let angle = Double(index) * step
            best = min(best, goldenSection(function, from: angle - step, to: angle + step, value: here))
        }
        return best
    }

    /// The least value of `function` between two parameters, where it has one dip (a golden-section search); never
    /// more than `value`, a value already known in that span.
    static func goldenSection(_ function: (Double) -> Double, from lower: Double, to upper: Double, value: Double) -> Double {
        let ratio = (5.0.squareRoot() - 1) / 2
        var lower = lower, upper = upper
        var a = upper - ratio * (upper - lower), b = lower + ratio * (upper - lower)
        var valueA = function(a), valueB = function(b)
        for _ in 0..<40 where upper - lower > 1e-9 {
            if valueA < valueB {
                upper = b; b = a; valueB = valueA
                a = upper - ratio * (upper - lower); valueA = function(a)
            } else {
                lower = a; a = b; valueA = valueB
                b = lower + ratio * (upper - lower); valueB = function(b)
            }
        }
        return min(value, valueA, valueB)
    }

    static func circleToCircle(_ first: Circle, _ second: Circle) -> Double {
        // Sample the smaller circle against the exact distance to the larger.
        let (walked, other) = first.radius <= second.radius ? (first, second) : (second, first)
        return leastRound(samples: 72) { angle in
            distance(walked.center + walked.radius * (cos(angle) * walked.axisU + sin(angle) * walked.axisV), other)
        }
    }

    static func circleToSegment(_ circle: Circle, _ segment: Segment, within reach: Double) -> Double {
        // Only the part of the segment within `reach` of the circle's bounding sphere can be nearer than `reach`.
        let direction = segment.end - segment.start
        let length = simd_length(direction)
        guard length > 1e-12 else { return distance(segment.start, circle) }
        let unit = direction / length
        let along = simd_dot(circle.center - segment.start, unit)
        let offAxis = simd_length(circle.center - segment.start - along * unit)
        let sphere = circle.radius + reach
        guard offAxis < sphere else { return offAxis - circle.radius }
        let half = (sphere * sphere - offAxis * offAxis).squareRoot()
        let lower = max(0, along - half), upper = min(length, along + half)
        guard lower < upper else {
            return min(distance(segment.start, circle), distance(segment.end, circle))
        }
        let function = { (s: Double) in distance(segment.start + s * unit, circle) }
        let samples = max(3, Int(((upper - lower) / 0.6).rounded(.up)))
        let step = (upper - lower) / Double(samples)
        var values = [Double](repeating: 0, count: samples + 1)
        for index in 0...samples { values[index] = function(lower + Double(index) * step) }
        var best = Double.infinity
        for index in 0...samples {
            let here = values[index]
            if index > 0 && values[index - 1] < here { continue }
            if index < samples && values[index + 1] < here { continue }
            let s = lower + Double(index) * step
            best = min(best, goldenSection(function, from: max(lower, s - step), to: min(upper, s + step), value: here))
        }
        return best
    }

    // MARK: Relations

    /// The relations of `Relations.failures` that can change in this move, each a sentence when it fails. Parts
    /// too far apart to be linked or threaded are not tested.
    func failures(_ pose: ToyPose) -> [String] {
        var failures: [String] = []
        let movingSet = Set(moving)
        let rings = (1...9).map { pose.ring($0).circle }
        let ringRadius = Dimensions.Ring.radius, eyeRadius = Dimensions.Rod.eyeRadius

        /// Whether rod `rod`'s threading path could cross ring `ring`'s disc at all.
        func rodCanReach(_ rod: Int, _ ring: Int) -> Bool {
            let rodPose = pose.rod(rod)
            let line = Segment(start: rodPose.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0)), end: rodPose.position)
            return simd_distance(line.nearestPoint(to: rings[ring - 1].center), rings[ring - 1].center) <= ringRadius + eyeRadius + 1e-6
        }
        func through(_ rod: Int, _ ring: Int) -> Bool {
            guard rodCanReach(rod, ring) else { return false }
            return Self.isThreaded(pose.rod(rod), through: rings[ring - 1])
        }
        func eyeLinked(_ rod: Int, _ ring: Int) -> Bool {
            guard simd_distance(pose.rod(rod).position, rings[ring - 1].center) <= ringRadius + eyeRadius + 1e-6 else { return false }
            return Self.areLinked(pose.rod(rod).eye, rings[ring - 1])
        }

        for ring in 1...9 {
            let moves = movingSet.contains(ring)
            if moves || swordMoves {
                let (near, far) = Relations.swordCrossings(of: ring, in: pose)
                if near.count % 2 != far.count % 2 { failures.append("ring \(ring) goes round one rail of the sword but not the other") }
                if !mayBeOff.contains(ring) && !(near.count % 2 == 1 && far.count % 2 == 1) { failures.append("ring \(ring) has left the rails") }
            }
            for rod in 1...9 where rod != ring && (moves || movingSet.contains(rod)) {
                let isThrough = through(rod, ring)
                if isThrough != (rod == ring - 1) {
                    failures.append(isThrough ? "rod \(rod) passes through ring \(ring)" : "rod \(rod) has come out of ring \(ring)")
                }
            }
            for rod in 1...9 where moves || movingSet.contains(rod) {
                let linked = rod == ring ? Self.areLinked(pose.rod(rod).eye, rings[ring - 1]) : eyeLinked(rod, ring)
                if linked != (rod == ring) {
                    failures.append(linked ? "eye \(rod) is linked with ring \(ring)" : "ring \(ring) has come out of its eye")
                }
            }
            for other in (ring + 1)..<10 where moves || movingSet.contains(other) {
                guard simd_distance(rings[ring - 1].center, rings[other - 1].center) < 2 * ringRadius + 1e-6 else { continue }
                if Self.areLinked(rings[ring - 1], rings[other - 1]) { failures.append("rings \(ring) and \(other) are linked") }
            }
        }
        for rod in moving { failures += rodFailures(rod, in: pose) }
        if !Relations.isClose(pose.bar, bar) { failures.append("the bar has moved") }
        return failures
    }

    /// How much room rod `number`'s shaft has in its own hole, as `Relations.holeRoom` measures it, with the
    /// distance from the shaft to each rim found from the exact distance of a point to a circle. (The checker's
    /// own search for that distance is slow when the shaft runs along the rim's axis, where the distance hardly
    /// changes round the rim: about 0.2 ms a rod.)
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
                room = min(room, -(offAxis - Bar.holeRadius) - Dimensions.Rod.wireRadius)
                continue
            }
            let rim = Circle(center: hole + face * up, normal: up, radius: Bar.holeRadius)
            room = min(room, circleToSegment(rim, shaft, within: .infinity) - Dimensions.Rod.wireRadius)
        }
        return room
    }

    /// `Relations.railChangeFailures`, for the rings that can change.
    func railChanges(from before: ToyPose, to after: ToyPose) -> [String] {
        var failures: [String] = []
        let rings = swordMoves ? Array(1...9) : moving
        for ring in rings {
            let wasRound = Relations.isRoundTheRails(ring, in: before)
            guard wasRound != Relations.isRoundTheRails(ring, in: after) else { continue }
            let (near, far) = Relations.swordCrossings(of: ring, in: wasRound ? before : after)
            if (near + far).contains(where: { $0.x >= Relations.tipEnd }) {
                failures.append("ring \(ring) \(wasRound ? "leaves" : "joins") the rails away from the tip end")
            }
        }
        return failures
    }

    /// The rod rule for a rod that moves, as `Relations` checks it.
    private func rodFailures(_ number: Int, in pose: ToyPose) -> [String] {
        var failures: [String] = []
        let rod = pose.rod(number)
        let ring = pose.ring(number).circle
        switch Self.holeRoom(number, in: pose) {
        case nil: failures.append("rod \(number) does not reach through the bar")
        case let room? where room < 0: failures.append("rod \(number) does not fit through its hole")
        default: break
        }
        if simd_distance(ring.nearestPoint(to: rod.position), rod.position) > 1e-9 { failures.append("eye \(number) is off its ring's wire") }
        if Self.circleToCircle(rod.eye, ring) < Dimensions.Rod.wireRadius + Dimensions.Ring.wireRadius {
            failures.append("ring \(number)'s wire cuts through its eye")
        }
        let hole = pose.bar.worldPoint(SIMD3(Dimensions.Bar.holeX(number), 0, 0))
        let up = pose.bar.worldDirection(SIMD3(0, 1, 0))
        let beadTop = simd_dot(rod.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0)) - hole, up) + Dimensions.Rod.beadRadius
        if beadTop > -Dimensions.Bar.thickness / 2 { failures.append("bead \(number) is not below the bar") }
        return failures
    }
}

extension FastRoom {
    /// The angles at which an arc of `circle`, from `start` to `end` radians, goes through the plane of `disc`
    /// inside it. The circle's points are `center + radius (cos θ axisU + sin θ axisV)`; its height over the
    /// disc's plane is `d + a cos θ + b sin θ`, which is zero at two angles at most.
    static func crossings(of circle: Circle, from start: Double, to end: Double, through disc: Circle) -> Int {
        let normal = disc.normal
        let d = simd_dot(circle.center - disc.center, normal)
        let a = circle.radius * simd_dot(circle.axisU, normal), b = circle.radius * simd_dot(circle.axisV, normal)
        let amplitude = (a * a + b * b).squareRoot()
        guard amplitude > abs(d) else { return 0 }
        let phase = atan2(b, a), spread = acos(-d / amplitude)
        var count = 0
        for angle in [phase + spread, phase - spread] {
            // Into the arc's span, a whole turn at a time.
            var turned = angle
            while turned < start { turned += 2 * .pi }
            while turned >= start + 2 * .pi { turned -= 2 * .pi }
            guard turned <= end else { continue }
            if simd_distance(circle.point(at: turned / (2 * .pi)), disc.center) < disc.radius { count += 1 }
        }
        return count
    }

    /// Whether two circles are linked: one goes through the other's disc an odd number of times. The same question
    /// as `Relations.areLinked`, answered exactly rather than with 360 straight pieces.
    static func areLinked(_ first: Circle, _ second: Circle) -> Bool {
        crossings(of: first, from: 0, to: 2 * .pi, through: second) % 2 == 1
    }

    /// Whether a rod is threaded through a ring: its path from the bead up the shaft to the foot of the eye, and
    /// round one side of the eye to its top, goes through the ring's disc an odd number of times. The path of
    /// `Relations.threadPath`, with the half eye taken exactly.
    static func isThreaded(_ rod: PartPose, through disc: Circle) -> Bool {
        let bead = rod.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0))
        let foot = rod.worldPoint(SIMD3(0, -Dimensions.Rod.eyeRadius, 0))
        let shaft = Relations.crossings(of: [bead, foot], through: disc).count
        return (shaft + crossings(of: rod.eye, from: -.pi / 2, to: .pi / 2, through: disc)) % 2 == 1
    }
}

extension FastRoom.Piece {
    var core: ShapeCore {
        switch kind {
        case .circle(let circle): .circle(circle)
        case .segment(let segment): .segment(segment)
        case .point(let point): .point(point)
        case .stadium(let stadium): .stadium(stadium)
        }
    }
}
