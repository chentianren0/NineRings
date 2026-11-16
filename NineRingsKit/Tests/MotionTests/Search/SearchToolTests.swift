import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Small, quick checks of the search tools themselves, run with every test run.
@Suite struct SearchToolTests {
    /// Poses of ring 2's move, as written and with its keys shaken, so that some poses fail and some come close.
    static func ringTwoPoses(count: Int) -> [ToyPose] {
        var random = SeededRandom(seed: 7)
        var poses: [ToyPose] = []
        for index in 0..<count {
            var keys = RingTwoOff.keys
            if index % 2 == 1 {
                for name in RingTwoTuneTests.names {
                    keys[name] = keys[name]!.enumerated().map { k, key in
                        let isEnd = k == 0 || k == keys[name]!.count - 1
                        let scale = name == "sword" || name == "ring2.eye" ? 4.0 : 30
                        return (key.0, isEnd ? key.1 : key.1 + scale * random.normal())
                    }
                }
            }
            poses.append(RingTwoOff(keys: keys).pose(at: Double(index) / Double(count - 1)))
        }
        return poses
    }

    @Test func fastRoomAgreesWithTheChecker() {
        let model = FastRoom(moving: [1, 2], swordMoves: true, mayBeOff: [1, 2], cap: 3)
        let moving = RingTwoTuneTests.moving
        var largestDifference = 0.0
        for pose in Self.ringTwoPoses(count: 48) {
            let checker = min(Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: moving)?.distance ?? 10, 3)
            let fast = model.smallestGap(pose).0
            largestDifference = max(largestDifference, abs(fast - checker))
            #expect(abs(fast - checker) < 2e-4, "fast \(fast), checker \(checker)")
            #expect(Set(model.failures(pose)) == Set(Relations.failures(in: pose, mayBeOff: [1, 2])))
        }
        print("fast room against the checker over 48 poses of ring 2's move: largest difference \(largestDifference) mm")
        // The shaken poses must include some that fail, or the relations are not tested.
        let failing = Self.ringTwoPoses(count: 48).filter { !Relations.failures(in: $0, mayBeOff: [1, 2]).isEmpty }.count
        #expect(failing >= 5, "only \(failing) shaken poses fail a relation")
    }

    @Test func holeRoomAgreesWithTheChecker() {
        for (index, pose) in Self.ringTwoPoses(count: 24).enumerated() {
            for rod in [1, 2] {
                let checker = Relations.holeRoom(rod, in: pose), fast = FastRoom.holeRoom(rod, in: pose)
                #expect((checker == nil) == (fast == nil))
                if let checker, let fast { #expect(abs(checker - fast) < 1e-6, "pose \(index) rod \(rod): \(fast) against \(checker)") }
            }
        }
    }

    @Test func fastRoomAgreesOnRingOne() {
        let model = FastRoom(moving: [1], swordMoves: false, mayBeOff: [1], cap: 3)
        for index in 0...20 {
            let pose = RingOneOff.written.pose(at: 0.56 + 0.44 * Double(index) / 20)
            let checker = min(Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: TuneTests.moving)?.distance ?? 10, 3)
            #expect(abs(model.smallestGap(pose).0 - checker) < 2e-4)
            #expect(model.failures(pose) == Relations.failures(in: pose, mayBeOff: [1]))
        }
    }
}
