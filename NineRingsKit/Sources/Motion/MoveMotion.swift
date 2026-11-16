import Puzzle
import Toy

/// A move played back: the pose of the whole toy as a pure function of how far the move has gone.
///
/// Nothing is simulated and nothing depends on time or on earlier calls: the same progress always gives the same
/// pose, so a slider can drag a move either way. Progress 0 is the rest pose of the state before the move and
/// progress 1 the rest pose of the state after it.
///
/// A ring going on follows the very path of that ring coming off, run backwards.
///
/// The toy has two moves: ring 1's (``RingOneOff``), and the second ring on the sword's (``PairMoveOff``), the same for
/// rings 2 to 9, one hole further along for each.
public struct MoveMotion: Sendable {
    public let move: Move

    /// How long the move takes at full speed and where it is at each moment (see ``MoveTiming``). The poses go by
    /// progress; the timing only says when the move reaches each progress.
    public var timing: MoveTiming {
        let comingOff = move.ring == 1 ? MoveTiming.evenly(MoveTiming.baseDuration) : MoveTiming.pair(ring: move.ring)
        return move.takesOff ? comingOff : comingOff.reversed
    }

    /// How long the move takes at full speed, in seconds.
    public var duration: Double { timing.duration }

    /// The motion of `move`: ring 1's, or the second ring on the sword's, which is one move for rings 2 to 9
    /// (``PairMoveOff``). Each comes off from any state the rule allows, whatever the rings behind are, and goes back on
    /// along the same path.
    public init(_ move: Move) {
        self.move = move
    }

    /// One move for each ring, the menu of written moves: each ring coming off where it first does on the way from
    /// every ring on to every ring off, ring k−1 on with every ring in front of it off and every ring behind it on.
    /// Each goes back on along the same path.
    public static let written: [Move] = PuzzleState.rings.compactMap { Move(ring: $0, from: PairMoveOff.firstPlace($0)) }

    /// The toy a fraction `progress` of the way through the move. Progress outside 0...1 is held at the ends.
    public func pose(at progress: Double) -> ToyPose {
        let progress = offProgress(progress)
        // The state with the ring on, where coming off begins.
        let on = move.takesOff ? move.from : move.to
        return move.ring == 1
            ? RingOneOff.pose(atProgress: progress, from: on)
            : PairMoveOff.pose(ring: move.ring, from: on, atProgress: progress)
    }

    /// The stages in the order the move goes through them, each with its span of progress.
    public var stages: [Stage] {
        let comingOff = move.ring == 1 ? RingOneOff.stages : PairMoveOff.stages(ring: move.ring)
        if move.takesOff { return comingOff }
        let keys = move.ring == 1 ? Self.ringOneKeysGoingOn : Self.pairKeysGoingOn
        return zip(comingOff.reversed(), keys).map { stage, key in
            Stage(key: key, ring: key.contains("%lld") ? move.ring : nil, start: 1 - stage.end, end: 1 - stage.start)
        }
    }

    /// The stages in the order the move goes through them, each with its span in seconds from the move's start, at
    /// full speed.
    public var timedStages: [Stage] {
        let timing = timing
        return stages.map { $0.spanning(from: timing.time(atProgress: $0.start), to: timing.time(atProgress: $0.end)) }
    }

    /// The stage at `progress`; at a boundary, the one that begins there.
    public func stage(at progress: Double) -> Stage {
        let stages = stages
        return stages.last { $0.start <= progress } ?? stages[0]
    }

    /// Going on, the stages of coming off are passed through backwards, under names that say what happens.
    private static let ringOneKeysGoingOn = [
        "Lift", "Up through the slot", "Turn", "Out past the tip", "Over the tip", "Lean",
    ]

    private static let pairKeysGoingOn = [
        "Sword moves away", "Ring %lld lifts", "Up through the slot", "Ring %lld over the tip", "Sword comes back",
    ]

    private func offProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return move.takesOff ? clamped : 1 - clamped
    }
}
