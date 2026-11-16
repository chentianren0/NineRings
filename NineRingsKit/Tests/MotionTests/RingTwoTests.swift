import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

let ringTwoOff = Move(ring: 2, from: .allOn)!
let ringTwoOn = ringTwoOff.reversed
let ringTwoOffState = PuzzleState.allOn.moving(2)

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

@Suite struct RingTwoMoveTests {
    @Test(arguments: [ringTwoOff, ringTwoOn])
    func nothingPassesThroughAnythingAndNothingJumps(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let sweep = Sweep(motion)
        let smallest = sweep.smallestGap
        let step = sweep.largestStep
        let direction = move.takesOff ? "off" : "on"
        print("ring 2 \(direction): smallest gap \(smallest.gap) at progress \(smallest.progress)")
        print("ring 2 \(direction): largest step \(String(format: "%.4f", step.distance)) mm, \(step.part), at progress \(step.progress)")
        #expect(smallest.gap.distance >= smallestAllowedGap)
        #expect(step.distance <= largestAllowedStep)
        // For the record: the smallest gap other than the beads resting a hair under the bar, and the smallest
        // that involves a part the move moves.
        let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2), .bead(2)]
        let records = Sweep.inParallel(sweep.poses.count) { index -> (Gap, Gap) in
            let shapes = sweep.poses[index].shapes.filter { $0.name != .bar }
            return (Gaps.smallest(in: shapes)!, Gaps.smallest(in: shapes, involving: moving)!)
        }
        let others = records.indices.min { records[$0].0.distance < records[$1].0.distance }!
        let moved = records.indices.min { records[$0].1.distance < records[$1].1.distance }!
        print("ring 2 \(direction): smallest gap leaving out the bar \(records[others].0) at progress \(sweep.progress[others])")
        print("ring 2 \(direction): smallest gap of a moving part \(records[moved].1) at progress \(sweep.progress[moved])")
        if let failure = sweep.firstRelationFailure {
            Issue.record("at progress \(failure.progress): \(failure.failures.joined(separator: "; "))")
        }
    }

    @Test(arguments: [ringTwoOff, ringTwoOn])
    func theEndsAreTheRestPoses(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let before = try #require(RestPoses.pose(for: move.from))
        let after = try #require(RestPoses.pose(for: move.to))
        #expect(Relations.isClose(motion.pose(at: 0), before))
        #expect(Relations.isClose(motion.pose(at: 1), after))
    }

    @Test func goingOnIsComingOffBackwards() throws {
        let off = try #require(MoveMotion(ringTwoOff))
        let on = try #require(MoveMotion(ringTwoOn))
        for index in 0...200 {
            let progress = Double(index) / 200
            #expect(Relations.isClose(off.pose(at: progress), on.pose(at: 1 - progress), tolerance: 1e-9))
        }
    }

    /// Rings 3 to 9 and their rods, and the bar, stay exactly where they rest.
    @Test func everyOtherPartStaysExactlyStill() throws {
        let motion = try #require(MoveMotion(ringTwoOff))
        let rest = try #require(RestPoses.pose(for: .allOn))
        for index in 0...4000 {
            let pose = motion.pose(at: Double(index) / 4000)
            for ring in 3...9 {
                #expect(pose.ring(ring) == rest.ring(ring), "ring \(ring) moved at sample \(index)")
                #expect(pose.rod(ring) == rest.rod(ring), "rod \(ring) moved at sample \(index)")
            }
            #expect(pose.bar == rest.bar)
            // Ring 1's eye never moves either: rod 1 stays down through the slot and through ring 2.
            #expect(pose.rod(1).position == rest.rod(1).position)
        }
    }

    /// Rings 1 and 2 leave and join the rails only over the tip end: just before a ring leaves, or just after it
    /// joins, the sword goes through it only near the tip's end. Ring 1 leaves and comes back once; ring 2 leaves
    /// once, after ring 1 has left and before it comes back.
    @Test func ringsOneAndTwoLeaveAndJoinTheRailsOnlyOverTheTipEnd() throws {
        let motion = try #require(MoveMotion(ringTwoOff))
        let samples = 4000
        var changes: [Int: [Double]] = [1: [], 2: []]
        for ring in [1, 2] {
            var previous: (on: Bool, crossings: [SIMD3<Double>])?
            for index in 0...samples {
                let progress = Double(index) / Double(samples)
                let pose = motion.pose(at: progress)
                let (near, far) = Relations.swordCrossings(of: ring, in: pose)
                let on = Relations.isRoundTheRails(ring, in: pose)
                if let previous, previous.on != on {
                    changes[ring, default: []].append(progress)
                    let last = previous.on ? previous.crossings : near + far
                    for crossing in last {
                        #expect(crossing.x < Dimensions.Sword.railOffset / 2, "the sword went through ring \(ring) at \(crossing) as it left or joined")
                    }
                }
                previous = (on, near + far)
            }
        }
        print("rails: ring 1 leaves and joins at \(changes[1]!), ring 2 leaves at \(changes[2]!)")
        #expect(changes[1]!.count == 2)
        #expect(changes[2]!.count == 1)
        if changes[1]!.count == 2, let leaves = changes[2]!.first {
            #expect(changes[1]![0] < leaves && leaves < changes[1]![1])
        }
    }

    @Test func theStagesComeInOrderAndEachDoesWhatItsNameSays() throws {
        let motion = try #require(MoveMotion(ringTwoOff))
        let stages = motion.stages
        #expect(stages.map(\.name) == ["Ring 1 steps aside", "Ring 2 over the tip", "Down through the slot", "Ring 2 hangs", "Ring 1 back on"])
        #expect(stages.first?.start == 0 && stages.last?.end == 1)
        #expect(zip(stages, stages.dropFirst()).allSatisfy { $0.end == $1.start && $0.start < $0.end })

        let samples = (0...2000).map { Double($0) / 2000 }
        let poses = samples.map(motion.pose(at:))
        func firstProgress(after start: Double = 0, where condition: (ToyPose) -> Bool) -> Double? {
            zip(samples, poses).first { $0.0 >= start && condition($0.1) }?.0
        }
        func stage(_ name: String) throws -> Stage {
            try #require(stages.first { $0.name == name })
        }
        let railTop = Dimensions.Sword.railHeight + Dimensions.Sword.wireRadius
        let railBottom = Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius

        // Ring 1 steps aside: it leaves the rails and ends standing up on its eye, along the sword.
        let oneLeaves = try #require(firstProgress { !Relations.isRoundTheRails(1, in: $0) })
        #expect(try stage("Ring 1 steps aside").contains(oneLeaves), "ring 1 leaves the rails at \(oneLeaves)")
        let aside = motion.pose(at: try stage("Ring 1 steps aside").end)
        #expect(aside.ring(1).position.y > aside.rod(1).position.y + Dimensions.Ring.radius - 1e-6, "ring 1 stands on its eye")
        #expect(abs(aside.ring(1).worldDirection(SIMD3(0, 0, 1)).z) > 0.999, "ring 1 stands along the sword")
        #expect(Relations.isRoundTheRails(2, in: aside))
        // Ring 2 over the tip: ring 2 leaves the rails.
        let twoLeaves = try #require(firstProgress { !Relations.isRoundTheRails(2, in: $0) })
        #expect(try stage("Ring 2 over the tip").contains(twoLeaves), "ring 2 leaves the rails at \(twoLeaves)")
        // Down through the slot: ring 2's eye goes down into the slot, and the whole ring passes below the rails.
        let eyeIn = try #require(firstProgress { $0.rod(2).position.y - Dimensions.Rod.eyeRadius - Dimensions.Rod.wireRadius < railTop })
        #expect(try stage("Down through the slot").contains(eyeIn), "ring 2's eye goes into the slot at \(eyeIn)")
        let below = try #require(firstProgress { pose in
            Relations.loop(pose.ring(2).circle, pieces: 90).allSatisfy { $0.y + Dimensions.Ring.wireRadius < railBottom }
        })
        #expect(try stage("Down through the slot").contains(below), "ring 2 is below the rails at \(below)")
        // Ring 2 hangs: its eye sinks below the rails, so its rod is out of the slot.
        let eyeBelow = try #require(firstProgress { $0.rod(2).position.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius < railBottom })
        #expect(try stage("Ring 2 hangs").contains(eyeBelow), "ring 2's eye is below the rails at \(eyeBelow)")
        #expect(eyeIn < below && below < eyeBelow)
        // Ring 1 back on: ring 1 goes round the rails again.
        let oneBack = try #require(firstProgress(after: oneLeaves) { Relations.isRoundTheRails(1, in: $0) })
        #expect(try stage("Ring 1 back on").contains(oneBack), "ring 1 is back on at \(oneBack)")
        print("stages: ring 1 leaves the rails at \(oneLeaves), ring 2 leaves at \(twoLeaves), its eye into the slot at \(eyeIn), the ring below the rails at \(below), the eye below the rails at \(eyeBelow), ring 1 back on at \(oneBack)")
    }

    @Test func goingOnNamesTheStagesForWhatHappens() throws {
        let motion = try #require(MoveMotion(ringTwoOn))
        #expect(motion.stages.map(\.name) == ["Ring 1 steps aside", "Ring 2 lifts", "Up through the slot", "Ring 2 over the tip", "Ring 1 back on"])
        #expect(motion.stage(at: 0).name == "Ring 1 steps aside")
        #expect(motion.stage(at: 1).name == "Ring 1 back on")
    }

    @Test func theWrittenMovesAreRingsOneTwoAndThree() {
        #expect(MoveMotion.written == [ringOneOff, ringTwoOff, ringThreeOff])
        #expect(MoveMotion.written.allSatisfy { MoveMotion($0) != nil && MoveMotion($0.reversed) != nil })
    }
}
