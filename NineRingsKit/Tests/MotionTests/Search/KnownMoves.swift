import Foundation
import Geometry
@testable import Motion
import Puzzle
import Toy
import simd

/// The two written moves as `KeyedMove`s, with the numbers today's tuners leave free, and the full check a path
/// must pass.
extension KeyedMove {
    /// Ring 1's drop, as `TuneTests` tunes it: the tip, tilt, swing and eye curves from path parameter 0.55 on.
    static let ringOne = KeyedMove(
        channels: [
            Channel(name: "tip", freeProgress: [false, true, true, true], freeValue: [false, true, true, false], valueStep: 8),
            Channel(name: "tilt", freeProgress: [true, true, true, false], freeValue: [false, true, true, false], valueStep: 8),
            Channel(name: "swing", freeProgress: [true, true, true, true, true], freeValue: [false, true, true, true, false], valueStep: 8),
            Channel(name: "eye", freeProgress: [false, true, true, true], freeValue: [false, true, true, false], valueStep: 0.8),
        ],
        span: 0.55...1,
        progressStep: 0.015,
        room: FastRoom(moving: [1], swordMoves: false, mayBeOff: [1]),
        path: { keys in
            let path = ringOnePath(keys)
            return { path.pose(at: $0) }
        }
    )

    static func ringOnePath(_ keys: Keys) -> RingOneOff {
        var path = RingOneOff.written
        path.turns.tip = RingOneOff.degrees(keys["tip"]!)
        path.turns.tilt = RingOneOff.degrees(keys["tilt"]!)
        path.turns.swing = RingOneOff.degrees(keys["swing"]!)
        path.turns.eyeHeight = RingOneOff.millimetres(keys["eye"]!)
        return path
    }

    /// Ring 1's drop as written.
    static let ringOneWritten: Keys = [
        "tip": [(0.55, 0), (0.6036, 22.401), (0.7267, 84.416), (0.9384, 180 - RingOneOff.leanHangingDegrees)],
        "tilt": [(0.5694, 0), (0.677, 36.106), (0.6882, 58.639), (1, 90)],
        "swing": [(0.585, 0), (0.6842, 29.932), (0.706, 2.61), (0.7734, -26.703), (0.8983, 0)],
        "eye": [(0.56, Layout.eyeHeightOn), (0.6583, -3.653), (0.8198, -6.088), (0.9549, Layout.eyeHeightHanging)],
    ]

    /// The hand guess that `TuneTests` starts from, as committed with it.
    static let ringOneHandGuess: Keys = [
        "tip": [(0.55, 0), (0.62, 25), (0.72, 90), (0.92, 180 - RingOneOff.leanHangingDegrees)],
        "tilt": [(0.57, 0), (0.66, 40), (0.72, 65), (1, 90)],
        "swing": [(0.60, 0), (0.68, 25), (0.72, 0), (0.78, -30), (0.92, 0)],
        "eye": [(0.56, Layout.eyeHeightOn), (0.64, -4), (0.80, -6.5), (0.95, Layout.eyeHeightHanging)],
    ]

    /// Ring 2's whole move, as `RingTwoTuneTests` tunes it: every key's place and value free but the ends'.
    static let ringTwo: KeyedMove = {
        let channels = RingTwoTuneTests.names.map { name -> Channel in
            let count = RingTwoOff.keys[name]!.count
            let fixedEnds = name == "ring1.lid" || name == "sword"
            return Channel(
                name: name,
                freeProgress: (0..<count).map { !(fixedEnds && ($0 == 0 || $0 == count - 1)) },
                freeValue: (0..<count).map { $0 != 0 && $0 != count - 1 },
                valueStep: ["ring2.eye", "sword"].contains(name) ? 0.8 : 6
            )
        }
        return KeyedMove(
            channels: channels,
            span: 0...1,
            room: FastRoom(moving: [1, 2], swordMoves: true, mayBeOff: [1, 2]),
            path: { keys in
                let path = RingTwoOff(keys: keys)
                return { path.pose(at: $0) }
            }
        )
    }()

    /// Ring 2's keys with every free number rounded as a person writing a first guess from the stages would
    /// write it: places to 0.05, angles to 10°, lengths to a millimetre.
    static var ringTwoRounded: Keys {
        var keys = RingTwoOff.keys
        for channel in ringTwo.channels {
            keys[channel.name] = keys[channel.name]!.enumerated().map { index, key in
                let place = channel.freeProgress[index] ? (key.0 * 20).rounded() / 20 : key.0
                let unit = channel.valueStep < 1 ? 1.0 : 10.0
                let value = channel.freeValue[index] ? (key.1 / unit).rounded() * unit : key.1
                return (place, value)
            }
        }
        return keys
    }

    /// `keys` with every free number shaken by a normal step of `scale` units.
    func shaken(_ keys: Keys, scale: Double, seed: UInt64) -> Keys {
        var random = SeededRandom(seed: seed)
        return self.keys(vector(keys).map { $0 + scale * random.normal() }, base: keys)
    }
}

/// The checker's own tests of a move, run on a path given as keys: 4000 samples of the move's progress, paced as
/// the app paces it, every pair of parts, every relation, and the largest step.
enum FullCheck {
    struct Report: CustomStringConvertible {
        var smallestGap: Gap
        var gapProgress: Double
        /// The smallest gap of any pair but a bead and the bar, which rest 0.25 mm apart by design.
        var smallestMovingGap: Gap
        var firstFailure: (Double, [String])?
        var largestStep: Double

        var passes: Bool { smallestGap.distance >= smallestAllowedGap && firstFailure == nil && largestStep <= largestAllowedStep }
        var description: String {
            "smallest gap \(smallestGap) at progress \(String(format: "%.4f", gapProgress)); apart from a resting bead \(smallestMovingGap); "
                + (firstFailure.map { "fails at \(String(format: "%.4f", $0.0)): \($0.1)" } ?? "no relation fails")
                + String(format: "; largest step %.3f mm", largestStep) + (passes ? "; PASSES" : "; does not pass")
        }
    }

    static func run(_ pathPose: @escaping @Sendable (Double) -> ToyPose, mayBeOff: Set<Int>, samples: Int = Sweep.samples) -> Report {
        let pacing = Pacing(pathPose)
        let progress = (0...samples).map { Double($0) / Double(samples) }
        let poses = progress.map { pathPose(pacing.pathParameter(atProgress: $0)) }
        let gaps = Sweep.inParallel(poses.count) { Gaps.smallest(in: poses[$0].shapes)! }
        let failures = Sweep.inParallel(poses.count) { index in
            Relations.failures(in: poses[index], mayBeOff: mayBeOff)
                + (index > 0 ? Relations.railChangeFailures(from: poses[index - 1], to: poses[index]) : [])
        }
        let steps = zip(poses, poses.dropFirst()).map { Relations.largestStep(from: $0, to: $1).distance }
        let smallest = gaps.indices.min { gaps[$0].distance < gaps[$1].distance }!
        let withoutBeads = Sweep.inParallel(poses.count) { index in
            Gaps.smallest(in: poses[index].shapes.filter { $0.name != .bar })!
        }
        let movingGap = withoutBeads.min { $0.distance < $1.distance }!
        let failing = failures.firstIndex { !$0.isEmpty }
        return Report(
            smallestGap: gaps[smallest], gapProgress: progress[smallest], smallestMovingGap: movingGap,
            firstFailure: failing.map { (progress[$0], failures[$0]) },
            largestStep: steps.max() ?? 0
        )
    }
}
