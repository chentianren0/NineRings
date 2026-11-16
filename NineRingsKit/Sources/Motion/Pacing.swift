import Foundation
import Toy
import simd

/// How a move's progress maps onto its path's own parameter.
///
/// A path's curves are keyed for where things happen, not for how fast they happen, and some stretches of a path
/// move the toy much faster than others. The pacing gives each stretch time in proportion to how far the toy
/// travels in it, mostly, so the move flows at a steady pace and starts and ends at rest. It is worked out once,
/// from the path, and changes only when the move is played, never where anything goes.
struct Pacing: Sendable {
    /// The path's parameter as a curve of the move's progress.
    let timing: Curve

    init(_ pose: (Double) -> ToyPose) {
        let pieces = 400
        let poses = (0...pieces).map { pose(Double($0) / Double(pieces)) }
        // How far the farthest point of anything moves along each piece of the path.
        let travel = zip(poses, poses.dropFirst()).map { a, b in
            var largest = simd_distance(a.swordOffset, b.swordOffset)
            for (first, second) in zip(a.rings + a.rods, b.rings + b.rods) {
                let turn = first.orientation.inverse * second.orientation
                let angle = 2 * atan2(simd_length(turn.imag), abs(turn.real))
                largest = max(largest, simd_distance(first.position, second.position) + angle * Self.reachOfARing)
            }
            return largest
        }
        // Time for each piece: mostly in proportion to its travel, partly the same for every piece, so that the
        // nearly still stretches near the ends are not skipped through.
        let mean = travel.reduce(0, +) / Double(travel.count)
        let weights = travel.map { 0.8 * $0 + 0.2 * mean }
        let total = weights.reduce(0, +)
        var keys = [Curve.Key(0, 0)]
        var elapsed = 0.0
        for (index, weight) in weights.enumerated() {
            elapsed += weight / total
            if (index + 1) % 10 == 0 {
                keys.append(Curve.Key(min(elapsed, 1), Double(index + 1) / Double(pieces)))
            }
        }
        keys[keys.count - 1] = Curve.Key(1, 1)
        timing = Curve(keys)
    }

    /// The farthest a point of a ring is from the ring's middle.
    private static let reachOfARing = Dimensions.Ring.radius + Dimensions.Ring.wireRadius

    /// The path's parameter a fraction `progress` of the way through the move.
    func pathParameter(atProgress progress: Double) -> Double {
        timing.value(at: progress)
    }

    /// Stages given as spans of the path's parameter, as spans of the move's progress.
    func stages(_ alongThePath: [Stage]) -> [Stage] {
        alongThePath.map { stage in
            stage.spanning(from: progress(atPathParameter: stage.start), to: progress(atPathParameter: stage.end))
        }
    }

    /// The progress at which the move reaches `parameter` along the path, found by halving.
    func progress(atPathParameter parameter: Double) -> Double {
        if parameter <= 0 { return 0 }
        if parameter >= 1 { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if timing.value(at: middle) < parameter { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
}
