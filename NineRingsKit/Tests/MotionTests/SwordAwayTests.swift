import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Ring 2 coming off the second way, the sword moving away while ring 1 keeps still (``SwordAwayTrial``), checked
/// as every written move is: both ways, 4000 samples each.
@Suite struct SwordAwayRingTwoTests {
    static let off = SwordAwayTrial.move
    static let on = off.reversed

    static func pose(_ move: Move, _ progress: Double) -> ToyPose {
        SwordAwayTrial.pose(at: move.takesOff ? progress : 1 - progress)
    }

    @Test(arguments: [off, on])
    func nothingPassesThroughAnythingAndNothingJumps(_ move: Move) throws {
        let sweep = Sweep(move) { Self.pose(move, $0) }
        let smallest = sweep.smallestGap
        let step = sweep.largestStep
        let direction = move.takesOff ? "off" : "on"
        print("sword away, ring 2 \(direction): smallest gap \(smallest.gap) at progress \(smallest.progress)")
        print("sword away, ring 2 \(direction): largest step \(String(format: "%.4f", step.distance)) mm, \(step.part), at progress \(step.progress)")
        #expect(smallest.gap.distance >= smallestAllowedGap)
        #expect(step.distance <= largestAllowedStep)
        // For the record: the smallest gap other than the beads resting a hair under the bar, and the smallest
        // round ring 1 and its rod, which keep still.
        let still: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1)]
        let records = Sweep.inParallel(sweep.poses.count) { index -> (Gap, Gap) in
            let shapes = sweep.poses[index].shapes.filter { $0.name != .bar }
            return (Gaps.smallest(in: shapes)!, Gaps.smallest(in: shapes, reach: 30, involving: still)!)
        }
        let others = records.indices.min { records[$0].0.distance < records[$1].0.distance }!
        let round = records.indices.min { records[$0].1.distance < records[$1].1.distance }!
        print("sword away, ring 2 \(direction): smallest gap leaving out the bar \(records[others].0) at progress \(sweep.progress[others])")
        print("sword away, ring 2 \(direction): smallest gap round ring 1 \(records[round].1) at progress \(sweep.progress[round])")
        if let failure = sweep.firstRelationFailure {
            Issue.record("at progress \(failure.progress): \(failure.failures.joined(separator: "; "))")
        }
    }

    @Test func theEndsAreTheRestPosesAndGoingOnIsComingOffBackwards() throws {
        #expect(Relations.isClose(Self.pose(Self.off, 0), try #require(RestPoses.pose(for: .allOn))))
        #expect(Relations.isClose(Self.pose(Self.off, 1), try #require(RestPoses.pose(for: PuzzleState.allOn.moving(2)))))
        for index in 0...200 {
            let progress = Double(index) / 200
            #expect(Relations.isClose(Self.pose(Self.off, progress), Self.pose(Self.on, 1 - progress)))
        }
    }

    /// Ring 1, its rod and the bar never move. Rings 3 to 9 and their rods move only straight down and up, with
    /// the sword, by exactly its height.
    @Test func ringOneKeepsStillAndTheRingsBehindRideWithTheSword() throws {
        let rest = try #require(RestPoses.pose(for: .allOn))
        var lowest = 0.0
        for index in 0...4000 {
            let pose = Self.pose(Self.off, Double(index) / 4000)
            #expect(pose.ring(1) == rest.ring(1) && pose.rod(1) == rest.rod(1), "ring 1 moved at sample \(index)")
            #expect(pose.bar == rest.bar)
            let down = SIMD3(0, pose.swordHeight, 0)
            for ring in 3...9 {
                #expect(Relations.isClose(PartPose(position: rest.ring(ring).position + down, orientation: rest.ring(ring).orientation), pose.ring(ring)), "ring \(ring) at sample \(index)")
                #expect(Relations.isClose(PartPose(position: rest.rod(ring).position + down, orientation: rest.rod(ring).orientation), pose.rod(ring)), "rod \(ring) at sample \(index)")
            }
            lowest = min(lowest, pose.swordHeight)
        }
        print("sword away: the sword goes down \(String(format: "%.3f", -lowest)) mm")
        #expect(abs(lowest + SwordAwayOff.drop) < 1e-9)
    }

    /// The sword leaves ring 1 and comes back into it once each, over the tip end; ring 2 leaves the rails once,
    /// over the tip end, while the sword is out of ring 1. The checker's relations already require every change
    /// to be over the tip end.
    @Test func theSwordLeavesRingOneOnceAndRingTwoLeavesWhileItIsOut() throws {
        let samples = (0...4000).map { Double($0) / 4000 }
        let poses = samples.map { Self.pose(Self.off, $0) }
        func changes(_ ring: Int) -> [Double] {
            let round = poses.map { Relations.isRoundTheRails(ring, in: $0) }
            return zip(round, round.dropFirst()).enumerated().filter { $0.element.0 != $0.element.1 }.map { samples[$0.offset + 1] }
        }
        let one = changes(1), two = changes(2)
        print("sword away: the sword leaves and enters ring 1 at \(one), ring 2 leaves the rails at \(two)")
        #expect(one.count == 2 && two.count == 1)
        if one.count == 2, let leaves = two.first { #expect(one[0] < leaves && leaves < one[1]) }
    }

    @Test func theStagesComeInOrderAndEachDoesWhatItsNameSays() throws {
        let stages = SwordAwayTrial.stages
        #expect(stages.map(\.name) == ["Sword moves away", "Ring 2 over the tip", "Down through the slot", "Ring 2 hangs", "Sword comes back"])
        #expect(stages.first?.start == 0 && stages.last?.end == 1)
        #expect(zip(stages, stages.dropFirst()).allSatisfy { $0.end == $1.start && $0.start < $0.end })
        func stage(_ name: String) throws -> Stage { try #require(stages.first { $0.name == name }) }

        let samples = (0...2000).map { Double($0) / 2000 }
        let poses = samples.map { Self.pose(Self.off, $0) }
        func firstProgress(after start: Double = 0, where condition: (ToyPose) -> Bool) -> Double? {
            zip(samples, poses).first { $0.0 >= start && condition($0.1) }?.0
        }
        // Heights in the sword's frame: the rails' top and bottom, wherever the sword is.
        func railTop(_ pose: ToyPose) -> Double { pose.swordHeight + Dimensions.Sword.railHeight + Dimensions.Sword.wireRadius }
        func railBottom(_ pose: ToyPose) -> Double { pose.swordHeight + Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius }
        let eyeReach = Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius

        // The sword moves away: it leaves ring 1 and reaches the bottom of its drop.
        let oneLeaves = try #require(firstProgress { !Relations.isRoundTheRails(1, in: $0) })
        #expect(try stage("Sword moves away").contains(oneLeaves), "the sword leaves ring 1 at \(oneLeaves)")
        let away = Self.pose(Self.off, try stage("Sword moves away").end)
        #expect(abs(away.swordHeight + SwordAwayOff.drop) < 1e-9 && Relations.isRoundTheRails(2, in: away))
        // Ring 2 over the tip.
        let twoLeaves = try #require(firstProgress { !Relations.isRoundTheRails(2, in: $0) })
        #expect(try stage("Ring 2 over the tip").contains(twoLeaves), "ring 2 leaves the rails at \(twoLeaves)")
        // Down through the slot: its eye goes down into the slot, and the whole ring passes below the rails.
        let eyeIn = try #require(firstProgress { $0.rod(2).position.y - eyeReach < railTop($0) })
        #expect(try stage("Down through the slot").contains(eyeIn), "ring 2's eye goes into the slot at \(eyeIn)")
        let below = try #require(firstProgress { pose in
            Relations.loop(pose.ring(2).circle, pieces: 90).allSatisfy { $0.y + Dimensions.Ring.wireRadius < railBottom(pose) }
        })
        #expect(try stage("Down through the slot").contains(below), "ring 2 is below the rails at \(below)")
        // Ring 2 hangs: its eye sinks below the rails, so its rod is out of the slot.
        let eyeBelow = try #require(firstProgress { $0.rod(2).position.y + eyeReach < railBottom($0) })
        #expect(try stage("Ring 2 hangs").contains(eyeBelow), "ring 2's eye is below the rails at \(eyeBelow)")
        #expect(eyeIn < below && below < eyeBelow)
        // The sword comes back: it enters ring 1 again and is home.
        let oneBack = try #require(firstProgress(after: oneLeaves) { Relations.isRoundTheRails(1, in: $0) })
        #expect(try stage("Sword comes back").contains(oneBack), "the sword is back in ring 1 at \(oneBack)")
        print("sword away stages: the sword leaves ring 1 at \(oneLeaves), ring 2 leaves at \(twoLeaves), its eye into the slot at \(eyeIn), the ring below the rails at \(below), the eye below the rails at \(eyeBelow), the sword back in ring 1 at \(oneBack)")
    }

    @Test func positionAndVelocityAreContinuousAndTheMoveDoesNotStopBetweenStages() throws {
        let pose = { (progress: Double) in Self.pose(Self.off, progress) }
        let coarse = SmoothnessTests.largestBend(pose, step: 1e-3)
        let fine = SmoothnessTests.largestBend(pose, step: 1e-4)
        print("sword away smoothness: largest bend \(coarse) at a step of 1e-3, \(fine) at 1e-4")
        #expect(fine < 1.5 * coarse)
        for end in [0.0, 1.0] {
            let speed = zip(numbers(pose(end)), numbers(pose(end == 0 ? 1e-6 : 1 - 1e-6))).map { abs($0 - $1) / 1e-6 }.max() ?? 0
            #expect(speed < 0.01, "speed \(speed) at progress \(end)")
        }
        for stage in SwordAwayTrial.stages.dropFirst() {
            let speed = zip(numbers(pose(stage.start)), numbers(pose(stage.start + 1e-4))).map { abs($0 - $1) / 1e-4 }.max() ?? 0
            print("sword away: speed at the start of \(stage.name): \(speed) mm per progress")
            #expect(speed > 10, "the motion stops at the start of \(stage.name)")
        }
    }
}

/// Why ring 3 cannot come off the same way, one hole along. With ring 1 off, ring 1 hangs from ring 2 and rod 1
/// stands under the sword, 30 mm in front of ring 3's eye, reaching down through the bar. The tip can never pass
/// it, at any height, so with the sword down there is at most 30 − 2.15 = 27.85 mm of slot in front of ring 3's
/// eye. Ring 2's drop, as written, needs the tip at 16.5 mm or less, 30.5 mm in front of its eye.
@Suite struct RingThreeCannotGoTheSameWayTests {
    static let from = PuzzleState.allOn.moving(1)

    static func smallestGap(_ path: SwordAwayOff, involving parts: Set<PartName>, samples: Int = 600) -> Gap {
        let paced = SwordAwayOff.Paced(path)
        let gaps = Sweep.inParallel(samples) { index in
            Gaps.smallest(in: paced.pose(atProgress: Double(index) / Double(samples - 1)).shapes.filter { $0.name != .bar }, reach: 30, involving: parts)!
        }
        return gaps.min { $0.distance < $1.distance }!
    }

    @Test func theTipCannotPassRodOneAndRingThreesDropDoesNotFitBehindIt() {
        let drop = SwordAwayOff.drop
        // One hole along, as it is: the tip, slid forward for the drop, runs into rod 1.
        let same = SwordAwayOff(ring: 3, from: Self.from, keys: SwordAwayOff.keys(drop: drop, dip: SwordAwayOff.dip))
        let rod = Self.smallestGap(same, involving: [.shaft(1)])
        print("ring 3 one hole along: \(rod)")
        #expect(rod.distance < -1)
        // With the tip held 2.15 mm behind rod 1 for the drop (19.15 mm for ring 2, so 34.15 mm), ring 3 meets it.
        let behind = SwordAwayOff(ring: 3, from: Self.from, keys: SwordAwayOff.keys(drop: drop, dip: 3, asideSlide: 23.2, dropSlide: 19.15))
        let ring = Self.smallestGap(behind, involving: [.ring(3)])
        print("ring 3 with the tip behind rod 1: \(ring)")
        #expect(ring.distance < -1)
        // Ring 2's own drop has room only with the tip at 16.5 mm or less.
        for (dropSlide, clear) in [(16.5, true), (17.0, false)] {
            let path = SwordAwayOff(ring: 2, from: .allOn, keys: SwordAwayOff.keys(drop: drop, dip: SwordAwayOff.dip, dropSlide: dropSlide))
            let gap = Self.smallestGap(path, involving: [.ring(2)])
            print("ring 2 with the tip at \(dropSlide) mm for the drop: \(gap)")
            #expect((gap.distance >= smallestAllowedGap) == clear)
        }
    }
}
