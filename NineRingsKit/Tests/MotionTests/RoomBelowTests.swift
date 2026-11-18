import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

extension MotionTests {
    /// How far the sword, and everything that rides on it, can go down before anything meets the bar: the limit on how far
    /// the second ring's move may take the sword down. Run with `NINE_RINGS_ROOM_BELOW=1`, optimized.
    @Suite struct RoomBelowTests {
        /// The toy at rest in `state`, with the sword and every ring from `firstRiding` on moved down by `drop`.
        static func pose(_ state: PuzzleState, firstRiding: Int, drop: Double) -> ToyPose {
            let rings = PuzzleState.rings.map { number -> HeldRing in
                var held = state.isOn(number) ? RestPoses.on(number) : RestPoses.hanging(number)
                if number >= firstRiding { held.eye.y -= drop }
                return held
            }
            return RestPoses.pose(holding: rings, swordSlide: Layout.swordHome, swordHeight: -drop)
        }

        /// The smallest gap between the bar and anything but the beads, which hang below it and slide down with their
        /// rods.
        static func barGap(_ pose: ToyPose) -> Gap {
            let shapes = pose.shapes.filter { if case .bead = $0.name { return false } else { return true } }
            return Gaps.smallest(in: shapes, reach: .infinity, involving: [.bar])!
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_ROOM_BELOW"] != nil))
        func howFarDownBeforeTheBar() throws {
            let cases: [(String, PuzzleState, Int)] = [
                ("every ring behind on (ring 2 and on ride)", .allOn, 2),
                ("ring 5 hanging behind (ring 3 and on ride)", PuzzleState(bits: 0x1FF & ~(1 << 4)), 3),
                ("ring 8 hanging behind (ring 3 and on ride)", PuzzleState(bits: 0x1FF & ~(1 << 7)), 3),
            ]
            for (label, state, firstRiding) in cases {
                let rest = Self.pose(state, firstRiding: firstRiding, drop: 0)
                let restGap = try #require(Gaps.smallest(in: rest.shapes.filter { $0.name != .bar }))
                var drop = 0.0
                var limits: [Double: Double] = [:]
                while drop < 60 {
                    let gap = Self.barGap(Self.pose(state, firstRiding: firstRiding, drop: drop)).distance
                    for wanted in [0.3, 0.2] where limits[wanted] == nil && gap < wanted { limits[wanted] = drop - 0.01 }
                    if gap < 0.2 { break }
                    drop += 0.01
                }
                let first = Self.barGap(Self.pose(state, firstRiding: firstRiding, drop: drop))
                print("room below, \(label): rest gap leaving out the bar \(restGap); 0.3 mm from the bar down to \(String(format: "%.2f", limits[0.3] ?? -1)) mm, 0.2 mm down to \(String(format: "%.2f", limits[0.2] ?? -1)) mm; first to meet it: \(first)")
            }
        }
    }
}
