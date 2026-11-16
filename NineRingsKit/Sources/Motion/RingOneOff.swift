import Foundation
import Puzzle
import Toy
import simd

/// The written path of ring 1 coming off while every other ring is on.
///
/// The path is a handful of numbers, each a ``Curve`` of the progress, and one rule that turns them into where the
/// ring is (see ``RingTurns``). Every turn of the ring is about an axis through its eye, so the eye is where the
/// eye's numbers put it:
///
/// - `lid`: the ring swings about the line of its wire through the eye, from leaning down toward the tip, through
///   lying flat, to standing straight up over its eye.
/// - `turn`: standing on its eye, the ring turns about the upright, from across the sword to along it.
/// - `tip`: the ring tips over toward the tip, about the line across the sword through the eye.
/// - `tilt`: at the same time it rolls about the line from the eye to its middle, so that its wire through the eye
///   stays within reach of level while it tips past lying on its side, and it ends hanging across the sword.
/// - `swing`: and it swings about the upright, first to one side and then to the other, so that the part of it
///   still above the rails is carried in over the slot rather than onto a rail.
///
/// The eye stays put above its hole until the ring goes down; then it goes down into the slot first. The ring
/// tips over and slips through the slot at a slant, partly over one rail and partly under the other, and comes to
/// hang across the sword in front of ring 2's lower arc. Only then does the eye sink below the rails, just above
/// ring 2's lower arc, and the rod leave the slot: while the eye is that low, ring 2's lower arc wraps round under
/// it so closely that ring 1 can only lie across the sword, and lying across it cannot pass between the rails.
///
/// The sword slides toward the grip to bring its tip end under the ring for the lift over it, then back home so
/// that the slot is long enough in front of the eye for the drop.
///
/// The drop's key values were found by a search for the path with the most room (see `TuneTests`), and are
/// written here as plain numbers.
struct RingOneOff: Sendable {
    /// The stages, as spans of the path's own parameter (see ``timing``).
    static let stagesAlongThePath = [
        Stage(name: "Flatten", start: 0, end: 0.16),
        Stage(name: "Over the tip", start: 0.16, end: 0.30),
        Stage(name: "Back over the slot", start: 0.30, end: 0.42),
        Stage(name: "Turn", start: 0.42, end: 0.56),
        Stage(name: "Down through the slot", start: 0.56, end: 0.84),
        Stage(name: "Hang", start: 0.84, end: 1),
    ]

    static func degrees(_ keys: [(Double, Double)]) -> Curve { RingTurns.degrees(keys) }
    static func millimetres(_ keys: [(Double, Double)]) -> Curve { RingTurns.millimetres(keys) }

    static let leanOnDegrees = RingTurns.leanOnDegrees
    static let leanHangingDegrees = RingTurns.leanHangingDegrees

    var turns: RingTurns
    var swordSlide: Curve

    /// The path as written.
    static let written = RingOneOff(
        turns: RingTurns(
            lid: degrees([(0, leanOnDegrees), (0.16, 76), (0.30, 130), (0.45, 180)]),
            turn: degrees([(0.39, 0), (0.56, 90)]),
            tip: degrees([(0.55, 0), (0.6036, 22.401), (0.7267, 84.416), (0.9384, 180 - leanHangingDegrees)]),
            tilt: degrees([(0.5694, 0), (0.677, 36.106), (0.6882, 58.639), (1, 90)]),
            swing: degrees([(0.585, 0), (0.6842, 29.932), (0.706, 2.61), (0.7734, -26.703), (0.8983, 0)]),
            eyeHeight: millimetres([(0.56, Layout.eyeHeightOn), (0.6583, -3.653), (0.8198, -6.088), (0.9549, Layout.eyeHeightHanging)])
        ),
        swordSlide: millimetres([(0, Layout.swordHome), (0.18, 12.5), (0.40, Layout.swordHome)])
    )

    /// Ring 1 as its rod holds it, at `progress` along the path's own parameter.
    func held(at progress: Double) -> HeldRing {
        turns.held(1, at: progress)
    }

    /// The toy at `progress` along the path's own parameter, with the rings behind ring 1 resting as they do in
    /// `state`. They keep still whatever they are: ring 1 comes off in front of them all.
    func pose(at progress: Double, from state: PuzzleState = .allOn) -> ToyPose {
        var rings = PuzzleState.rings.map { RestPoses.resting($0, in: state) }
        rings[0] = held(at: progress)
        return RestPoses.pose(holding: rings, swordSlide: swordSlide.value(at: progress))
    }

    // MARK: Timing

    /// How the move's progress maps onto the path's own parameter (see ``Pacing``). The rings behind keep still, so
    /// it is the same whatever they are.
    static let pacing = Pacing { written.pose(at: $0) }

    static var timing: Curve { pacing.timing }

    /// The stages as spans of the move's progress.
    static let stages: [Stage] = pacing.stages(stagesAlongThePath)

    /// The toy a fraction `progress` of the way through the move, the rings behind resting as in `state`.
    static func pose(atProgress progress: Double, from state: PuzzleState = .allOn) -> ToyPose {
        written.pose(at: pacing.pathParameter(atProgress: progress), from: state)
    }
}
