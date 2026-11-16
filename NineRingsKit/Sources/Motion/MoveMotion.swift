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
/// rings 2 to 9, one hole further along for each. ``RingTwoOff``, ring 2 with ring 1 stepping aside, is kept beside
/// them with its tests, but the app plays the second ring's move for ring 2 as for the others.
public struct MoveMotion: Sendable {
    public let move: Move

    /// How long the move takes at full speed, in seconds.
    public static let duration = 3.0

    /// The motion of `move`. Every legal move is written: ring 1's, and the second ring on the sword's, which is one
    /// move for rings 2 to 9 (``PairMoveOff``). Each comes off from any state the rule allows, whatever the rings
    /// behind are, and goes back on along the same path. The initializer stays failable so that a move can be left
    /// unwritten again without changing its callers.
    public init?(_ move: Move) {
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
        let names = move.ring == 1 ? Self.ringOneNamesGoingOn : Self.pairNamesGoingOn(ring: move.ring)
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

    private static func pairNamesGoingOn(ring: Int) -> [String] {
        ["Sword moves away", "Ring \(ring) lifts", "Up through the slot", "Ring \(ring) over the tip", "Sword comes back"]
    }

    private func offProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return move.takesOff ? clamped : 1 - clamped
    }
}
