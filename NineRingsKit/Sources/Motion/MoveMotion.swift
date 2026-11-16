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

    /// The motion of `move`, or nil when that move has not been written yet. So far three moves are written, each
    /// coming off and going back on: ring 1 and ring 2 with every other ring on, and ring 3 with ring 1 off and
    /// every other ring on.
    public init?(_ move: Move) {
        guard Self.written.contains(move) || Self.written.contains(move.reversed) else { return nil }
        self.move = move
    }

    /// The moves that are written, each coming off. Each goes back on along the same path.
    public static let written: [Move] = [
        Move(ring: 1, from: .allOn), Move(ring: 2, from: .allOn), Move(ring: 3, from: PuzzleState.allOn.moving(1)),
    ].compactMap { $0 }

    /// The toy a fraction `progress` of the way through the move. Progress outside 0...1 is held at the ends.
    public func pose(at progress: Double) -> ToyPose {
        let progress = offProgress(progress)
        switch move.ring {
        case 1: return RingOneOff.pose(atProgress: progress)
        case 2: return RingTwoOff.pose(atProgress: progress)
        default: return RingThreeOff.pose(atProgress: progress)
        }
    }

    /// The stages in the order the move goes through them, each with its span of progress.
    public var stages: [Stage] {
        let comingOff = [RingOneOff.stages, RingTwoOff.stages, RingThreeOff.stages][move.ring - 1]
        if move.takesOff { return comingOff }
        let names = [Self.ringOneNamesGoingOn, Self.ringTwoNamesGoingOn, Self.ringThreeNamesGoingOn][move.ring - 1]
        return zip(comingOff.reversed(), names).map { stage, name in
            Stage(name: name, start: 1 - stage.end, end: 1 - stage.start)
        }
    }

    /// The stage at `progress`; at a boundary, the one that begins there.
    public func stage(at progress: Double) -> Stage {
        let stages = stages
        return stages.last { $0.start <= progress } ?? stages[0]
    }

    /// Going on, the stages of coming off are passed through backwards, under names that say what happens.
    private static let ringOneNamesGoingOn = [
        "Lift", "Up through the slot", "Turn", "Out past the tip", "Over the tip", "Lean",
    ]

    private static let ringTwoNamesGoingOn = [
        "Ring 1 steps aside", "Ring 2 lifts", "Up through the slot", "Ring 2 over the tip", "Ring 1 back on",
    ]

    private static let ringThreeNamesGoingOn = [
        "Ring 2 steps aside", "Ring 3 lifts", "Up through the slot", "Ring 3 over the tip", "Ring 2 back on",
    ]

    private func offProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return move.takesOff ? clamped : 1 - clamped
    }
}
