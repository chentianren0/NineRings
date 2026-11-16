import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

/// Every number a pose is made of: positions, and each orientation as the three axes it turns the local ones to.
func numbers(_ pose: ToyPose) -> [Double] {
    var numbers = [pose.swordSlide, pose.swordHeight]
    for part in pose.rings + pose.rods + [pose.bar] {
        numbers += [part.position.x, part.position.y, part.position.z]
        for axis in [SIMD3<Double>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
            let turned = part.worldDirection(axis) * 10
            numbers += [turned.x, turned.y, turned.z]
        }
    }
    return numbers
}

@Suite struct SmoothnessTests {
    /// The largest second difference of any number of the pose over the whole move, divided by the step squared.
    /// It stays bounded as the step shrinks when positions and velocities are continuous; a jump in velocity
    /// would make it grow as one over the step.
    private func largestBend(_ motion: MoveMotion, step: Double) -> Double {
        Self.largestBend(motion.pose(at:), step: step)
    }

    static func largestBend(_ pose: (Double) -> ToyPose, step: Double) -> Double {
        var largest = 0.0
        var progress = step
        while progress < 1 - step {
            let before = numbers(pose(progress - step))
            let here = numbers(pose(progress))
            let after = numbers(pose(progress + step))
            for index in here.indices {
                largest = max(largest, abs(after[index] - 2 * here[index] + before[index]) / (step * step))
            }
            progress += step / 3.7
        }
        return largest
    }

    @Test(arguments: MoveMotion.written)
    func positionAndVelocityAreContinuous(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let coarse = largestBend(motion, step: 1e-3)
        let fine = largestBend(motion, step: 1e-4)
        print("smoothness, ring \(move.ring): largest bend \(coarse) at a step of 1e-3, \(fine) at 1e-4 (mm per progress squared)")
        #expect(fine < 1.5 * coarse)
    }

    @Test(arguments: MoveMotion.written)
    func theMoveStartsAndEndsAtRest(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        for end in [0.0, 1.0] {
            let here = numbers(motion.pose(at: end))
            let near = numbers(motion.pose(at: end == 0 ? 1e-6 : 1 - 1e-6))
            let speed = zip(here, near).map { abs($0 - $1) / 1e-6 }.max() ?? 0
            #expect(speed < 0.01, "speed \(speed) at progress \(end)")
        }
    }

    /// Where several parts move at once, the motion should not come to a halt at a stage boundary.
    @Test(arguments: MoveMotion.written)
    func theMotionDoesNotStopBetweenStages(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        for stage in motion.stages.dropFirst() {
            let here = numbers(motion.pose(at: stage.start))
            let near = numbers(motion.pose(at: stage.start + 1e-4))
            let speed = zip(here, near).map { abs($0 - $1) / 1e-4 }.max() ?? 0
            print("ring \(move.ring): speed at the start of \(stage.name): \(speed) mm per progress")
            #expect(speed > 10, "the motion stops at the start of \(stage.name)")
        }
    }

    @Test(arguments: MoveMotion.written)
    func aPoseTakesFarLessThanAMillisecond(_ move: Move) throws {
        let motion = try #require(MoveMotion(move))
        let count = 20_000
        var checksum = 0.0
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<count {
                checksum += motion.pose(at: Double(index) / Double(count)).ring(1).position.x
            }
        }
        let microseconds = Double(elapsed.components.attoseconds) / 1e12 / Double(count) + Double(elapsed.components.seconds) * 1e6 / Double(count)
        print("timing, ring \(move.ring): one pose takes \(String(format: "%.2f", microseconds)) µs (checksum \(checksum))")
        #expect(microseconds < 1000)
    }
}

@Suite struct CurveTests {
    @Test func passesThroughItsKeysWithoutOvershooting() {
        let curve = Curve([.init(0, 0), .init(0.2, 1), .init(0.5, 1.2), .init(0.7, -1), .init(1, 0)])
        for key in curve.keys {
            #expect(abs(curve.value(at: key.progress) - key.value) < 1e-12)
        }
        for (a, b) in zip(curve.keys, curve.keys.dropFirst()) {
            for step in 1..<50 {
                let value = curve.value(at: a.progress + (b.progress - a.progress) * Double(step) / 50)
                #expect(value >= min(a.value, b.value) - 1e-12 && value <= max(a.value, b.value) + 1e-12)
            }
        }
    }

    @Test func holdsItsEndValuesBeyondItsKeys() {
        let curve = Curve([.init(0.3, 2), .init(0.6, 5)])
        #expect(curve.value(at: 0) == 2 && curve.value(at: 0.3) == 2)
        #expect(curve.value(at: 0.6) == 5 && curve.value(at: 1) == 5)
        // It leaves and reaches its end values at rest.
        #expect(abs(curve.value(at: 0.3 + 1e-6) - 2) < 1e-9)
        #expect(abs(curve.value(at: 0.6 - 1e-6) - 5) < 1e-9)
    }
}
