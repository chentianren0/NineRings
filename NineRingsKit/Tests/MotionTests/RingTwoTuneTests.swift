import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Searches the key values of ring 2's move for the path with the most room, for writing the path by hand.
/// Run with `NINE_RINGS_TUNE2=1`, optimized. It starts from the keys written in ``RingTwoOff``, or from keys an
/// earlier run printed, given as `NINE_RINGS_PATH2`; `NINE_RINGS_TUNE_ONLY` names the curves it may change.
@Suite struct RingTwoTuneTests {
    typealias Keys = [String: [(Double, Double)]]

    static let names = ["ring1.lid", "ring1.turn", "ring2.tip", "ring2.tilt", "ring2.swing", "ring2.eye", "sword"]

    static var initial: Keys {
        if let text = ProcessInfo.processInfo.environment["NINE_RINGS_PATH2"], let parsed = parse(text) { return parsed }
        return RingTwoOff.keys
    }

    static func parse(_ text: String) -> Keys? {
        var keys: Keys = RingTwoOff.keys
        for part in text.split(separator: ";") {
            let halves = part.split(separator: ":")
            guard halves.count == 2, names.contains(String(halves[0])) else { return nil }
            keys[String(halves[0])] = halves[1].split(separator: ",").compactMap { pair in
                let numbers = pair.split(separator: "=").compactMap { Double($0) }
                return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
            }
        }
        return keys
    }

    static func text(_ keys: Keys) -> String {
        names.map { name in
            name + ":" + keys[name]!.map { String(format: "%.4f=%.3f", $0.0, $0.1) }.joined(separator: ",")
        }.joined(separator: ";")
    }

    static func path(_ keys: Keys) -> RingTwoOff? {
        for name in names {
            let progress = keys[name]!.map(\.0)
            guard zip(progress, progress.dropFirst()).allSatisfy({ $0 < $1 - 0.008 }), progress.first! >= 0, progress.last! <= 1 else { return nil }
        }
        return RingTwoOff(keys: keys)
    }

    static let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2), .bead(2), .sword]

    /// The room at one point of the path, or a negative penalty when something is wrong.
    static func room(_ path: RingTwoOff, at parameter: Double) -> Double {
        let ringTwo = path.ringTwo.held(2, at: parameter)
        let down = simd_normalize(Layout.hole(2) - ringTwo.eye)
        let wireAngle = asin(min(1, abs(simd_dot(ringTwo.alongWire, down)))) * 180 / .pi
        if wireAngle > 55 { return -(wireAngle - 55) / 10 - 1 }
        let pose = path.pose(at: parameter)
        let one = pose.ring(1).circle, two = pose.ring(2).circle
        var penalty = 0.0
        for ring in [1, 2] {
            let (near, far) = Relations.swordCrossings(of: ring, in: pose)
            if near.count % 2 != far.count % 2 { penalty += 1 }
        }
        if Relations.crossings(of: Relations.threadPath(of: pose.rod(1)), through: two).count % 2 != 1 { penalty += 1 }
        if Relations.crossings(of: Relations.threadPath(of: pose.rod(2)), through: pose.ring(3).circle).count % 2 != 1 { penalty += 1 }
        if Relations.areLinked(two, one) || Relations.areLinked(two, pose.ring(3).circle) { penalty += 1 }
        if Relations.areLinked(pose.rod(1).eye, two) || Relations.areLinked(pose.rod(2).eye, one) { penalty += 1 }
        let shapes = pose.shapes.filter { $0.name != .bar }
        let gap = Gaps.smallest(in: shapes, involving: moving)?.distance ?? 10
        return penalty > 0 ? min(gap, 0) - penalty : min(gap, 1.5)
    }

    static func score(_ keys: Keys, samples: Int = 300) -> Double {
        guard let path = path(keys) else { return -100 }
        let progress = (0...samples).map { Double($0) / Double(samples) }
        let rooms = Sweep.inParallel(progress.count) { room(path, at: progress[$0]) }
        return rooms.min() ?? -100
    }

    struct Item { var name: String; var key: Int; var isProgress: Bool; var step: Double }

    static func free(_ keys: Keys) -> [Item] {
        let only = ProcessInfo.processInfo.environment["NINE_RINGS_TUNE_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        var list: [Item] = []
        for name in names where only?.contains(name) ?? true {
            let count = keys[name]!.count
            for k in 0..<count {
                let isEnd = k == 0 || k == count - 1
                // The ends of the move are fixed; elsewhere every key's place is free, and every value but an end
                // value, which is a rest pose.
                let fixedProgress = (name == "ring1.lid" || name == "sword") && isEnd
                let fixedValue = isEnd
                if !fixedProgress { list.append(Item(name: name, key: k, isProgress: true, step: 0.01)) }
                if !fixedValue { list.append(Item(name: name, key: k, isProgress: false, step: ["ring2.eye", "sword"].contains(name) ? 0.8 : 6)) }
            }
        }
        return list
    }

    static func nudge(_ keys: inout Keys, _ item: Item, by amount: Double) {
        if item.isProgress { keys[item.name]![item.key].0 += amount } else { keys[item.name]![item.key].1 += amount }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_TUNE2"] != nil))
    func tune() {
        var best = Self.initial
        var bestScore = Self.score(best)
        print("start: \(bestScore)")
        Self.report(best)
        var scale = Double(ProcessInfo.processInfo.environment["NINE_RINGS_SCALE"] ?? "1")!
        var generator = SystemRandomNumberGenerator()
        let rounds = ProcessInfo.processInfo.environment["NINE_RINGS_ROUNDS"].flatMap { Int($0) } ?? 40
        for round in 0..<rounds {
            var improved = false
            for item in Self.free(best) {
                for direction in [-1.0, 1.0] {
                    var trial = best
                    Self.nudge(&trial, item, by: direction * item.step * scale)
                    let trialScore = Self.score(trial)
                    if trialScore > bestScore { (best, bestScore, improved) = (trial, trialScore, true) }
                }
            }
            for _ in 0..<12 {
                var trial = best
                for item in Self.free(trial) {
                    Self.nudge(&trial, item, by: Double.random(in: -1...1, using: &generator) * item.step * scale)
                }
                let trialScore = Self.score(trial)
                if trialScore > bestScore { (best, bestScore, improved) = (trial, trialScore, true) }
            }
            print("round \(round): \(bestScore) at scale \(scale)")
            if !improved { scale /= 2 }
            if scale < 0.05 { break }
        }
        print("best room \(bestScore)")
        print("NINE_RINGS_PATH2='\(Self.text(best))'")
        print("check with 1200 samples: \(Self.score(best, samples: 1200))")
        Self.report(best)
    }

    /// Prints the room along the path, a line per hundredth.
    static func report(_ keys: Keys) {
        guard let path = path(keys) else { return }
        for index in 0...100 {
            let parameter = Double(index) / 100
            let pose = path.pose(at: parameter)
            let gap = Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: moving)!
            let on = [1, 2].map { Relations.isRoundTheRails($0, in: pose) ? "on " : "off" }.joined(separator: " ")
            print(String(format: "path %.2f room %6.3f  %@  ", parameter, room(path, at: parameter), on) + "\(gap)")
        }
    }
}
