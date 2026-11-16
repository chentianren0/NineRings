import Puzzle
import Toy

/// A move played back: the pose of the whole toy as a pure function of how far the move has gone.
///
/// Nothing is simulated and nothing depends on time or on earlier calls: the same progress always gives the same
/// pose, so a slider can drag a move either way. Progress 0 is the rest pose of the state before the move and
/// progress 1 the rest pose of the state after it.
///
/// A ring going on follows the very path of that ring coming off, run backwards.
public struct MoveMotion: Sendable {
    public let move: Move

    /// How long the move takes at full speed, in seconds.
    public static let duration = 3.0

    /// The motion of `move`, or nil when that move has not been written yet. So far ring 1 is written, coming off
    /// with every other ring on and going back on.
    public init?(_ move: Move) {
        let written = move.ring == 1 && (move.from == .allOn || move.to == .allOn)
        guard written else { return nil }
        self.move = move
    }

    /// The toy a fraction `progress` of the way through the move. Progress outside 0...1 is held at the ends.
    public func pose(at progress: Double) -> ToyPose {
        RingOneOff.written.pose(at: offProgress(progress))
    }

    /// The stages in the order the move goes through them, each with its span of progress.
    public var stages: [Stage] {
        if move.takesOff { return RingOneOff.stages }
        return zip(RingOneOff.stages.reversed(), Self.namesGoingOn).map { stage, name in
            Stage(name: name, start: 1 - stage.end, end: 1 - stage.start)
        }
    }

    /// The stage at `progress`; at a boundary, the one that begins there.
    public func stage(at progress: Double) -> Stage {
        let stages = stages
        return stages.last { $0.start <= progress } ?? stages[0]
    }

    /// Going on, the stages of coming off are passed through backwards, under names that say what happens.
    private static let namesGoingOn = [
        "Lift", "Up through the slot", "Turn", "Out past the tip", "Over the tip", "Lean",
    ]

    private func offProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return move.takesOff ? clamped : 1 - clamped
    }
}
