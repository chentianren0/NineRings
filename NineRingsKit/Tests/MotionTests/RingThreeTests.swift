import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

let ringOneOffState = PuzzleState.allOn.moving(1)
let ringThreeOff = Move(ring: 3, from: ringOneOffState)!
let ringThreeOn = ringThreeOff.reversed
let ringThreeOffState = ringOneOffState.moving(3)

@Suite struct RingThreeRestTests {
    @Test func ringsOneAndThreeOffRestClearAndReadAsTheirState() throws {
        let pose = try #require(RestPoses.pose(for: ringThreeOffState))
        let gap = try #require(Gaps.smallest(in: pose.shapes))
        print("rest \(ringThreeOffState): smallest gap \(gap)")
        #expect(gap.distance >= smallestAllowedGap, "\(gap)")
        let failures = Relations.failures(in: pose, mayBeOff: [1, 3])
        #expect(failures.isEmpty, "\(failures)")
        #expect(pose.ringsOnTheSword == ringThreeOffState)
        for ring in PuzzleState.rings {
            #expect(Relations.isRoundTheRails(ring, in: pose) == ringThreeOffState.isOn(ring), "ring \(ring)")
        }
    }

    /// Ring 3 off hangs as ring 1 off does, two holes further on, with rod 2 down through it; ring 1 hangs as it did.
    @Test func ringThreeHangsAsRingOneDoesTwoHolesOn() throws {
        let one = try #require(RestPoses.pose(for: ringOneOffState))
        let three = try #require(RestPoses.pose(for: ringThreeOffState))
        let pitch = SIMD3(2 * Dimensions.Bar.holePitch, 0, 0)
        #expect(Relations.isClose(PartPose(position: one.ring(1).position + pitch, orientation: one.ring(1).orientation), three.ring(3)))
        #expect(Relations.isClose(PartPose(position: one.rod(1).position + pitch, orientation: one.rod(1).orientation), three.rod(3)))
        #expect(Relations.isClose(one.ring(1), three.ring(1)) && Relations.isClose(one.rod(1), three.rod(1)))
        #expect(Relations.crossings(of: Relations.threadPath(of: three.rod(2)), through: three.ring(3).circle).count == 1)
    }
}

@Suite struct RingThreeMoveTests {
    @Test(arguments: [ringThreeOff, ringThreeOn])
    func nothingPassesThroughAnythingAndNothingJumps(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let sweep = Sweep(motion)
        let smallest = sweep.smallestGap
        let step = sweep.largestStep
        let direction = move.takesOff ? "off" : "on"
        print("ring 3 \(direction): smallest gap \(smallest.gap) at progress \(smallest.progress)")
        print("ring 3 \(direction): largest step \(String(format: "%.4f", step.distance)) mm, \(step.part), at progress \(step.progress)")
        #expect(smallest.gap.distance >= smallestAllowedGap)
        #expect(step.distance <= largestAllowedStep)
        // For the record: the largest lean of a rod from upright, and the smallest gap of a part the move moves.
        let lean = sweep.poses.map { pose in
            (1...9).map { acos(min(1, pose.rod($0).worldDirection(SIMD3(0, 1, 0)).y)) * 180 / .pi }.max()!
        }.max()!
        print("ring 3 \(direction): largest lean of a rod \(String(format: "%.3f", lean))°")
        let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2), .bead(2), .ring(3), .eye(3), .shaft(3), .bead(3)]
        let records = Sweep.inParallel(sweep.poses.count) { index in Gaps.smallest(in: sweep.poses[index].shapes, involving: moving)! }
        let moved = records.indices.min { records[$0].distance < records[$1].distance }!
        print("ring 3 \(direction): smallest gap of a moving part \(records[moved]) at progress \(sweep.progress[moved])")
        if let failure = sweep.firstRelationFailure {
            Issue.record("at progress \(failure.progress): \(failure.failures.joined(separator: "; "))")
        }
    }

    @Test(arguments: [ringThreeOff, ringThreeOn])
    func theEndsAreTheRestPoses(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let before = try #require(RestPoses.pose(for: move.from))
        let after = try #require(RestPoses.pose(for: move.to))
        #expect(Relations.isClose(motion.pose(at: 0), before))
        #expect(Relations.isClose(motion.pose(at: 1), after))
    }

    @Test func goingOnIsComingOffBackwards() throws {
        let off = try #require(MoveMotion(ringThreeOff))
        let on = try #require(MoveMotion(ringThreeOn))
        for index in 0...200 {
            let progress = Double(index) / 200
            #expect(Relations.isClose(off.pose(at: progress), on.pose(at: 1 - progress), tolerance: 1e-9))
        }
    }

    /// Rings 4 to 9 and their rods, and the bar, stay exactly where they rest.
    @Test func everyOtherPartStaysExactlyStill() throws {
        let motion = try #require(MoveMotion(ringThreeOff))
        let rest = try #require(RestPoses.pose(for: ringOneOffState))
        for index in 0...4000 {
            let pose = motion.pose(at: Double(index) / 4000)
            for ring in 4...9 {
                #expect(pose.ring(ring) == rest.ring(ring), "ring \(ring) moved at sample \(index)")
                #expect(pose.rod(ring) == rest.rod(ring), "rod \(ring) moved at sample \(index)")
            }
            #expect(pose.bar == rest.bar)
            // Ring 2's eye never moves: rod 2 stays down through the slot and through ring 3.
            #expect(pose.rod(2).position == rest.rod(2).position)
        }
    }

    /// Ring 1 never goes round the rails; ring 2 leaves them over the tip end and joins them again once; ring 3
    /// leaves them once, after ring 2 has left and before it comes back.
    @Test func ringsTwoAndThreeLeaveAndJoinTheRailsOnlyOverTheTipEnd() throws {
        let motion = try #require(MoveMotion(ringThreeOff))
        let samples = 4000
        var changes: [Int: [Double]] = [1: [], 2: [], 3: []]
        for ring in [1, 2, 3] {
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
        print("rails: ring 2 leaves and joins at \(changes[2]!), ring 3 leaves at \(changes[3]!)")
        #expect(changes[1]!.isEmpty)
        #expect(changes[2]!.count == 2)
        #expect(changes[3]!.count == 1)
        if changes[2]!.count == 2, let leaves = changes[3]!.first {
            #expect(changes[2]![0] < leaves && leaves < changes[2]![1])
        }
    }

    @Test func theStagesComeInOrderAndEachDoesWhatItsNameSays() throws {
        let motion = try #require(MoveMotion(ringThreeOff))
        let stages = motion.stages
        #expect(stages.map(\.name) == ["Ring 2 steps aside", "Ring 3 over the tip", "Down through the slot", "Ring 3 hangs", "Ring 2 back on"])
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

        // Ring 2 steps aside: it leaves the rails, and ring 1 ends lifted with its eye above ring 2's eye.
        let twoLeaves = try #require(firstProgress { !Relations.isRoundTheRails(2, in: $0) })
        #expect(try stage("Ring 2 steps aside").contains(twoLeaves), "ring 2 leaves the rails at \(twoLeaves)")
        let aside = motion.pose(at: try stage("Ring 2 steps aside").end)
        #expect(aside.rod(1).position.y > aside.rod(2).position.y, "ring 1 is lifted above ring 2")
        #expect(Relations.isRoundTheRails(3, in: aside))
        // Ring 3 over the tip: ring 3 leaves the rails.
        let threeLeaves = try #require(firstProgress { !Relations.isRoundTheRails(3, in: $0) })
        #expect(try stage("Ring 3 over the tip").contains(threeLeaves), "ring 3 leaves the rails at \(threeLeaves)")
        // Down through the slot: ring 3's eye goes down into the slot, and the whole ring passes below the rails.
        let eyeIn = try #require(firstProgress { $0.rod(3).position.y - Dimensions.Rod.eyeRadius - Dimensions.Rod.wireRadius < railTop })
        #expect(try stage("Down through the slot").contains(eyeIn), "ring 3's eye goes into the slot at \(eyeIn)")
        let below = try #require(firstProgress { pose in
            Relations.loop(pose.ring(3).circle, pieces: 90).allSatisfy { $0.y + Dimensions.Ring.wireRadius < railBottom }
        })
        #expect(try stage("Down through the slot").contains(below), "ring 3 is below the rails at \(below)")
        // Ring 3 hangs: its eye sinks below the rails, so its rod is out of the slot.
        let eyeBelow = try #require(firstProgress { $0.rod(3).position.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius < railBottom })
        #expect(try stage("Ring 3 hangs").contains(eyeBelow), "ring 3's eye is below the rails at \(eyeBelow)")
        #expect(eyeIn < below && below < eyeBelow)
        // Ring 2 back on: ring 2 goes round the rails again.
        let twoBack = try #require(firstProgress(after: twoLeaves) { Relations.isRoundTheRails(2, in: $0) })
        #expect(try stage("Ring 2 back on").contains(twoBack), "ring 2 is back on at \(twoBack)")
        print("stages: ring 2 leaves the rails at \(twoLeaves), ring 3 leaves at \(threeLeaves), its eye into the slot at \(eyeIn), the ring below the rails at \(below), the eye below the rails at \(eyeBelow), ring 2 back on at \(twoBack)")
    }

    @Test func goingOnNamesTheStagesForWhatHappens() throws {
        let motion = try #require(MoveMotion(ringThreeOn))
        #expect(motion.stages.map(\.name) == ["Ring 2 steps aside", "Ring 3 lifts", "Up through the slot", "Ring 3 over the tip", "Ring 2 back on"])
        #expect(motion.stage(at: 0).name == "Ring 2 steps aside")
        #expect(motion.stage(at: 1).name == "Ring 2 back on")
    }
}
