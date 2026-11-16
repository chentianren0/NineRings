import Foundation
import Geometry
import Motion
import Puzzle
import Testing
import Toy
import simd

@Suite struct SwordGapTests {
    /// For the record: the smallest gap between the sword and any other part, with every ring on at rest and
    /// through each written move in both directions. The sweeps' own tests hold every gap to the rule; this one
    /// says how near anything comes to the sword, and where.
    @Test(arguments: [ringOneOff, ringOneOn, ringTwoOff, ringTwoOn])
    func smallestGapToTheSword(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let samples = Sweep.samples
        let gaps = Sweep.inParallel(samples + 1) { index in
            Gaps.smallest(in: motion.pose(at: Double(index) / Double(samples)).shapes, involving: [.sword])!
        }
        let index = gaps.indices.min { gaps[$0].distance < gaps[$1].distance }!
        print("ring \(move.ring) \(move.takesOff ? "off" : "on"): smallest gap to the sword \(gaps[index]) at progress \(Double(index) / Double(samples))")
        #expect(gaps[index].distance >= smallestAllowedGap)
        // And of the parts the move moves alone.
        let moving = Set((1...move.ring).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] })
        let moved = Sweep.inParallel(samples + 1) { index in
            let shapes = motion.pose(at: Double(index) / Double(samples)).shapes.filter { $0.name == .sword || moving.contains($0.name) }
            return Gaps.smallest(in: shapes, reach: .infinity)!
        }
        let nearest = moved.indices.min { moved[$0].distance < moved[$1].distance }!
        print("ring \(move.ring) \(move.takesOff ? "off" : "on"): smallest gap between the sword and a moving part \(moved[nearest]) at progress \(Double(nearest) / Double(samples))")
    }

    @Test func smallestGapToTheSwordAtRest() throws {
        let pose = try #require(RestPoses.pose(for: .allOn))
        let gap = try #require(Gaps.smallest(in: pose.shapes, involving: [.sword]))
        print("every ring on, at rest: smallest gap to the sword \(gap)")
        #expect(gap.distance >= smallestAllowedGap)
        // Rod 9 stands close to where the rails close.
        let shaft = try #require(Gaps.smallest(in: pose.shapes.filter { $0.name == .sword || $0.name == .shaft(9) }, reach: .infinity))
        print("every ring on, at rest: shaft 9 to the sword \(shaft)")
        #expect(shaft.distance >= smallestAllowedGap)
    }
}

/// The sword the app draws and the sword the checker checks are one and the same.
@Suite struct SwordCoverTests {
    /// How far the drawn wire may stand outside the checked one: room only for the drawing's single-precision
    /// numbers, which round each point by less than 0.00003 mm. It is a two-hundredth of the smallest gap the
    /// checker allows.
    static let allowance = 0.001

    /// The path the app draws its sword along, as the app has it: `SwordPath` is `SwordShape.wire` in single
    /// precision.
    static var drawnPath: [Vector] { SwordShape.wire.map { Vector(SIMD3<Float>($0)) } }

    /// The sword's shapes as the checker builds them, with the sword at home, in the sword's frame.
    static var checkedPieces: [Shape] {
        var pose = RestPoses.pose(for: .allOn)!
        pose.swordSlide = 0
        return pose.shapes.filter { $0.name == .sword }
    }

    /// Every piece of the wire the app draws lies inside the shapes the checker checks.
    ///
    /// The app draws a tube of the wire's radius along the drawn path (`MeshBuilder.addTube`): a ring of vertices
    /// round each point of the path, each the wire's radius from the point, and flat facets joining each ring to
    /// the next, with flat caps at the two ends. The capsule of that radius round a piece of the path holds both
    /// rings at the piece's ends, and a capsule is convex, so it holds the facets between them as well: the mesh
    /// lies within the capsules round the pieces of the drawn path, its facets just inside the round tube. So
    /// the drawn sword is inside the checked one when the checked pieces have the wire's radius and every point
    /// of every drawn piece is within the allowance of a checked piece's core.
    ///
    /// This fails if the checker leaves out any of the drawn wire, the grip loops for instance, or if the two are
    /// built from different points.
    @Test func theDrawnSwordLiesInsideTheCheckedOne() {
        let checked = Self.checkedPieces
        #expect(checked.allSatisfy { $0.radius == Dimensions.Sword.wireRadius })
        let cores = checked.compactMap { shape -> Segment? in
            if case .segment(let segment) = shape.core { return segment }
            return nil
        }
        #expect(cores.count == checked.count, "every piece of the checked sword is a straight piece")
        let drawn = Self.drawnPath
        let uncovered = zip(drawn, drawn.dropFirst()).map { Segment(start: $0, end: $1) }.filter { !Self.isCovered($0, by: cores) }
        print("cover: \(drawn.count - 1) drawn pieces, \(cores.count) checked pieces, \(uncovered.count) drawn pieces outside the checked sword")
        #expect(uncovered.isEmpty, "drawn pieces outside the checked sword, the first from \(uncovered.first.map { "\($0.start) to \($0.end)" } ?? "")")
    }

    /// And the other way: the checker checks no sword that is not drawn, so the checked sword is the drawn one.
    @Test func theCheckedSwordLiesInsideTheDrawnOne() {
        let drawn = Self.drawnPath
        let cores = zip(drawn, drawn.dropFirst()).map { Segment(start: $0, end: $1) }
        let pieces = Self.checkedPieces.compactMap { shape -> Segment? in
            if case .segment(let segment) = shape.core { return segment }
            return nil
        }
        let uncovered = pieces.filter { !Self.isCovered($0, by: cores) }
        #expect(uncovered.isEmpty, "\(uncovered.count) checked pieces are not drawn")
    }

    /// Whether every point of `piece` is within the allowance of one of `cores`.
    ///
    /// The distance to a straight piece is convex along another straight piece, so if both ends of `piece` are
    /// within the allowance of one core, all of it is. Otherwise `piece` is split in two and each half tried, down
    /// to halves too short to matter.
    static func isCovered(_ piece: Segment, by cores: [Segment], depth: Int = 0) -> Bool {
        func within(_ point: Vector, _ core: Segment) -> Bool {
            simd_distance(core.nearestPoint(to: point), point) <= allowance
        }
        if cores.contains(where: { within(piece.start, $0) && within(piece.end, $0) }) {
            return true
        }
        guard depth < 24, simd_distance(piece.start, piece.end) > allowance / 10 else { return false }
        let middle = (piece.start + piece.end) / 2
        return isCovered(Segment(start: piece.start, end: middle), by: cores, depth: depth + 1)
            && isCovered(Segment(start: middle, end: piece.end), by: cores, depth: depth + 1)
    }

    /// The relation that a ring leaves the rails only over the tip end rests on each side of the sword having
    /// only two ends a ring could pass over: the tip's end, where the sides meet, and the end of its grip loop,
    /// which must lie inside the side's own wire, so that no ring can pass over it without meeting the wire.
    @Test func eachGripLoopEndsInsideItsOwnWire() {
        for side in [1.0, -1.0] {
            let points = SwordShape.centerline(side: side)
            let end = points[points.count - 1]
            // The pieces of the wire before the grip loop's last turn, which the end comes back to lie against.
            let pieces = zip(points, points.dropFirst()).dropLast(SwordShape.gripLoopPieces / 2)
            let nearest = pieces.map { simd_distance(Segment(start: $0, end: $1).nearestPoint(to: end), end) }.min()!
            print("side \(side): the grip loop ends \(String(format: "%.3f", nearest)) mm from the wire's centreline")
            #expect(nearest < Dimensions.Sword.wireRadius / 2)
        }
    }
}
