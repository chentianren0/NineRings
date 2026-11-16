import Foundation
import Toy

/// How long a move takes at full speed, and how far through it the move is at each moment.
///
/// A move's poses are a function of its progress, from 0 to 1, which the slider drags. The timing sits beside them and
/// changes none of them: it maps a moment of the move, in seconds, to the progress there, and back, so that a move
/// played at full speed passes through its stages in its own time.
///
/// - Ring 1's move takes ``baseDuration``, at the even pace its pacing gives (see ``Pacing``).
/// - The second ring's move takes ``baseDuration`` for ring 2, the same way. For ring k it is the same move one hole
///   further along, except that the sword starts from home and so is drawn back one hole further for each ring after
///   ring 2, and comes home as far. Ring k's moves keep ring 2's time, moment for moment, with the sword's added travel
///   covered at ``slideSpeed``: at each point of the path, the time is ring 2's time there, plus how much further ring
///   k's sword has slid by then than ring 2's, divided by that speed. While ring k itself moves the sword is one hole
///   further along for each ring and has slid no further, so those stages take ring 2's seconds; the move as a whole
///   takes 15 (k − 2) mm each way longer, half a second for each ring after ring 2.
///
/// The time is a smooth function of the path's own parameter, so the speed of every part stays continuous: where the
/// sword's added slide begins and ends, its rate blends into ring 2's.
public struct MoveTiming: Sendable {
    /// How long ring 1's move and ring 2's take at full speed, in seconds.
    public static let baseDuration = 3.0

    /// How fast the sword covers the travel that each ring after ring 2 adds, in millimetres a second. It is ring 2's
    /// own pace: its sword slides from home to its first key, 21.5 mm, at 56 mm a second on average. In round numbers,
    /// each ring after ring 2 adds 30 mm of travel and half a second.
    public static let slideSpeed = 60.0

    /// How long the move takes at full speed, in seconds.
    public let duration: Double

    /// The moment, in seconds, at a progress, and the progress at a moment; both increasing, between 0 and 1 and 0 and
    /// `duration`.
    private let timeAtProgress: @Sendable (Double) -> Double
    private let progressAtTime: @Sendable (Double) -> Double
    /// Whether the progress goes evenly with time, which running backwards keeps.
    private let isEven: Bool

    private init(
        duration: Double, isEven: Bool = false, timeAtProgress: @escaping @Sendable (Double) -> Double,
        progressAtTime: @escaping @Sendable (Double) -> Double
    ) {
        self.duration = duration
        self.isEven = isEven
        self.timeAtProgress = timeAtProgress
        self.progressAtTime = progressAtTime
    }

    /// A move whose progress goes evenly with time.
    static func evenly(_ duration: Double) -> MoveTiming {
        MoveTiming(duration: duration, isEven: true, timeAtProgress: { $0 * duration }, progressAtTime: { $0 / duration })
    }

    /// The second ring's move coming off, for ring `ring`.
    ///
    /// Everything is worked out through ring 2's progress, whose time is simply `baseDuration` times it: a point of the
    /// path is reached by ring 2 at its progress there, and by ring k that much later as its sword has slid further.
    static func pair(ring: Int) -> MoveTiming {
        guard ring > 2 else { return .evenly(baseDuration) }
        let two = PairMoveOff.paced[0], here = PairMoveOff.paced[ring - 2]
        let added = Double(ring - 2) * Dimensions.Bar.holePitch
        /// How much further ring k's sword has slid than ring 2's by the path's parameter `parameter`: going out, the
        /// difference of their slides, which grows to one hole for each ring after ring 2; coming home, that and what
        /// the difference has fallen back by.
        @Sendable func addedTravel(_ parameter: Double) -> Double {
            let difference = here.path.swordSlide.value(at: parameter) - two.path.swordSlide.value(at: parameter)
            return parameter <= 0.5 ? difference : 2 * added - difference
        }
        /// The moment at which ring k reaches the point of the path that ring 2 reaches at progress `ringTwos`.
        @Sendable func time(atRingTwosProgress ringTwos: Double) -> Double {
            baseDuration * ringTwos + addedTravel(two.pacing.pathParameter(atProgress: ringTwos)) / slideSpeed
        }
        return MoveTiming(
            duration: baseDuration + 2 * added / slideSpeed,
            timeAtProgress: { progress in
                time(atRingTwosProgress: two.pacing.progress(atPathParameter: here.pacing.pathParameter(atProgress: progress)))
            },
            progressAtTime: { moment in
                // Ring 2's progress at that moment, found by halving, then ring k's at the same point of the path.
                var low = 0.0, high = 1.0
                for _ in 0..<60 {
                    let middle = (low + high) / 2
                    if time(atRingTwosProgress: middle) < moment { low = middle } else { high = middle }
                }
                return here.pacing.progress(atPathParameter: two.pacing.pathParameter(atProgress: (low + high) / 2))
            }
        )
    }

    /// The same move run backwards, as a ring going on runs its coming off.
    var reversed: MoveTiming {
        if isEven { return self }
        let duration = duration, forwardTime = timeAtProgress, forwardProgress = progressAtTime
        return MoveTiming(
            duration: duration,
            timeAtProgress: { duration - forwardTime(1 - $0) },
            progressAtTime: { 1 - forwardProgress(duration - $0) }
        )
    }

    /// The moment, in seconds from the move's start, at which it reaches `progress`.
    public func time(atProgress progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return duration }
        return timeAtProgress(progress)
    }

    /// How far through the move it is `time` seconds from its start.
    public func progress(atTime time: Double) -> Double {
        if time <= 0 { return 0 }
        if time >= duration { return 1 }
        return progressAtTime(time)
    }
}
