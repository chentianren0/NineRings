import Foundation
@testable import Motion
import Puzzle
import Geometry
import Testing
import Toy
import simd

/// Searches the key values of ring 1's drop for the path with the most room, for writing the path by hand.
/// Run with `NINE_RINGS_TUNE=1`, optimized. It prints the best keys it finds.
@Suite struct TuneTests {
    /// The drop's keys: for each curve, its keys as (progress, value) pairs, values in degrees or millimetres.
    /// Keys marked fixed keep their value; every progress is free within its order.
    struct Drop {
        struct Channel {
            var name: String
            var keys: [(Double, Double)]
            var fixedValues: Set<Int>
            var fixedProgress: Set<Int> = []
        }
        var channels: [Channel]

        static let hang = 180 - RingOneOff.leanHangingDegrees

        static var initial: Drop {
            let channels = ProcessInfo.processInfo.environment["NINE_RINGS_DROP"].flatMap(Drop.parse) ?? [
                Channel(name: "tip", keys: [(0.55, 0), (0.62, 25), (0.72, 90), (0.92, hang)], fixedValues: [0, 3], fixedProgress: [0]),
                Channel(name: "tilt", keys: [(0.57, 0), (0.66, 40), (0.72, 65), (1, 90)], fixedValues: [0, 3], fixedProgress: [3]),
                Channel(name: "swing", keys: [(0.60, 0), (0.68, 25), (0.72, 0), (0.78, -30), (0.92, 0)], fixedValues: [0, 4]),
                Channel(name: "eye", keys: [(0.56, Layout.eyeHeightOn), (0.64, -4), (0.80, -6.5), (0.95, Layout.eyeHeightHanging)], fixedValues: [0, 3], fixedProgress: [0]),
            ]
            return Drop(channels: channels)
        }

        /// Reads channels printed by an earlier run: `name:p=v,p=v;name:...`, with the fixed keys as in `initial`.
        static func parse(_ text: String) -> [Channel]? {
            let template = Drop(channels: [
                Channel(name: "tip", keys: [], fixedValues: [], fixedProgress: [0]),
                Channel(name: "tilt", keys: [], fixedValues: [], fixedProgress: []),
                Channel(name: "swing", keys: [], fixedValues: [], fixedProgress: []),
                Channel(name: "eye", keys: [], fixedValues: [], fixedProgress: [0]),
            ])
            var channels: [Channel] = []
            for part in text.split(separator: ";") {
                let halves = part.split(separator: ":")
                guard halves.count == 2, var channel = template.channels.first(where: { $0.name == halves[0] }) else { return nil }
                channel.keys = halves[1].split(separator: ",").compactMap { pair in
                    let numbers = pair.split(separator: "=").compactMap { Double($0) }
                    return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
                }
                channel.fixedValues = [0, channel.keys.count - 1]
                if channel.name == "tilt" { channel.fixedProgress = [channel.keys.count - 1] }
                channels.append(channel)
            }
            return channels
        }

        var text: String {
            channels.map { channel in
                channel.name + ":" + channel.keys.map { String(format: "%.4f=%.3f", $0.0, $0.1) }.joined(separator: ",")
            }.joined(separator: ";")
        }

        /// Every free number, with the step to try it by.
        var free: [(channel: Int, key: Int, isProgress: Bool, step: Double)] {
            var list: [(Int, Int, Bool, Double)] = []
            for (c, channel) in channels.enumerated() {
                for k in channel.keys.indices {
                    if !channel.fixedProgress.contains(k) { list.append((c, k, true, 0.015)) }
                    if !channel.fixedValues.contains(k) { list.append((c, k, false, channel.name == "eye" ? 0.8 : 8)) }
                }
            }
            return list
        }

        mutating func nudge(_ item: (channel: Int, key: Int, isProgress: Bool, step: Double), by amount: Double) {
            if item.isProgress { channels[item.channel].keys[item.key].0 += amount } else { channels[item.channel].keys[item.key].1 += amount }
        }

        func path() -> RingOneOff? {
            for channel in channels {
                let progress = channel.keys.map(\.0)
                guard zip(progress, progress.dropFirst()).allSatisfy({ $0 < $1 - 0.008 }), progress.first! >= 0.43, progress.last! <= 1 else { return nil }
            }
            var path = RingOneOff.written
            for channel in channels {
                switch channel.name {
                case "tip": path.tip = RingOneOff.degrees(channel.keys)
                case "tilt": path.tilt = RingOneOff.degrees(channel.keys)
                case "swing": path.swing = RingOneOff.degrees(channel.keys)
                default: path.eyeHeight = RingOneOff.millimetres(channel.keys)
                }
            }
            return path
        }
    }

    static let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1)]

    /// The smallest room over the drop, with penalties for anything else that goes wrong.
    static func score(_ drop: Drop, samples: Int = 160) -> Double {
        guard let path = drop.path() else { return -100 }
        let progress = (0...samples).map { 0.55 + 0.45 * Double($0) / Double(samples) }
        let scores = Sweep.inParallel(progress.count) { index -> Double in
            let p = progress[index]
            let held = path.held(at: p)
            let down = simd_normalize(Layout.hole(1) - held.eye)
            let wireAngle = asin(min(1, abs(simd_dot(held.alongWire, down)))) * 180 / .pi
            if wireAngle > 55 { return -(wireAngle - 55) / 10 - 1 }
            let pose = path.pose(at: p)
            let (near, far) = ([Vector](), [Vector]())
            _ = (near, far)
            // The bead resting under the bar is a hair away by design, and not what the drop has to clear.
            let shapes = pose.shapes.filter { $0.name != .bar }
            let gap = Gaps.smallest(in: shapes, involving: moving)?.distance ?? 10
            return min(gap, 1.5)
        }
        return scores.min() ?? -100
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_TUNE"] != nil))
    func tuneDrop() {
        var best = Drop.initial
        var bestScore = Self.score(best)
        print("start: \(bestScore)")
        if let path = best.path() {
            for index in 0...90 {
                let p = 0.55 + 0.005 * Double(index)
                let (near, far) = Relations.swordCrossings(of: 1, in: path.pose(at: p))
                if near.count % 2 == 1 || far.count % 2 == 1 { print("odd at \(p): near \(near) far \(far)") }
            }
        }
        var scale = 1.0
        var generator = SystemRandomNumberGenerator()
        for round in 0..<(ProcessInfo.processInfo.environment["NINE_RINGS_ROUNDS"].flatMap { Int($0) } ?? 40) {
            var improved = false
            for item in best.free {
                for direction in [-1.0, 1.0] {
                    var trial = best
                    trial.nudge(item, by: direction * item.step * scale)
                    let trialScore = Self.score(trial)
                    if trialScore > bestScore {
                        (best, bestScore, improved) = (trial, trialScore, true)
                    }
                }
            }
            // A few random nudges of everything at once, to get out of corners.
            for _ in 0..<12 {
                var trial = best
                for item in trial.free {
                    trial.nudge(item, by: Double.random(in: -1...1, using: &generator) * item.step * scale)
                }
                let trialScore = Self.score(trial)
                if trialScore > bestScore {
                    (best, bestScore, improved) = (trial, trialScore, true)
                }
            }
            print("round \(round): \(bestScore) at scale \(scale)")
            if !improved { scale /= 2 }
            if scale < 0.05 { break }
        }
        print("best room \(bestScore)")
        print("NINE_RINGS_DROP='\(best.text)'")
        print("check with 800 samples: \(Self.score(best, samples: 800))")
        if let path = best.path() {
            let angles = (0...400).map { index -> Double in
                let held = path.held(at: 0.55 + 0.45 * Double(index) / 400)
                let down = simd_normalize(Layout.hole(1) - held.eye)
                return asin(min(1, abs(simd_dot(held.alongWire, down)))) * 180 / .pi
            }
            print("largest angle of the wire in the eye: \(angles.max()!) degrees")
        }
        if let path = best.path() {
            for index in 0...45 {
                let p = 0.55 + 0.01 * Double(index)
                let held = path.held(at: p)
                let gap = Gaps.smallest(in: path.pose(at: p).shapes, involving: Self.moving)!
                print(String(format: "%.3f eye %6.2f V (%5.2f %5.2f %5.2f) T (%5.2f %5.2f %5.2f) ", p, held.eye.y, held.towardCenter.x, held.towardCenter.y, held.towardCenter.z, held.alongWire.x, held.alongWire.y, held.alongWire.z) + "\(gap)")
            }
        }
    }
}
