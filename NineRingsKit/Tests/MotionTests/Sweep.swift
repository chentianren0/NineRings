import Foundation
import Motion
import Puzzle
import Toy
import simd

/// A move sampled at many progress values, with everything the checker reads from it.
struct Sweep {
    static let samples = 4000

    let motion: MoveMotion
    let progress: [Double]
    let poses: [ToyPose]
    /// The smallest gap at each sample.
    let gaps: [Gap]
    /// The largest step of any point from each sample to the next.
    let steps: [(distance: Double, part: String)]

    init(_ motion: MoveMotion, samples: Int = Sweep.samples) {
        self.motion = motion
        progress = (0...samples).map { Double($0) / Double(samples) }
        poses = progress.map(motion.pose(at:))
        let poses = poses
        gaps = Sweep.inParallel(poses.count) { index in
            guard let gap = Gaps.smallest(in: poses[index].shapes) else {
                preconditionFailure("the toy always has parts near one another")
            }
            return gap
        }
        steps = zip(poses, poses.dropFirst()).map { Relations.largestStep(from: $0, to: $1) }
    }

    var smallestGap: (gap: Gap, progress: Double) {
        let index = gaps.indices.min { gaps[$0].distance < gaps[$1].distance } ?? 0
        return (gaps[index], progress[index])
    }

    var largestStep: (distance: Double, part: String, progress: Double) {
        let index = steps.indices.max { steps[$0].distance < steps[$1].distance } ?? 0
        return (steps[index].distance, steps[index].part, progress[index])
    }

    /// The rings that may be off the rails during the move: ring 1, which steps aside for ring 2, and every ring up
    /// to the one that moves.
    var mayBeOff: Set<Int> { Set(1...motion.move.ring) }

    /// The first progress, if any, at which a relation fails, with what failed.
    var firstRelationFailure: (progress: Double, failures: [String])? {
        let poses = poses
        let mayBeOff = mayBeOff
        let failures = Sweep.inParallel(poses.count) { Relations.failures(in: poses[$0], mayBeOff: mayBeOff) }
        guard let index = failures.firstIndex(where: { !$0.isEmpty }) else { return nil }
        return (progress[index], failures[index])
    }

    /// `work` for every index from 0 to `count`, side by side, the results in order. The samples of a sweep are
    /// independent, so this only makes the checker quicker.
    static func inParallel<Result: Sendable>(_ count: Int, _ work: @escaping @Sendable (Int) -> Result) -> [Result] {
        let results = Results<Result>(count: count)
        DispatchQueue.concurrentPerform(iterations: count) { index in
            results.set(index, work(index))
        }
        return results.values
    }

    /// Whether ring `number` goes round both rails at each sample.
    func roundTheRails(_ number: Int) -> [Bool] {
        poses.map { Relations.isRoundTheRails(number, in: $0) }
    }
}

/// Results written from many threads, each to its own slot.
private final class Results<Value: Sendable>: @unchecked Sendable {
    private var slots: [Value?]
    private let lock = NSLock()

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ value: Value) {
        lock.withLock { slots[index] = value }
    }

    var values: [Value] {
        lock.withLock { slots.map { $0! } }
    }
}
