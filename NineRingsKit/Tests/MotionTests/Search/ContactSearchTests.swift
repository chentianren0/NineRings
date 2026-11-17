import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Where the written moves bring parts together: the tool that found the contacts the score is written at (see
/// ``Score``). Run optimized with `NINE_RINGS_CONTACTS=1`. For ring 1's move and the second ring's (as ring 2's), it
/// samples the path's own parameter and prints each place where the gap between two parts that the score cares about
/// is at its smallest, under 2 mm: the moving ring and the sword, the moving ring and any other part, and, in the
/// second ring's move, ring k−1 and the sword.
@Suite struct ContactSearchTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_CONTACTS"] != nil))
    func contacts() {
        report("ring 1", ring: 1, pose: { RingOneOff.written.pose(at: $0) }, pacing: RingOneOff.pacing)
        let paced = PairMoveOff.paced[0]
        report("ring 2", ring: 2, pose: paced.path.pose(at:), pacing: paced.pacing)
    }

    private func report(_ title: String, ring: Int, pose: (Double) -> ToyPose, pacing: Pacing) {
        let samples = 2000
        let parameters = (0...samples).map { Double($0) / Double(samples) }
        let poses = parameters.map(pose)
        var series: [(String, [Double])] = [
            ("ring \(ring) – sword", poses.map { ContactProbe.gap(ring: ring, toSword: $0) }),
            ("ring \(ring) – others", poses.map { ContactProbe.gap(ring: ring, toOthers: $0) }),
        ]
        if ring > 1 {
            series.append(("ring \(ring - 1) – sword", poses.map { ContactProbe.gap(ring: ring - 1, toSword: $0) }))
        }
        print("\(title):")
        for (name, gaps) in series {
            for index in ContactProbe.minima(gaps, below: 2, prominence: 0.3) {
                let parameter = parameters[index]
                print(String(
                    format: "  %@: %.3f mm at path %.4f, progress %.4f", name, gaps[index], parameter,
                    pacing.progress(atPathParameter: parameter)
                ))
            }
            let profile = stride(from: 0, through: samples, by: 40).map { String(format: "%.1f", min(gaps[$0], 9.9)) }
            print("    every 0.02: " + profile.joined(separator: " "))
            for window in [(0.0, 0.16), (0.9, 1.0)] {
                let range = stride(from: Int(window.0 * Double(samples)), through: Int(window.1 * Double(samples)), by: 10)
                print(String(format: "    from %.2f every 0.005: ", window.0) + range.map { String(format: "%.2f", min(gaps[$0], 9.9)) }.joined(separator: " "))
            }
        }
        let slides = poses.map(\.swordSlide), heights = poses.map(\.swordHeight)
        print(String(format: "  sword slide from %.2f to %.2f mm, height from %.2f to %.2f mm", slides.min()!, slides.max()!, heights.min()!, heights.max()!))
    }
}

/// Gaps between the parts the score cares about.
enum ContactProbe {
    /// The gap between ring `ring`'s wire and the sword's.
    static func gap(ring: Int, toSword pose: ToyPose) -> Double {
        let shapes = pose.shapes
        guard let ringShape = shapes.first(where: { $0.name == .ring(ring) }) else { return .infinity }
        return shapes.filter { $0.name == .sword }.map { distance(ringShape, $0) }.min() ?? .infinity
    }

    /// The gap between ring `ring` and every part but the sword and its own rod.
    static func gap(ring: Int, toOthers pose: ToyPose) -> Double {
        let shapes = pose.shapes
        guard let ringShape = shapes.first(where: { $0.name == .ring(ring) }) else { return .infinity }
        return shapes.filter { $0.name != .sword && !ringShape.name.isJoined(to: $0.name) }.map { distance(ringShape, $0) }.min() ?? .infinity
    }

    /// The indices where `values` is at a smallest that stands out: under `below`, and lower by at least `prominence`
    /// than the highest value on each side before a lower one. A flat stretch counts once, at its first index.
    static func minima(_ values: [Double], below: Double, prominence: Double) -> [Int] {
        var found: [Int] = []
        var index = 1
        while index < values.count - 1 {
            var end = index
            while end + 1 < values.count && values[end + 1] == values[index] { end += 1 }
            let value = values[index]
            if value < below && values[index - 1] > value && (end + 1 == values.count || values[end + 1] > value) {
                var left = value, right = value
                var i = index - 1
                while i >= 0 && values[i] >= value { left = max(left, values[i]); i -= 1 }
                var j = end + 1
                while j < values.count && values[j] >= value { right = max(right, values[j]); j += 1 }
                // An end of the move counts as a high side: a gap that only grows away from it stands out.
                let leftHigh = i < 0 ? max(left, values[0] + prominence) : left
                let rightHigh = j >= values.count ? max(right, values[values.count - 1] + prominence) : right
                if min(leftHigh, rightHigh) - value >= prominence { found.append(index) }
            }
            index = end + 1
        }
        return found
    }

    static func distance(_ a: Shape, _ b: Shape) -> Double {
        if simd_distance(a.boundCenter, b.boundCenter) > a.boundRadius + b.boundRadius + 3 { return .infinity }
        let (pointA, pointB) = Gaps.nearest(a.core, b.core)
        return simd_distance(pointA, pointB) - a.radius - b.radius
    }
}
