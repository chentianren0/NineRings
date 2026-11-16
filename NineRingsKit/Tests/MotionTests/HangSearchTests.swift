import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Searches for how ring 1 can hang off while ring 2 is on, which is how the leans of the rest poses were found.
/// Run with `NINE_RINGS_HANG=1`, optimized; `NINE_RINGS_FREE_ROD2=1` lets rod 2 lean.
@Suite struct HangSearchTests {
    static let freeRodTwo = ProcessInfo.processInfo.environment["NINE_RINGS_FREE_ROD2"] != nil
    /// For a what-if only: how much further under the bar the beads of rings that are on would rest, which lets
    /// rod 2 rise by that much. Zero is the model as written.
    static let beadRoom = Double(ProcessInfo.processInfo.environment["NINE_RINGS_BEAD_ROOM"] ?? "0")!

    /// Ring 2's lean, side and roll; ring 1's eye, lean, side and roll; rod 2's eye offsets. Degrees and mm.
    static let names = ["lean2", "side2", "roll2", "eye1x", "eye1y", "eye1z", "lean1", "side1", "roll1", "eye2dx", "eye2dy", "eye2dz"]
    static let ranges: [ClosedRange<Double>] = [0...45, -40...40, -70...70, 30...52, -22...(-9.5), -9...9, -10...100, -70...70, -90...90, -14...6, -6...(Double(ProcessInfo.processInfo.environment["NINE_RINGS_BEAD_ROOM"] ?? "0")!), -9...9]

    static func direction(lean: Double, side: Double) -> SIMD3<Double> {
        let l = lean * .pi / 180, s = side * .pi / 180
        return SIMD3(-sin(l) * cos(s), -cos(l) * cos(s), sin(s))
    }

    static func held(_ v: [Double]) -> (ring1: HeldRing, ring2: HeldRing) {
        func ring(eye: SIMD3<Double>, lean: Double, side: Double, roll: Double) -> HeldRing {
            let center = direction(lean: lean, side: side)
            var reference = SIMD3<Double>(0, 0, 1) - simd_dot(SIMD3(0, 0, 1), center) * center
            if simd_length(reference) < 1e-6 { reference = SIMD3(1, 0, 0) }
            let wire = simd_quatd(angle: roll * .pi / 180, axis: center).act(simd_normalize(reference))
            return HeldRing(eye: eye, towardCenter: center, alongWire: wire)
        }
        let eye2 = RestPoses.on(2).eye + (freeRodTwo ? SIMD3(v[9], v[10], v[11]) : .zero)
        return (ring(eye: SIMD3(v[3], v[4], v[5]), lean: v[6], side: v[7], roll: v[8]),
                ring(eye: eye2, lean: v[0], side: v[1], roll: v[2]))
    }

    static let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2), .bead(2)]

    static func score(_ v: [Double]) -> Double {
        let (one, two) = held(v)
        for (index, ring) in [one, two].enumerated() {
            let down = simd_normalize(Layout.hole(index + 1) - ring.eye)
            let angle = asin(min(1, abs(simd_dot(ring.alongWire, down)))) * 180 / .pi
            if angle > 55 { return -20 - angle / 10 }
        }
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = one
        rings[1] = two
        let pose = RestPoses.pose(holding: rings, swordSlide: 0)
        var penalty = Double(Relations.failures(in: pose).count)
        if Relations.isRoundTheRails(1, in: pose) { penalty += 1 }
        let eyeTop = one.eye.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius
        if eyeTop > Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius - 0.2 { penalty += 1 }
        // Ring 1 hangs on the tip side of ring 2.
        let ringTwo = pose.ring(2).circle
        let towardTip = ringTwo.normal.x < 0 ? ringTwo.normal : -ringTwo.normal
        if simd_dot(pose.ring(1).position - ringTwo.center, towardTip) < 0 { penalty += 1 }
        var shapes = pose.shapes
        if Self.beadRoom > 0 {
            // The bar as if the beads rested further under it: moved up by the extra room.
            shapes = shapes.map { shape in
                guard shape.name == .bar, case .stadium(var stadium) = shape.core else { return shape }
                stadium.center.y += Self.beadRoom
                return Shape(.bar, .stadium(stadium), radius: shape.radius)
            }
        }
        let gap = Gaps.smallest(in: shapes, involving: moving)?.distance ?? 10
        return penalty > 0 ? min(gap, 0) - 3 * penalty : min(gap, 2)
    }

    static func describe(_ v: [Double]) -> String {
        zip(names, v).map { "\($0)=\(String(format: "%.2f", $1))" }.joined(separator: " ")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_HANG"] != nil))
    func searchHang() {
        var generator = SystemRandomNumberGenerator()
        let count = Int(ProcessInfo.processInfo.environment["NINE_RINGS_SAMPLES"] ?? "40000")!
        let candidates = (0..<count).map { _ in Self.ranges.map { Double.random(in: $0, using: &generator) } }
        let scores = Sweep.inParallel(candidates.count) { Self.score(candidates[$0]) }
        let order = scores.indices.sorted { scores[$0] > scores[$1] }
        print("feasible: \(scores.filter { $0 > 0 }.count) of \(count)")
        var results: [(Double, [Double])] = []
        for start in order.prefix(12) {
            var best = candidates[start], bestScore = scores[start]
            var scale = 1.0
            while scale > 0.01 {
                var improved = false
                for index in best.indices where Self.freeRodTwo || index < 9 {
                    for sign in [-1.0, 1.0] {
                        var trial = best
                        let span = Self.ranges[index].upperBound - Self.ranges[index].lowerBound
                        trial[index] = min(max(trial[index] + sign * span * 0.05 * scale, Self.ranges[index].lowerBound), Self.ranges[index].upperBound)
                        let s = Self.score(trial)
                        if s > bestScore { (best, bestScore, improved) = (trial, s, true) }
                    }
                }
                if !improved { scale /= 2 }
            }
            results.append((bestScore, best))
            print(String(format: "%.3f  ", bestScore) + Self.describe(best))
        }
    }
}
