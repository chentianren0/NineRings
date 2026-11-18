import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

extension MotionTests {
    /// Every one of the 512 states at rest: nothing within the checker's gap, every relation holding, and the pose reading
    /// as its state. Each ring rests by its own state alone, whatever its neighbours are.
    @Suite struct EveryRestTests {
        @Test func everyStateRestsClearAndReadsAsItself() throws {
            let states = (0..<512).map { PuzzleState(bits: UInt16($0)) }
            let results = Sweep.inParallel(states.count) { index -> (Gap, Gap, [String], Bool) in
                let state = states[index]
                let pose = RestPoses.pose(for: state)
                let shapes = pose.shapes
                let off = Set(PuzzleState.rings.filter { !state.isOn($0) })
                let reads = pose.ringsOnTheSword == state
                    && PuzzleState.rings.allSatisfy { Relations.isRoundTheRails($0, in: pose) == state.isOn($0) }
                return (Gaps.smallest(in: shapes)!, Gaps.smallest(in: shapes.filter { $0.name != .bar })!, Relations.failures(in: pose, mayBeOff: off), reads)
            }
            let worst = results.indices.min { results[$0].0.distance < results[$1].0.distance }!
            let worstOther = results.indices.min { results[$0].1.distance < results[$1].1.distance }!
            print("every rest: smallest gap \(results[worst].0) in \(states[worst])")
            print("every rest: smallest gap leaving out the bar \(results[worstOther].1) in \(states[worstOther])")
            for index in states.indices {
                #expect(results[index].0.distance >= smallestAllowedGap, "\(states[index]): \(results[index].0)")
                #expect(results[index].2.isEmpty, "\(states[index]): \(results[index].2)")
                #expect(results[index].3, "\(states[index]) does not read as itself")
            }
        }

        /// One relation pinned in one state: ring 2 off, with ring 1 on in front of it, hangs on the tip side of ring 3's
        /// lower arc with its eye below the rails and rod 1 down through it.
        @Test func ringTwoOffHangsOnTheTipSideOfRingThreesLowerArcWithRodOneThroughIt() throws {
            let pose = RestPoses.pose(for: ringTwoOffState)
            let ringTwo = pose.ring(2).circle
            let ringThree = pose.ring(3).circle
            let towardTip = ringThree.normal.x < 0 ? ringThree.normal : -ringThree.normal
            let sides = Relations.loop(ringTwo).map { simd_dot($0 - ringThree.center, towardTip) }
            #expect(sides.allSatisfy { $0 > 0 })
            // Its eye is below the rails, so its rod is out of the slot.
            let eyeTop = pose.rod(2).position.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius
            #expect(eyeTop < Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius)
            // Ring 1 is on in front of it, and rod 1 runs down through it.
            #expect(Relations.isRoundTheRails(1, in: pose))
            #expect(Relations.crossings(of: Relations.threadPath(of: pose.rod(1)), through: ringTwo).count == 1)
        }
    }
}
