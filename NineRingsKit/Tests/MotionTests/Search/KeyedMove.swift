import Foundation
import Geometry
@testable import Motion
import Puzzle
import Toy
import simd

/// A move written as keys, as `RingOneOff` and `RingTwoOff` write theirs: for each named curve, (path parameter,
/// value) pairs, angles in degrees and lengths in millimetres. Some numbers are free for a search to change, each
/// with a step that says how far a change of one unit goes.
struct KeyedMove: Sendable {
    typealias Keys = [String: [(Double, Double)]]

    struct Channel: Sendable {
        var name: String
        /// For each key: whether its parameter is free, and whether its value is free.
        var freeProgress: [Bool]
        var freeValue: [Bool]
        /// How far one unit of the search moves a value.
        var valueStep: Double
    }

    var channels: [Channel]
    /// Where the search may put keys, and where the path is sampled: the part of the path that the search changes.
    var span: ClosedRange<Double>
    /// The least distance between two keys of a curve.
    var spacing = 0.008
    /// How far one unit of the search moves a key's parameter.
    var progressStep = 0.01
    /// The room of a pose.
    var room: FastRoom
    /// The values each curve may take, where limited: a value the search moves outside is put back at the limit.
    var bounds: [String: ClosedRange<Double>] = [:]
    /// The path for a set of keys, as a pose for each path parameter.
    var path: @Sendable (Keys) -> @Sendable (Double) -> ToyPose

    // MARK: Free numbers as a vector

    /// The free numbers of `keys`, each divided by its step.
    func vector(_ keys: Keys) -> [Double] {
        var vector: [Double] = []
        for channel in channels {
            for (index, key) in keys[channel.name]!.enumerated() {
                if channel.freeProgress[index] { vector.append(key.0 / progressStep) }
                if channel.freeValue[index] { vector.append(key.1 / channel.valueStep) }
            }
        }
        return vector
    }

    /// `keys` with its free numbers taken from `vector`, then put in order: within each curve the keys stay in
    /// their order, at least `spacing` apart, and inside `span`.
    func keys(_ vector: [Double], base: Keys) -> Keys {
        var keys = base
        var cursor = 0
        for channel in channels {
            var list = base[channel.name]!
            for index in list.indices {
                if channel.freeProgress[index] { list[index].0 = vector[cursor] * progressStep; cursor += 1 }
                if channel.freeValue[index] {
                    list[index].1 = vector[cursor] * channel.valueStep
                    if let range = bounds[channel.name] { list[index].1 = min(max(list[index].1, range.lowerBound), range.upperBound) }
                    cursor += 1
                }
            }
            keys[channel.name] = ordered(list, channel)
        }
        return keys
    }

    private func ordered(_ list: [(Double, Double)], _ channel: Channel) -> [(Double, Double)] {
        var list = list
        let count = list.count
        // Free parameters stay inside the span with room for the keys either side.
        for index in list.indices where channel.freeProgress[index] {
            let lower = span.lowerBound + Double(index) * spacing
            let upper = span.upperBound - Double(count - 1 - index) * spacing
            list[index].0 = min(max(list[index].0, lower), upper)
        }
        // Then each at least `spacing` after the one before, pushing forward, and back from the end.
        for index in 1..<max(count, 1) where list[index].0 < list[index - 1].0 + spacing {
            if channel.freeProgress[index] { list[index].0 = list[index - 1].0 + spacing }
        }
        for index in stride(from: count - 2, through: 0, by: -1) where list[index].0 > list[index + 1].0 - spacing {
            if channel.freeProgress[index] { list[index].0 = list[index + 1].0 - spacing }
        }
        return list
    }

    var dimension: Int {
        channels.reduce(0) { $0 + $1.freeProgress.filter { $0 }.count + $1.freeValue.filter { $0 }.count }
    }

    // MARK: Scoring

    struct Score: CustomStringConvertible {
        /// The least room along the path; below zero when something fails.
        var least: Double
        /// The mean room, capped, which breaks ties.
        var mean: Double
        var worstParameter: Double
        var worst: FastRoom.Room?

        var value: Double { least + 0.02 * mean }
        var description: String {
            String(format: "least %.4f at %.4f", least, worstParameter) + (worst.map { " (\($0))" } ?? "")
        }
    }

    /// Whether `keys` make a valid set of curves: in order, inside 0...1.
    func isValid(_ keys: Keys) -> Bool {
        keys.values.allSatisfy { list in
            zip(list, list.dropFirst()).allSatisfy { $0.0 < $1.0 } && (list.first?.0 ?? 0) >= 0 && (list.last?.0 ?? 1) <= 1
        }
    }

    /// The room along the path at `samples` evenly spaced parameters of the span, with a ring leaving or joining
    /// the rails away from the tip end between two samples counted as a failure.
    func score(_ keys: Keys, samples: Int, offset: Double = 0, detail: Bool = false) -> Score {
        guard isValid(keys) else { return Score(least: -100, mean: -100, worstParameter: 0) }
        let pose = path(keys)
        var least = Double.infinity, total = 0.0, worstParameter = 0.0
        var worst: FastRoom.Room?
        var previous: ToyPose?
        for index in 0...samples {
            let parameter = span.lowerBound + (span.upperBound - span.lowerBound) * min(1, (Double(index) + offset) / Double(samples))
            let here = pose(parameter)
            var measured = room.room(here)
            if let previous { measured.failures += room.railChanges(from: previous, to: here) }
            let value = measured.value
            total += min(value, room.cap)
            if value < least {
                (least, worstParameter) = (value, parameter)
                if detail { worst = measured }
            }
            previous = here
        }
        return Score(least: least, mean: total / Double(samples + 1), worstParameter: worstParameter, worst: worst)
    }

    /// Keys as text, in the form today's tuners print and read: `name:p=v,p=v;name:...`.
    func text(_ keys: Keys) -> String {
        channels.map { channel in
            channel.name + ":" + keys[channel.name]!.map { String(format: "%.4f=%.3f", $0.0, $0.1) }.joined(separator: ",")
        }.joined(separator: ";")
    }

    static func parse(_ text: String, into base: Keys) -> Keys? {
        var keys = base
        for part in text.split(separator: ";") {
            let halves = part.split(separator: ":")
            guard halves.count == 2 else { return nil }
            keys[String(halves[0])] = halves[1].split(separator: ",").compactMap { pair in
                let numbers = pair.split(separator: "=").compactMap { Double($0) }
                return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
            }
        }
        return keys
    }

    /// Keys as Swift source, for writing into a path.
    func swift(_ keys: Keys) -> String {
        channels.map { channel in
            "\"\(channel.name)\": [" + keys[channel.name]!.map { String(format: "(%.4f, %.3f)", $0.0, $0.1) }.joined(separator: ", ") + "],"
        }.joined(separator: "\n")
    }
}
