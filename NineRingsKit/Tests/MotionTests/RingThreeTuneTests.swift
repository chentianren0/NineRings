import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Searches the key values of ring 3's move for the path with the most room, for writing the path by hand.
/// Run with `NINE_RINGS_TUNE3=1`, optimized. It starts from the keys written in ``RingThreeOff``, or from keys an
/// earlier run printed, given as `NINE_RINGS_PATH3`; `NINE_RINGS_TUNE_ONLY` names the curves it may change.
/// `NINE_RINGS_REPORT3=1` only prints the room along the path.
@Suite struct RingThreeTuneTests {
    typealias Keys = [String: [(Double, Double)]]

    static let names = ["ring2.lid", "ring2.tilt", "ring2.swing", "ring3.tip", "ring3.tilt", "ring3.swing", "ring3.eye", "sword"]

    static var initial: Keys {
        if let text = ProcessInfo.processInfo.environment["NINE_RINGS_PATH3"], let parsed = parse(text) { return parsed }
        return RingThreeOff.keys
    }

    static func parse(_ text: String) -> Keys? {
        var keys: Keys = RingThreeOff.keys
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

    static func path(_ keys: Keys) -> RingThreeOff? {
        for name in names {
            let progress = keys[name]!.map(\.0)
            guard zip(progress, progress.dropFirst()).allSatisfy({ $0 < $1 - 0.008 }), progress.first! >= 0, progress.last! <= 1 else { return nil }
        }
        return RingThreeOff(keys: keys)
    }

    static let moving: Set<PartName> = [
        .ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2), .bead(2),
        .ring(3), .eye(3), .shaft(3), .bead(3), .sword,
    ]

    /// The room at one point of the path, or a negative penalty when something is wrong.
    static func room(_ path: RingThreeOff, at parameter: Double, previous: ToyPose? = nil) -> (room: Double, why: String) {
        let pose = path.pose(at: parameter)
        var penalty = 0.0
        var why: [String] = []
        for ring in 1...3 {
            let rodDown = simd_normalize(Layout.hole(ring) - pose.rod(ring).position)
            let wire = pose.ring(ring).worldDirection(SIMD3(1, 0, 0))
            let wireAngle = asin(min(1, abs(simd_dot(wire, rodDown)))) * 180 / .pi
            if wireAngle > 55 { penalty += (wireAngle - 55) / 10 + 1; why.append("wire along rod \(ring)") }
        }
        let failures = Relations.failures(in: pose, mayBeOff: [1, 2, 3])
            + (previous.map { Relations.railChangeFailures(from: $0, to: pose) } ?? [])
        if !failures.isEmpty { penalty += Double(failures.count); why += failures }
        let holeRoom = Relations.holeRoom(1, in: pose) ?? -1
        if holeRoom < 0.05 { penalty += (0.05 - holeRoom) * 10 + 0.5; why.append("rod 1 tight in its hole \(holeRoom)") }

        let shapes = pose.shapes
        let withoutBar = shapes.filter { $0.name != .bar }
        let gap = Gaps.smallest(in: withoutBar, involving: moving)
        // Bead 1 rises toward the bar; it should keep at least the resting gap.
        let beadOne = Gaps.smallest(in: shapes.filter { $0.name == .bar || $0.name == .bead(1) })?.distance ?? 10
        let beadRoom = (beadOne - Layout.restingGap) * 6 + 1.5
        if let gap { why.append("\(gap)") }
        let room = min(gap?.distance ?? 10, beadRoom, 1.5)
        return penalty > 0 ? (min(room, 0) - penalty, why.joined(separator: "; ")) : (room, why.joined(separator: "; "))
    }

    static func score(_ keys: Keys, samples: Int = 300) -> Double {
        guard let path = path(keys) else { return -100 }
        let progress = (0...samples).map { Double($0) / Double(samples) }
        let rooms = Sweep.inParallel(progress.count) { index in
            let previous = index > 0 ? path.pose(at: progress[index - 1]) : nil
            return room(path, at: progress[index], previous: previous).room
        }
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
                let fixedProgress = (name == "ring2.lid" || name == "sword") && isEnd
                let fixedValue = isEnd && !["ring2.swing", "ring2.tilt"].contains(name)
                if !fixedProgress { list.append(Item(name: name, key: k, isProgress: true, step: 0.01)) }
                if !fixedValue { list.append(Item(name: name, key: k, isProgress: false, step: ["ring3.eye", "sword"].contains(name) ? 0.8 : 6)) }
            }
        }
        return list
    }

    static func nudge(_ keys: inout Keys, _ item: Item, by amount: Double) {
        if item.isProgress { keys[item.name]![item.key].0 += amount } else { keys[item.name]![item.key].1 += amount }
        // The swing of ring 2 starts and ends at zero.
        if ["ring2.swing", "ring2.tilt"].contains(item.name) && !item.isProgress && (item.key == 0 || item.key == keys[item.name]!.count - 1) {
            keys[item.name]![item.key].1 = 0
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_TUNE3"] != nil))
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
            print("NINE_RINGS_PATH3='\(Self.text(best))'")
            if !improved { scale /= 2 }
            if scale < 0.05 { break }
        }
        print("best room \(bestScore)")
        print("NINE_RINGS_PATH3='\(Self.text(best))'")
        print("check with 1200 samples: \(Self.score(best, samples: 1200))")
        Self.report(best)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_REPORT3"] != nil))
    func reportOnly() {
        Self.report(Self.initial)
    }

    /// Prints the room along the path, a line per hundredth.
    static func report(_ keys: Keys) {
        guard let path = path(keys) else { return }
        for index in 0...100 {
            let parameter = Double(index) / 100
            let previous = index > 0 ? path.pose(at: Double(index - 1) / 100) : nil
            let pose = path.pose(at: parameter)
            let (room, why) = room(path, at: parameter, previous: previous)
            let on = [1, 2, 3].map { Relations.isRoundTheRails($0, in: pose) ? "on " : "off" }.joined(separator: " ")
            let eye = pose.rod(1).position
            print(String(format: "path %.2f room %6.3f  %@ sword %5.1f eye1 (%5.1f %5.1f %5.1f) ", parameter, room, on, pose.swordSlide, eye.x, eye.y, eye.z) + why)
        }
    }
}
