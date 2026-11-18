import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

/// The smallest gap the checker accepts between two parts that are not joined by design, in millimetres.
let smallestAllowedGap = 0.2
/// The most any point may move from one sample to the next, in millimetres.
let largestAllowedStep = 0.25

let ringOneOff = Move(ring: 1, from: .allOn)!
let ringOneOn = ringOneOff.reversed

extension MotionTests {
    @Suite struct RestTests {
        @Test(arguments: [PuzzleState.allOn, PuzzleState.allOn.moving(1)])
        func restsClearAndReadsAsItsState(_ state: PuzzleState) throws {
            let pose = RestPoses.pose(for: state)
            let gap = try #require(Gaps.smallest(in: pose.shapes))
            print("rest \(state): smallest gap \(gap)")
            #expect(gap.distance >= smallestAllowedGap, "\(gap)")
            #expect(Relations.failures(in: pose).isEmpty, "\(Relations.failures(in: pose))")
            #expect(pose.ringsOnTheSword == state)
            for ring in PuzzleState.rings {
                #expect(Relations.isRoundTheRails(ring, in: pose) == state.isOn(ring), "ring \(ring)")
            }
        }

        @Test func aRingThatIsOnRestsTheSameWayAtEveryHole() {
            let first = RestPoses.on(1)
            for ring in 2...9 {
                let held = RestPoses.on(ring)
                let pitch = SIMD3(Dimensions.Bar.holePitch * Double(ring - 1), 0, 0)
                #expect(simd_distance(held.eye, first.eye + pitch) < 1e-12)
                #expect(held.towardCenter == first.towardCenter && held.alongWire == first.alongWire)
            }
        }

        @Test func everyBeadOfARingThatIsOnRestsAHairUnderTheBar() throws {
            let pose = RestPoses.pose(for: .allOn)
            let barBottom = Layout.bar.position.y - Dimensions.Bar.thickness / 2
            for ring in PuzzleState.rings {
                let beadTop = pose.rod(ring).worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0)).y + Dimensions.Rod.beadRadius
                #expect(abs(barBottom - beadTop - Layout.restingGap) < 1e-9)
            }
        }

        @Test func ringOneOffHangsOnTheTipSideOfRingTwosLowerArc() throws {
            let pose = RestPoses.pose(for: PuzzleState.allOn.moving(1))
            let ringOne = pose.ring(1).circle
            let ringTwo = pose.ring(2).circle
            // Every point of ring 1 lies on the tip side of ring 2's plane.
            let towardTip = ringTwo.normal.x < 0 ? ringTwo.normal : -ringTwo.normal
            let sides = Relations.loop(ringOne).map { simd_dot($0 - ringTwo.center, towardTip) }
            #expect(sides.allSatisfy { $0 > 0 })
            #expect(!Relations.areLinked(ringOne, ringTwo))
            // Its eye is below the rails, so its rod is out of the slot, and its rod has slid down.
            let eyeTop = pose.rod(1).position.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius
            #expect(eyeTop < Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius)
            print("ring 1 off: its rod has slid \(Layout.eyeHeightOn - Layout.eyeHeightHanging) mm down")
        }
    }

    @Suite struct RingOneMoveTests {
        @Test(arguments: [ringOneOff, ringOneOn])
        func nothingPassesThroughAnythingAndNothingJumps(_ move: Move) throws {
            let motion = MoveMotion(move)
            let sweep = Sweep(motion)
            let smallest = sweep.smallestGap
            let step = sweep.largestStep
            print("ring 1 \(move.takesOff ? "off" : "on"): smallest gap \(smallest.gap) at progress \(smallest.progress)")
            print("ring 1 \(move.takesOff ? "off" : "on"): largest step \(String(format: "%.4f", step.distance)) mm, \(step.part), at progress \(step.progress)")
            #expect(smallest.gap.distance >= smallestAllowedGap)
            #expect(step.distance <= largestAllowedStep)
            // For the record: the smallest gap other than the beads resting a hair under the bar.
            let others = sweep.poses.enumerated().map { index, pose in
                (Gaps.smallest(in: pose.shapes.filter { $0.name != .bar })!, sweep.progress[index])
            }.min { $0.0.distance < $1.0.distance }!
            print("ring 1 \(move.takesOff ? "off" : "on"): smallest gap leaving out the bar \(others.0) at progress \(others.1)")
            if let failure = sweep.firstRelationFailure {
                Issue.record("at progress \(failure.progress): \(failure.failures.joined(separator: "; "))")
            }
        }

        @Test(arguments: [ringOneOff, ringOneOn])
        func theEndsAreTheRestPoses(_ move: Move) throws {
            let motion = MoveMotion(move)
            let before = RestPoses.pose(for: move.from)
            let after = RestPoses.pose(for: move.to)
            #expect(Relations.isClose(motion.pose(at: 0), before))
            #expect(Relations.isClose(motion.pose(at: 1), after))
        }

        @Test func goingOnIsComingOffBackwards() throws {
            let off = MoveMotion(ringOneOff)
            let on = MoveMotion(ringOneOn)
            for index in 0...200 {
                let progress = Double(index) / 200
                #expect(Relations.isClose(off.pose(at: progress), on.pose(at: 1 - progress), tolerance: 1e-9))
            }
        }

        /// A ring can leave the rails only by passing out over the tip end: the two places where the sword goes
        /// through it close in on each other round the tip and meet at its end.
        @Test func ringOneLeavesTheRailsOnlyOverTheTipEnd() throws {
            let motion = MoveMotion(ringOneOff)
            let samples = 4000
            var previous: (on: Bool, crossings: [SIMD3<Double>])?
            var changes = 0
            for index in 0...samples {
                let pose = motion.pose(at: Double(index) / Double(samples))
                let (near, far) = Relations.swordCrossings(of: 1, in: pose)
                let on = Relations.isRoundTheRails(1, in: pose)
                if let previous, previous.on != on {
                    changes += 1
                    // Just before it leaves, the sword goes through it only near the tip's end.
                    let last = previous.on ? previous.crossings : near + far
                    for crossing in last {
                        #expect(crossing.x < Dimensions.Sword.railOffset / 2, "the sword went through ring 1 at \(crossing) as it left")
                    }
                }
                previous = (on, near + far)
            }
            #expect(changes == 1)
        }

        @Test func theStagesComeInOrderAndEachDoesWhatItsNameSays() throws {
            let motion = MoveMotion(ringOneOff)
            let stages = motion.stages
            #expect(stages.map(\.name) == ["Flatten", "Over the tip", "Back over the slot", "Turn", "Down through the slot", "Hang"])
            #expect(stages.first?.start == 0 && stages.last?.end == 1)
            #expect(zip(stages, stages.dropFirst()).allSatisfy { $0.end == $1.start && $0.start < $0.end })

            let samples = (0...2000).map { Double($0) / 2000 }
            let poses = samples.map(motion.pose(at:))
            func firstProgress(where condition: (ToyPose) -> Bool) -> Double? {
                zip(samples, poses).first { condition($0.1) }?.0
            }
            func stage(_ name: String) throws -> Stage {
                try #require(stages.first { $0.name == name })
            }

            // Over the tip: ring 1 leaves the rails.
            let leaves = try #require(firstProgress { !Relations.isRoundTheRails(1, in: $0) })
            #expect(try stage("Over the tip").contains(leaves), "ring 1 leaves the rails at \(leaves)")
            // Flatten: by the time it leaves, the ring lies nearly flat.
            let flatAtLeaving = abs(motion.pose(at: leaves).ring(1).worldDirection(SIMD3(0, 0, 1)).y)
            #expect(flatAtLeaving > cos(30 * Double.pi / 180), "the ring's normal is \(acos(flatAtLeaving) * 180 / .pi) degrees from upright")
            // Back over the slot: the sword is home again before the turn.
            let slideEnds = samples.last { motion.pose(at: $0).swordSlide > Layout.swordHome + 1e-6 } ?? 0
            #expect(try stage("Back over the slot").contains(slideEnds), "the sword is home at \(slideEnds)")
            // Turn: the ring turns from across the sword to along it, standing on its eye.
            let along = try #require(firstProgress { abs($0.ring(1).worldDirection(SIMD3(0, 0, 1)).z) > 0.95 && $0.ring(1).position.y > $0.rod(1).position.y })
            #expect(try stage("Turn").contains(along), "the ring is along the sword at \(along)")
            // Down through the slot: the eye goes down into the slot first, then the whole ring passes below the rails.
            let railTop = Dimensions.Sword.railHeight + Dimensions.Sword.wireRadius
            let railBottom = Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius
            let eyeIn = try #require(firstProgress { $0.rod(1).position.y - Dimensions.Rod.eyeRadius - Dimensions.Rod.wireRadius < railTop })
            #expect(try stage("Down through the slot").contains(eyeIn), "the eye goes into the slot at \(eyeIn)")
            let below = try #require(firstProgress { pose in
                Relations.loop(pose.ring(1).circle, pieces: 90).allSatisfy { $0.y + Dimensions.Ring.wireRadius < railBottom }
            })
            #expect(try stage("Down through the slot").contains(below), "the ring is below the rails at \(below)")
            // Hang: the ring hangs across the sword, and the eye sinks below the rails, so the rod is out of the slot.
            let eyeBelow = try #require(firstProgress { $0.rod(1).position.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius < railBottom })
            #expect(try stage("Hang").contains(eyeBelow), "the eye is below the rails at \(eyeBelow)")
            #expect(eyeIn < below && below < eyeBelow)
            print("stages: leaves the rails at \(leaves), along the sword at \(along), eye into the slot at \(eyeIn), ring below the rails at \(below), eye below the rails at \(eyeBelow)")
        }

        @Test func goingOnNamesTheStagesForWhatHappens() throws {
            let motion = MoveMotion(ringOneOn)
            #expect(motion.stages.map(\.name) == ["Lift", "Up through the slot", "Turn", "Out past the tip", "Over the tip", "Lean"])
            #expect(motion.stage(at: 0).name == "Lift")
            #expect(motion.stage(at: 1).name == "Lean")
        }
    }
}
