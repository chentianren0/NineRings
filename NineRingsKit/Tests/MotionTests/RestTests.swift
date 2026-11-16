import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

@Suite struct RingTwoRestTests {
    @Test func ringTwoOffRestsClearAndReadsAsItsState() throws {
        let pose = try #require(RestPoses.pose(for: ringTwoOffState))
        let gap = try #require(Gaps.smallest(in: pose.shapes))
        print("rest \(ringTwoOffState): smallest gap \(gap)")
        #expect(gap.distance >= smallestAllowedGap, "\(gap)")
        let failures = Relations.failures(in: pose, mayBeOff: [1, 2])
        #expect(failures.isEmpty, "\(failures)")
        #expect(pose.ringsOnTheSword == ringTwoOffState)
        for ring in PuzzleState.rings {
            #expect(Relations.isRoundTheRails(ring, in: pose) == ringTwoOffState.isOn(ring), "ring \(ring)")
        }
    }

    @Test func ringTwoOffHangsOnTheTipSideOfRingThreesLowerArcWithRodOneThroughIt() throws {
        let pose = try #require(RestPoses.pose(for: ringTwoOffState))
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

    @Test func ringTwoOffHangsAsRingOneOffDoesOneHoleFurtherOn() throws {
        let one = try #require(RestPoses.pose(for: PuzzleState.allOn.moving(1)))
        let two = try #require(RestPoses.pose(for: ringTwoOffState))
        let pitch = SIMD3(Dimensions.Bar.holePitch, 0, 0)
        #expect(Relations.isClose(PartPose(position: one.ring(1).position + pitch, orientation: one.ring(1).orientation), two.ring(2)))
        #expect(Relations.isClose(PartPose(position: one.rod(1).position + pitch, orientation: one.rod(1).orientation), two.rod(2)))
    }
}

/// Every one of the 512 states at rest: nothing within the checker's gap, every relation holding, and the pose reading
/// as its state. Each ring rests by its own state alone, whatever its neighbours are.
@Suite struct EveryRestTests {
    @Test func everyStateRestsClearAndReadsAsItself() throws {
        let states = (0..<512).map { PuzzleState(bits: UInt16($0)) }
        let results = Sweep.inParallel(states.count) { index -> (Gap, Gap, [String], Bool) in
            let state = states[index]
            let pose = RestPoses.pose(for: state)!
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
}
