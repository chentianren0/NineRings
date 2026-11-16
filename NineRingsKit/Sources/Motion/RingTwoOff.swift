import Foundation
import Puzzle
import Toy
import simd

/// The written path of ring 2 coming off while every other ring is on: ring 1 steps aside, ring 2 comes off over
/// the tip and goes down through the slot round rod 1, and ring 1 goes back on.
///
/// Three things move, each by curves of the path's own parameter (see ``RingTurns``):
///
/// - Ring 1 stands up on its eye and turns to stand along the sword, then turns back and lies down again. Its eye
///   never moves: rod 1 stays where it is, down through the slot and through ring 2.
/// - Ring 2 is written as standing along the sword and then tipped over toward the tip, tilted and swung. Tipped
///   by 137° and tilted by 90° it leans across the sword as it does when it is on.
/// - The sword slides toward the grip and back.
///
/// Ring 1 cannot stay where it is: its lower part is where ring 2 must go to pass over the tip, and while ring 2
/// stays round rod 1 it cannot get past eye 1 and ring 1 any other way. So first the sword is drawn back, and the
/// tip passes out of ring 1 as ring 1 lifts: ring 1 is off the rails, over the tip end, without its eye moving.
/// It stands up on its eye and turns to stand along the sword, above the slot, where ring 2's tilted side cannot
/// reach it.
///
/// Then ring 2 swings up about its wire through the eye until it lies nearly flat over the tip end, which by now
/// is drawn back almost to rod 1: the tip passes out of ring 2. Rod 1 still runs down through ring 2, just under
/// eye 1, and that is what lets ring 2 go down through the slot: rod 1 is in the slot too.
///
/// The sword slides back toward the tip, under ring 2, to give the slot in front of ring 2 the length ring 1 had
/// for its own drop. Ring 2 swings to one side and tilts, so that its lower side goes down inside the slot; then
/// it slips through at a slant, partly over one rail and partly under the other, the way ring 1 does, and comes to
/// hang across the sword in front of ring 3's lower arc. Its eye sinks below the rails last.
///
/// Last, ring 1 turns back and lies down over the tip as the sword goes home: ring 1 is on again.
///
/// The key values of ring 2's path and the sword's were found by a search for the path with the most room (see
/// `RingTwoTuneTests`), and are written here as plain numbers.
struct RingTwoOff: Sendable {
    /// The stages, as spans of the path's own parameter.
    static let stagesAlongThePath = [
        Stage(name: "Ring 1 steps aside", start: 0, end: 0.22),
        Stage(name: "Ring 2 over the tip", start: 0.22, end: 0.40),
        Stage(name: "Down through the slot", start: 0.40, end: 0.75),
        Stage(name: "Ring 2 hangs", start: 0.75, end: 0.82),
        Stage(name: "Ring 1 back on", start: 0.82, end: 1),
    ]

    var ringOne: RingTurns
    var ringTwo: RingTurns
    var swordSlide: Curve

    static let leanOn = RingTurns.leanOnDegrees
    /// Ring 2's tip when it rests on the rails or hangs: 180° less its lean.
    static let tipOn = 180 - RingTurns.leanOnDegrees
    static let tipHanging = 180 - RingTurns.leanHangingDegrees

    /// The keys as written, each curve's keys as (path parameter, value) pairs, angles in degrees and lengths in
    /// millimetres.
    static let keys: [String: [(Double, Double)]] = [
        "ring1.lid": [(0, leanOn), (0.10, 100), (0.17, 180), (0.84, 180), (0.92, 100), (1, leanOn)],
        "ring1.turn": [(0.13, 0), (0.21, 90), (0.80, 90), (0.88, 0)],
        "ring2.tip": [(0.20, tipOn), (0.368, 93.718), (0.642, 84.795), (0.776, tipHanging)],
        "ring2.tilt": [(0.4763, 90), (0.5629, 62.031), (0.82, 90)],
        "ring2.swing": [(0.4289, 0), (0.5428, 24.742), (0.6231, 4.12), (0.6951, -27.2), (0.7857, 0)],
        "ring2.eye": [(0.5022, Layout.eyeHeightOn), (0.6480, -4.475), (0.7419, -5.977), (0.796, Layout.eyeHeightHanging)],
        "sword": [(0, Layout.swordHome), (0.14, 20.4), (0.28, 25.4), (0.39, 27.8), (0.4911, 15.841), (0.94, 15.841), (1, Layout.swordHome)],
    ]

    /// The path from a set of keys, named as in ``keys``.
    init(keys: [String: [(Double, Double)]]) {
        func curve(_ name: String, degrees: Bool) -> Curve {
            guard let keys = keys[name] else { preconditionFailure("no keys for \(name)") }
            return degrees ? RingTurns.degrees(keys) : RingTurns.millimetres(keys)
        }
        ringOne = RingTurns(
            lid: curve("ring1.lid", degrees: true),
            turn: curve("ring1.turn", degrees: true),
            tip: Curve(constant: 0),
            tilt: Curve(constant: 0),
            swing: Curve(constant: 0),
            eyeHeight: Curve(constant: Layout.eyeHeightOn)
        )
        ringTwo = RingTurns(
            lid: Curve(constant: .pi),
            turn: Curve(constant: .pi / 2),
            tip: curve("ring2.tip", degrees: true),
            tilt: curve("ring2.tilt", degrees: true),
            swing: curve("ring2.swing", degrees: true),
            eyeHeight: curve("ring2.eye", degrees: false)
        )
        swordSlide = curve("sword", degrees: false)
    }

    /// The path as written.
    static let written = RingTwoOff(keys: keys)

    /// The toy at `progress` along the path's own parameter.
    func pose(at progress: Double) -> ToyPose {
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = ringOne.held(1, at: progress)
        rings[1] = ringTwo.held(2, at: progress)
        return RestPoses.pose(holding: rings, swordSlide: swordSlide.value(at: progress))
    }

    // MARK: Timing

    /// How the move's progress maps onto the path's own parameter (see ``Pacing``).
    static let pacing = Pacing(written.pose(at:))

    /// The stages as spans of the move's progress.
    static let stages: [Stage] = pacing.stages(stagesAlongThePath)

    /// The toy a fraction `progress` of the way through the move.
    static func pose(atProgress progress: Double) -> ToyPose {
        written.pose(at: pacing.pathParameter(atProgress: progress))
    }
}
