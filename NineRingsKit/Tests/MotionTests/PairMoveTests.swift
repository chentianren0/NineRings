import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// A state written ring 1 first, `1` for on.
func state(_ text: String) -> PuzzleState {
    guard let state = PuzzleState(text) else { preconditionFailure("not a state: \(text)") }
    return state
}

/// Ring 2 coming off every ring on, and going back on: the second ring's move for ring 2.
let ringTwoOff = Move(ring: 2, from: .allOn)!
let ringTwoOn = ringTwoOff.reversed
let ringTwoOffState = PuzzleState.allOn.moving(2)

/// The moves checked here in full, both ways: ring 3 with ring 1 off in front; the same move for ring 2 with nothing
/// in front and for ring 9 with seven off rings in front; ring 3 and ring 2 with the rings behind on, off and mixed;
/// and ring 1 with ring 2 off behind it.
let pairMoveCases: [Move] = [
    Move(ring: 3, from: state("011111111"))!,
    Move(ring: 2, from: state("111111111"))!,
    Move(ring: 9, from: state("000000011"))!,
    Move(ring: 3, from: state("011011111"))!,
    Move(ring: 3, from: state("011000000"))!,
    Move(ring: 2, from: state("110111111"))!,
    Move(ring: 1, from: state("101111111"))!,
]

@Suite struct PairMoveTests {
    static let bothWays = pairMoveCases.flatMap { [$0, $0.reversed] }

    @Test(arguments: bothWays)
    func nothingPassesThroughAnythingAndNothingJumps(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let sweep = Sweep(motion)
        let smallest = sweep.smallestGap
        let step = sweep.largestStep
        let label = "ring \(move.ring) \(move.takesOff ? "off" : "on") from \(move.from)"
        print("\(label): smallest gap \(smallest.gap) at progress \(smallest.progress)")
        print("\(label): largest step \(String(format: "%.4f", step.distance)) mm, \(step.part), at progress \(step.progress)")
        #expect(smallest.gap.distance >= smallestAllowedGap)
        #expect(step.distance <= largestAllowedStep)
        // For the record: the smallest gap other than the beads resting a hair under the bar, and the smallest round
        // the rings in front of the moving one, with their rods.
        let front = Set((1..<move.ring).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] })
        let records = Sweep.inParallel(sweep.poses.count) { index -> (Gap, Gap?) in
            let shapes = sweep.poses[index].shapes.filter { $0.name != .bar }
            return (Gaps.smallest(in: shapes)!, front.isEmpty ? nil : Gaps.smallest(in: shapes, reach: 30, involving: front))
        }
        let others = records.indices.min { records[$0].0.distance < records[$1].0.distance }!
        print("\(label): smallest gap leaving out the bar \(records[others].0) at progress \(sweep.progress[others])")
        if !front.isEmpty {
            let round = records.indices.min { records[$0].1!.distance < records[$1].1!.distance }!
            print("\(label): smallest gap round the rings in front \(records[round].1!) at progress \(sweep.progress[round])")
        }
        if let failure = sweep.firstRelationFailure {
            Issue.record("at progress \(failure.progress): \(failure.failures.joined(separator: "; "))")
        }
    }

    @Test(arguments: pairMoveCases)
    func theEndsAreTheRestPosesAndGoingOnIsComingOffBackwards(_ off: Move) throws {
        let comingOff = try #require(MoveMotion(off))
        let goingOn = try #require(MoveMotion(off.reversed))
        #expect(Relations.isClose(comingOff.pose(at: 0), try #require(RestPoses.pose(for: off.from))))
        #expect(Relations.isClose(comingOff.pose(at: 1), try #require(RestPoses.pose(for: off.to))))
        for index in 0...200 {
            let progress = Double(index) / 200
            #expect(Relations.isClose(comingOff.pose(at: progress), goingOn.pose(at: 1 - progress)))
        }
    }

    /// Every ring in front of the one that moves, ring k−1 included, keeps exactly still with its rod: the rings that
    /// are off in front do nothing at all. Every ring behind, on or off, moves only straight down and up with the
    /// sword, by exactly its height. The bar never moves.
    @Test(arguments: pairMoveCases.filter { $0.ring >= 2 })
    func theRingsInFrontKeepStillAndTheRingsBehindRideWithTheSword(_ off: Move) throws {
        let motion = try #require(MoveMotion(off))
        let rest = try #require(RestPoses.pose(for: off.from))
        var lowest = 0.0
        for index in 0...4000 {
            let pose = motion.pose(at: Double(index) / 4000)
            #expect(pose.bar == rest.bar)
            for ring in 1..<off.ring {
                #expect(pose.ring(ring) == rest.ring(ring) && pose.rod(ring) == rest.rod(ring), "ring \(ring) moved at sample \(index)")
            }
            let down = SIMD3(0, pose.swordHeight, 0)
            for ring in PuzzleState.rings where ring > off.ring {
                #expect(Relations.isClose(PartPose(position: rest.ring(ring).position + down, orientation: rest.ring(ring).orientation), pose.ring(ring)), "ring \(ring) at sample \(index)")
                #expect(Relations.isClose(PartPose(position: rest.rod(ring).position + down, orientation: rest.rod(ring).orientation), pose.rod(ring)), "rod \(ring) at sample \(index)")
            }
            lowest = min(lowest, pose.swordHeight)
        }
        #expect(abs(lowest + PairMoveOff.drop) < 1e-9)
    }

    /// Ring 1's move is the same whatever is behind it: every other ring and rod keeps exactly still.
    @Test func ringOneComesOffWhateverIsBehindIt() throws {
        let off = try #require(Move(ring: 1, from: state("101111111")))
        let motion = try #require(MoveMotion(off))
        let rest = try #require(RestPoses.pose(for: off.from))
        let allOn = try #require(MoveMotion(Move(ring: 1, from: .allOn)!))
        for index in 0...4000 {
            let progress = Double(index) / 4000
            let pose = motion.pose(at: progress)
            for ring in 2...9 {
                #expect(pose.ring(ring) == rest.ring(ring) && pose.rod(ring) == rest.rod(ring), "ring \(ring) moved at sample \(index)")
            }
            // Ring 1 and the sword go exactly as they do with every ring on.
            #expect(pose.ring(1) == allOn.pose(at: progress).ring(1) && pose.swordOffset == allOn.pose(at: progress).swordOffset)
        }
    }

    /// The same move for every ring: ring k's path is ring 2's, one hole further along for each ring after ring 2,
    /// moving ring, sword and all.
    @Test func theMoveIsTheSameForEveryRingOneHoleFurtherAlong() throws {
        let two = try #require(MoveMotion(Move(ring: 2, from: .allOn)!))
        for ring in 3...9 {
            let motion = try #require(MoveMotion(Move(ring: ring, from: PairMoveOff.firstPlace(ring))!))
            let shift = SIMD3(Dimensions.Bar.holePitch * Double(ring - 2), 0, 0)
            // The pacing differs by how far the sword slides from home, so compare along the path's own parameter.
            for index in 1..<400 {
                let parameter = Double(index) / 400
                let base = PairMoveOff.paced[0].path.pose(at: parameter)
                let here = PairMoveOff.paced[ring - 2].path.pose(at: parameter)
                #expect(Relations.isClose(PartPose(position: base.ring(2).position + shift, orientation: base.ring(2).orientation), here.ring(ring), tolerance: 1e-9))
                // The sword's offset moves along too, between the keys next to home at either end.
                if parameter >= 0.20 && parameter <= 0.90 {
                    #expect(abs(here.swordSlide - base.swordSlide - shift.x) < 1e-9 && here.swordHeight == base.swordHeight)
                }
            }
            #expect(motion.stages.map(\.name) == two.stages.map(\.name).map { $0.replacingOccurrences(of: "Ring 2", with: "Ring \(ring)") })
        }
    }

    /// The sword leaves ring k−1 and comes back into it once each, over the tip end; ring k leaves the rails once,
    /// over the tip end, while the sword is out of ring k−1.
    @Test(arguments: pairMoveCases.filter { $0.ring >= 2 })
    func theSwordLeavesTheRingInFrontOnceAndTheRingLeavesWhileItIsOut(_ off: Move) throws {
        let motion = try #require(MoveMotion(off))
        let samples = (0...4000).map { Double($0) / 4000 }
        let poses = samples.map(motion.pose(at:))
        func changes(_ ring: Int) -> [Double] {
            let round = poses.map { Relations.isRoundTheRails(ring, in: $0) }
            return zip(round, round.dropFirst()).enumerated().filter { $0.element.0 != $0.element.1 }.map { samples[$0.offset + 1] }
        }
        let front = changes(off.ring - 1), moving = changes(off.ring)
        #expect(front.count == 2 && moving.count == 1)
        if front.count == 2, let leaves = moving.first { #expect(front[0] < leaves && leaves < front[1]) }
        for ring in PuzzleState.rings where ring != off.ring && ring != off.ring - 1 {
            #expect(changes(ring).isEmpty, "ring \(ring) changed")
        }
    }

    @Test(arguments: [2, 3, 9])
    func theStagesComeInOrderAndEachDoesWhatItsNameSays(_ ring: Int) throws {
        let motion = try #require(MoveMotion(Move(ring: ring, from: PairMoveOff.firstPlace(ring))!))
        let stages = motion.stages
        #expect(stages.map(\.name) == ["Sword moves away", "Ring \(ring) over the tip", "Down through the slot", "Ring \(ring) hangs", "Sword comes back"])
        #expect(stages.first?.start == 0 && stages.last?.end == 1)
        #expect(zip(stages, stages.dropFirst()).allSatisfy { $0.end == $1.start && $0.start < $0.end })
        func stage(_ name: String) throws -> Stage { try #require(stages.first { $0.name == name }) }

        let samples = (0...2000).map { Double($0) / 2000 }
        let poses = samples.map(motion.pose(at:))
        func firstProgress(after start: Double = 0, where condition: (ToyPose) -> Bool) -> Double? {
            zip(samples, poses).first { $0.0 >= start && condition($0.1) }?.0
        }
        func railTop(_ pose: ToyPose) -> Double { pose.swordHeight + Dimensions.Sword.railHeight + Dimensions.Sword.wireRadius }
        func railBottom(_ pose: ToyPose) -> Double { pose.swordHeight + Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius }
        let eyeReach = Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius

        // The sword moves away: it leaves ring k−1 and reaches the bottom of its drop.
        let frontLeaves = try #require(firstProgress { !Relations.isRoundTheRails(ring - 1, in: $0) })
        #expect(try stage("Sword moves away").contains(frontLeaves), "the sword leaves ring \(ring - 1) at \(frontLeaves)")
        let away = motion.pose(at: try stage("Sword moves away").end)
        #expect(abs(away.swordHeight + PairMoveOff.drop) < 1e-9 && Relations.isRoundTheRails(ring, in: away))
        // Ring k over the tip.
        let leaves = try #require(firstProgress { !Relations.isRoundTheRails(ring, in: $0) })
        #expect(try stage("Ring \(ring) over the tip").contains(leaves), "ring \(ring) leaves the rails at \(leaves)")
        // Down through the slot: its eye goes down into the slot, and the whole ring passes below the rails.
        let eyeIn = try #require(firstProgress { $0.rod(ring).position.y - eyeReach < railTop($0) })
        #expect(try stage("Down through the slot").contains(eyeIn), "ring \(ring)'s eye goes into the slot at \(eyeIn)")
        let below = try #require(firstProgress { pose in
            Relations.loop(pose.ring(ring).circle, pieces: 90).allSatisfy { $0.y + Dimensions.Ring.wireRadius < railBottom(pose) }
        })
        #expect(try stage("Down through the slot").contains(below), "ring \(ring) is below the rails at \(below)")
        // Ring k hangs: its eye sinks below the rails, so its rod is out of the slot.
        let eyeBelow = try #require(firstProgress { $0.rod(ring).position.y + eyeReach < railBottom($0) })
        #expect(try stage("Ring \(ring) hangs").contains(eyeBelow), "ring \(ring)'s eye is below the rails at \(eyeBelow)")
        #expect(eyeIn < below && below < eyeBelow)
        // The sword comes back: it enters ring k−1 again and is home.
        let frontBack = try #require(firstProgress(after: frontLeaves) { Relations.isRoundTheRails(ring - 1, in: $0) })
        #expect(try stage("Sword comes back").contains(frontBack), "the sword is back in ring \(ring - 1) at \(frontBack)")
        print("ring \(ring) stages: the sword leaves ring \(ring - 1) at \(frontLeaves), ring \(ring) leaves at \(leaves), its eye into the slot at \(eyeIn), the ring below the rails at \(below), the eye below the rails at \(eyeBelow), the sword back in ring \(ring - 1) at \(frontBack)")
    }

    @Test func goingOnNamesTheStagesForWhatHappens() throws {
        let motion = try #require(MoveMotion(Move(ring: 4, from: state("001011111"))!))
        #expect(motion.stages.map(\.name) == ["Sword moves away", "Ring 4 lifts", "Up through the slot", "Ring 4 over the tip", "Sword comes back"])
    }

    @Test func theWrittenMovesAreOneForEachRingWhereItFirstComesOff() {
        #expect(MoveMotion.written.map(\.ring) == Array(1...9))
        #expect(MoveMotion.written.map(\.from) == [.allOn, .allOn] + (3...9).map { PairMoveOff.firstPlace($0) })
        #expect(MoveMotion.written.allSatisfy { $0.takesOff && MoveMotion($0) != nil && MoveMotion($0.reversed) != nil })
        #expect(PairMoveOff.firstPlace(3) == state("011111111") && PairMoveOff.firstPlace(9) == state("000000011"))
    }
}
