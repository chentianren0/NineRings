import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

extension MotionTests {
    /// Small, quick checks of the search tools themselves, run with every test run.
    @Suite struct SearchToolTests {
        /// The pair move that the checks below use: ring 3 coming off with ring 1 off in front, so that there is a ring
        /// in front that is off, a ring in front that the sword leaves, rings behind that go down with the sword, and a
        /// rod that leans.
        static let pairFrom = PuzzleState(bits: 0x1FE)

        /// Poses of ring 3's pair move, as written and with the ring's keys and the sword's shaken, so that some poses fail
        /// and some come close. The sword never rises above home, so that the beads of the rings behind stay no nearer
        /// the bar than they rest, where the fast room, like the tuners, leaves a resting bead out.
        static func pairPoses(count: Int) -> [ToyPose] {
            var random = SeededRandom(seed: 7)
            var poses: [ToyPose] = []
            for index in 0..<count {
                var keys = PairMoveOff.keys
                if index % 2 == 1 {
                    for name in ["ring.tip", "ring.tilt", "ring.swing", "ring.eye", "ring.back", "sword.slide", "sword.height"] {
                        keys[name] = keys[name]!.enumerated().map { k, key in
                            let isEnd = k == 0 || k == keys[name]!.count - 1
                            let scale = ["ring.eye", "ring.back", "sword.slide", "sword.height"].contains(name) ? 4.0 : 45
                            let value = isEnd ? key.1 : key.1 + scale * random.normal()
                            return (key.0, name == "sword.height" ? min(value, 0) : value)
                        }
                    }
                }
                // The written poses across the whole path; the shaken ones where the ring moves, which the shaking changes.
                let fraction = Double(index) / Double(count - 1)
                let parameter = index % 2 == 0 ? fraction : 0.30 + 0.55 * fraction
                poses.append(PairMoveOff(ring: 3, from: pairFrom, keys: keys).pose(at: parameter))
            }
            return poses
        }

        /// The parts of ring 3 and of every ring behind it, and the sword: every part that moves in ring 3's pair move.
        static let pairMoving = Set((3...9).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] } + [.sword])

        @Test func fastRoomAgreesWithTheChecker() {
            let model = FastRoom(moving: Array(3...9), swordMoves: true, mayBeOff: [1, 2, 3], cap: 3)
            var largestDifference = 0.0
            for pose in Self.pairPoses(count: 48) {
                let checker = min(Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: Self.pairMoving)?.distance ?? 10, 3)
                let fast = model.smallestGap(pose).0
                largestDifference = max(largestDifference, abs(fast - checker))
                #expect(abs(fast - checker) < 2e-4, "fast \(fast), checker \(checker)")
                #expect(Set(model.failures(pose)) == Set(Relations.failures(in: pose, mayBeOff: [1, 2, 3])))
            }
            // The shaken poses must include some that fail, or the relations are not tested.
            let failing = Self.pairPoses(count: 48).filter { !Relations.failures(in: $0, mayBeOff: [1, 2, 3]).isEmpty }.count
            print("fast room against the checker over 48 poses of ring 3's pair move, \(failing) failing a relation: largest difference \(largestDifference) mm")
            #expect(failing >= 5, "only \(failing) shaken poses fail a relation")
        }

        @Test func holeRoomAgreesWithTheChecker() {
            for (index, pose) in Self.pairPoses(count: 24).enumerated() {
                for rod in [2, 3, 4] {
                    let checker = Relations.holeRoom(rod, in: pose), fast = FastRoom.holeRoom(rod, in: pose)
                    #expect((checker == nil) == (fast == nil))
                    if let checker, let fast { #expect(abs(checker - fast) < 1e-6, "pose \(index) rod \(rod): \(fast) against \(checker)") }
                }
            }
        }

        /// Ring 1 and its rod: every part that moves in ring 1's drop.
        static let ringOneMoving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1)]

        @Test func fastRoomAgreesOnRingOne() {
            let model = FastRoom(moving: [1], swordMoves: false, mayBeOff: [1], cap: 3)
            for index in 0...20 {
                let pose = RingOneOff.written.pose(at: 0.56 + 0.44 * Double(index) / 20)
                let checker = min(Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: Self.ringOneMoving)?.distance ?? 10, 3)
                #expect(abs(model.smallestGap(pose).0 - checker) < 2e-4)
                #expect(model.failures(pose) == Relations.failures(in: pose, mayBeOff: [1]))
            }
        }
    }
}
