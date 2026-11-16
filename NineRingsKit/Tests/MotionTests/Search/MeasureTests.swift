import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Times the pieces of today's search tools, to see where a tuner's time goes. Run with
/// `NINE_RINGS_MEASURE=1`, optimized. It prints one line per piece.
@Suite struct MeasureTests {
    /// Seconds per call of `work`, over at least `minimum` seconds.
    static func time(_ label: String, minimum: Double = 0.5, _ work: () -> Void) -> Double {
        var calls = 0
        let start = DispatchTime.now().uptimeNanoseconds
        var elapsed = 0.0
        repeat {
            work()
            calls += 1
            elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        } while elapsed < minimum
        let each = elapsed / Double(calls)
        print(String(format: "%-58@ %10.1f µs  (%d calls)", label as NSString, each * 1e6, calls))
        return each
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_MEASURE"] != nil))
    func measure() {
        let ringTwo = RingTwoOff.written
        let parameter = 0.6
        let pose = ringTwo.pose(at: parameter)
        let shapes = pose.shapes
        print("shapes in a pose: \(shapes.count), of them sword pieces: \(shapes.filter { $0.name == .sword }.count)")
        var sink = 0.0
        _ = Self.time("pose of ring 2's move") { sink += ringTwo.pose(at: parameter).swordSlide }
        _ = Self.time("all shapes of a pose") { sink += Double(ringTwo.pose(at: parameter).shapes.count) }
        _ = Self.time("smallest gap, every pair (checker)") { sink += Gaps.smallest(in: shapes)!.distance }
        let moving = RingTwoTuneTests.moving
        let withoutBar = shapes.filter { $0.name != .bar }
        _ = Self.time("smallest gap, pairs with a moving part (ring 2 tuner)") {
            sink += Gaps.smallest(in: withoutBar, involving: moving)!.distance
        }
        _ = Self.time("relations, every one (checker)") { sink += Double(Relations.failures(in: pose, mayBeOff: [1, 2]).count) }
        _ = Self.time("ring 2 tuner's room at one point") { sink += RingTwoTuneTests.room(ringTwo, at: parameter) }
        let score = Self.time("ring 2 tuner's score of one path (301 points)", minimum: 3) {
            sink += RingTwoTuneTests.score(RingTwoOff.keys)
        }
        let items = RingTwoTuneTests.free(RingTwoOff.keys).count
        print("ring 2 tuner: \(items) free numbers, so \(2 * items + 12) scores a round, \(String(format: "%.1f", Double(2 * items + 12) * score)) s a round")

        // The pairs the checker looks at, and how many it measures after the bounding spheres.
        var pairs = 0, measured = 0
        for (index, first) in shapes.enumerated() {
            for second in shapes[(index + 1)...] where !first.name.isJoined(to: second.name) {
                pairs += 1
                if simd_distance(first.boundCenter, second.boundCenter) <= first.boundRadius + second.boundRadius + 3 { measured += 1 }
            }
        }
        print("pairs not joined: \(pairs), within reach: \(measured)")

        // The cost of each kind of nearest-points search.
        let ring1 = pose.ring(1).circle, ring2 = pose.ring(2).circle
        _ = Self.time("nearest points, ring and ring (96 samples)") {
            sink += simd_distance(Gaps.nearest(.circle(ring1), .circle(ring2)).0, .zero)
        }
        let piece = Segment(start: SIMD3(20, -3, 9.4), end: SIMD3(30, -3, 9.4))
        _ = Self.time("nearest points, ring and sword piece (48 samples)") {
            sink += simd_distance(Gaps.nearest(.circle(ring2), .segment(piece)).0, .zero)
        }
        _ = Self.time("nearest points, two segments") {
            sink += simd_distance(Gaps.nearest(.segment(piece), .segment(pose.rod(1).shaft)).0, .zero)
        }

        let ringOne = RingOneOff.written
        _ = Self.time("ring 1 tuner's score of one path (161 points)", minimum: 3) {
            sink += TuneTests.score(TuneTests.Drop.initial)
        }
        _ = Self.time("pose of ring 1's move") { sink += ringOne.pose(at: 0.7).swordSlide }
        let fast2 = FastRoom(moving: [1, 2], swordMoves: true, mayBeOff: [1, 2])
        _ = Self.time("fast room: gap, ring 2's move") { sink += fast2.smallestGap(pose).0 }
        _ = Self.time("fast room: relations, ring 2's move") { sink += Double(fast2.failures(pose).count) }
        let fast1 = FastRoom(moving: [1], swordMoves: false, mayBeOff: [1])
        let poseOne = ringOne.pose(at: 0.7)
        _ = Self.time("checker gap, moving parts, ring 1's drop") {
            sink += Gaps.smallest(in: poseOne.shapes.filter { $0.name != .bar }, involving: TuneTests.moving)!.distance
        }
        _ = Self.time("fast room: gap, ring 1's drop") { sink += fast1.smallestGap(poseOne).0 }
        _ = Self.time("fast room: relations, ring 1's drop") { sink += Double(fast1.failures(poseOne).count) }
        _ = Self.time("relation: sword crossings of one ring") { sink += Double(Relations.swordCrossings(of: 1, in: poseOne).near.count) }
        _ = Self.time("relation: hole room of rod 1") { sink += Relations.holeRoom(1, in: poseOne) ?? 0 }
        _ = Self.time("relation: rod 1 threaded through ring 2, exact") { sink += FastRoom.isThreaded(poseOne.rod(1), through: poseOne.ring(2).circle) ? 1 : 0 }
        _ = Self.time("relation: eye 2 linked with ring 1, exact") { sink += FastRoom.areLinked(poseOne.rod(2).eye, poseOne.ring(1).circle) ? 1 : 0 }
        _ = Self.time("relation: eye 2 linked with ring 1, checker") { sink += Relations.areLinked(poseOne.rod(2).eye, poseOne.ring(1).circle) ? 1 : 0 }
        _ = Self.time("relation: rail change between two poses") { sink += Double(Relations.railChangeFailures(from: poseOne, to: poseOne).count) }
        let shaken = SearchToolTests.ringTwoPoses(count: 48)
        let failing = shaken.filter { !fast2.failures($0).isEmpty }.count
        let tight = shaken.filter { fast2.smallestGap($0).0 < 0.2 }.count
        print("shaken poses: \(failing) of 48 with a relation failing, \(tight) with a gap under 0.2 mm")
        print("(ignore) \(sink)")
    }
}
