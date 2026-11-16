import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// How long each move takes, and how its time maps onto its progress (``MoveTiming``).
@Suite struct MoveTimingTests {
    /// The menu's move for each ring, from where it first comes off.
    static let moves = MoveMotion.written

    /// The pose `time` seconds into the move at full speed.
    static func pose(_ motion: MoveMotion, atTime time: Double) -> ToyPose {
        motion.pose(at: motion.timing.progress(atTime: time))
    }

    @Test func ringOneAndRingTwoTakeThreeSecondsAndEachRingAfterAddsHalfASecond() {
        var lengths: [String] = []
        for move in Self.moves {
            let duration = MoveMotion(move).duration
            let expected = move.ring <= 2 ? 3.0 : 3.0 + 2 * Dimensions.Bar.holePitch * Double(move.ring - 2) / MoveTiming.slideSpeed
            #expect(abs(duration - expected) < 1e-12, "ring \(move.ring): \(duration) s")
            #expect(MoveMotion(move.reversed).duration == duration)
            lengths.append("ring \(move.ring) \(String(format: "%.2f", duration)) s")
        }
        print("move lengths at full speed, slide speed \(MoveTiming.slideSpeed) mm/s: \(lengths.joined(separator: ", "))")
    }

    @Test(arguments: moves.flatMap { [$0, $0.reversed] })
    func timeAndProgressAreEachOthersInverseAndBothIncrease(_ move: Move) {
        let timing = MoveMotion(move).timing
        #expect(timing.time(atProgress: 0) == 0 && timing.time(atProgress: 1) == timing.duration)
        #expect(timing.progress(atTime: 0) == 0 && timing.progress(atTime: timing.duration) == 1)
        var previous = -1.0
        for index in 0...2000 {
            let progress = Double(index) / 2000
            let time = timing.time(atProgress: progress)
            #expect(time > previous, "ring \(move.ring): the time does not increase at progress \(progress)")
            #expect(abs(timing.progress(atTime: time) - progress) < 1e-9)
            previous = time
        }
    }

    /// A ring going on runs its coming off backwards, in time as in its poses.
    @Test(arguments: moves)
    func goingOnTakesTheTimeOfComingOffBackwards(_ off: Move) {
        let comingOff = MoveMotion(off).timing, goingOn = MoveMotion(off.reversed).timing
        for index in 0...200 {
            let progress = Double(index) / 200
            #expect(abs(goingOn.time(atProgress: progress) - (comingOff.duration - comingOff.time(atProgress: 1 - progress))) < 1e-9)
        }
    }

    /// The stages in which ring k itself moves take ring 2's seconds for every ring, moment for moment: at the same
    /// time into them, ring k is where ring 2 is, one hole further along for each ring after ring 2. Only the stages in
    /// which the sword moves away and comes back are longer, by the added slide.
    @Test func theRingsOwnStagesTakeRingTwosSecondsForEveryRing() {
        let two = MoveMotion(Self.moves[1])
        let twoStages = two.timedStages
        for move in Self.moves.dropFirst(2) {
            let motion = MoveMotion(move)
            let stages = motion.timedStages
            let added = Dimensions.Bar.holePitch * Double(move.ring - 2) / MoveTiming.slideSpeed
            for index in 1...3 {
                #expect(abs((stages[index].end - stages[index].start) - (twoStages[index].end - twoStages[index].start)) < 1e-9,
                        "ring \(move.ring), \(stages[index].name)")
            }
            for index in [0, 4] {
                #expect(abs((stages[index].end - stages[index].start) - (twoStages[index].end - twoStages[index].start) - added) < 1e-9,
                        "ring \(move.ring), \(stages[index].name)")
            }
            // Moment for moment through the ring's own stages.
            let shift = SIMD3(Dimensions.Bar.holePitch * Double(move.ring - 2), 0, 0)
            var largest = 0.0
            for index in 0...300 {
                let into = (twoStages[3].end - twoStages[1].start) * Double(index) / 300
                let here = Self.pose(motion, atTime: stages[1].start + into).ring(move.ring)
                let there = Self.pose(two, atTime: twoStages[1].start + into).ring(2)
                largest = max(largest, simd_distance(here.position, there.position + shift))
            }
            #expect(largest < 1e-6, "ring \(move.ring) is \(largest) mm from where ring 2 is at the same time")
        }
    }

    @Test(arguments: moves)
    func theStagesInTimeSpanTheMoveInOrder(_ move: Move) {
        let motion = MoveMotion(move)
        let stages = motion.timedStages
        #expect(stages.map(\.name) == motion.stages.map(\.name))
        #expect(stages.first?.start == 0 && stages.last?.end == motion.duration)
        #expect(zip(stages, stages.dropFirst()).allSatisfy { $0.end == $1.start && $0.start < $0.end })
        for (timed, stage) in zip(stages, motion.stages) {
            #expect(abs(motion.timing.progress(atTime: timed.start) - stage.start) < 1e-9)
        }
    }

    /// The speed of every part stays continuous over the whole move, against time: no jump where the sword's added
    /// slide meets the ring's own stages. Checked as the motion's smoothness is checked against progress, with the
    /// move's time in place of its progress, and the same steps in seconds for every ring (those of ring 2's progress
    /// steps), so that a longer move is looked at as closely as a shorter one.
    @Test(arguments: moves)
    func positionAndVelocityAreContinuousInTime(_ move: Move) {
        let motion = MoveMotion(move)
        let duration = motion.duration
        let pose = { (fraction: Double) in Self.pose(motion, atTime: fraction * duration) }
        let coarse = SmoothnessTests.largestBend(pose, step: 3e-3 / duration)
        let fine = SmoothnessTests.largestBend(pose, step: 3e-4 / duration)
        let perSecondSquared = 1 / (duration * duration)
        print(String(format: "smoothness in time, ring %d: largest bend %.0f mm/s² at a step of 3 ms, %.0f at 0.3 ms", move.ring, coarse * perSecondSquared, fine * perSecondSquared))
        #expect(fine < 1.5 * coarse)
    }

    /// At full speed the move starts and ends at rest, and does not stop where one stage meets the next.
    @Test(arguments: moves)
    func theMoveStartsAndEndsAtRestAndDoesNotStopBetweenStagesInTime(_ move: Move) {
        let motion = MoveMotion(move)
        func speed(at time: Double, step: Double) -> Double {
            zip(numbers(Self.pose(motion, atTime: time)), numbers(Self.pose(motion, atTime: time + step))).map { abs($0 - $1) / abs(step) }.max() ?? 0
        }
        #expect(speed(at: 0, step: 1e-6) < 0.05)
        #expect(speed(at: motion.duration, step: -1e-6) < 0.05)
        for stage in motion.timedStages.dropFirst() {
            let here = speed(at: stage.start, step: 1e-4)
            #expect(here > 3, "ring \(move.ring): \(here) mm/s at the start of \(stage.name)")
        }
    }
}
