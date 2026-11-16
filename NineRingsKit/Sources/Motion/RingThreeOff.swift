import Foundation
import Puzzle
import Toy
import simd

/// The written path of ring 3 coming off while ring 1 is off and every other ring is on: ring 2 steps aside, and
/// ring 1, which hangs from it, is lifted clear above it; ring 3 comes off over the tip and goes down through the
/// slot round rod 2; and ring 2 goes back on with ring 1 hanging from it again.
///
/// Four things are written, each by curves of the path's own parameter (see ``RingTurns``), and any rings that
/// hang below ring 1 would follow by rule (see ``HangingChain``):
///
/// - Ring 2 swings up about its wire through the eye, rolls a little and turns about the upright through its eye,
///   until it lies over the tip end, rising slightly toward the tip and turned to one side. Its eye never moves: rod 2
///   stays where it is, down through the slot and through ring 3.
/// - Ring 1 is carried with ring 2 as one piece while ring 2 starts to swing up, so that the two cannot cut into
///   each other, and then lifted clear above it, its rod upright and sliding up in its hole. It ends high above
///   ring 2, drooping toward the tip as it hangs at rest, with rod 1 down through ring 2. The bar is held high
///   enough for this (see ``Layout/barRaise``).
/// - Ring 3 is written as ring 2 is in ring 2's move, one hole further on: standing along the sword and then
///   tipped over toward the tip, tilted and swung.
/// - The sword slides toward the grip and back. While ring 3 drops, ring 1 moves across to the side ring 2 is turned
///   to, so that rod 1 leans aside and the sword can slide back toward the tip past it, giving ring 3 as much slot
///   in front of it as ring 2 had in its own move.
///
/// The key values were found by a search for the path with the most room (see `RingThreeTuneTests`), and are
/// written here as plain numbers.
struct RingThreeOff: Sendable {
    /// The stages, as spans of the path's own parameter.
    static let stagesAlongThePath = [
        Stage(name: "Ring 2 steps aside", start: 0, end: 0.22),
        Stage(name: "Ring 3 over the tip", start: 0.22, end: 0.40),
        Stage(name: "Down through the slot", start: 0.40, end: 0.75),
        Stage(name: "Ring 3 hangs", start: 0.75, end: 0.82),
        Stage(name: "Ring 2 back on", start: 0.82, end: 1),
    ]

    var ringOne: RingTurns
    /// How far ring 1 is carried with ring 2 as one piece rather than following its own path: 1 at the start and
    /// the end of the move, 0 while it is lifted clear.
    var ringOneCarry: Curve
    /// How far ring 1's eye moves across the sword, toward the side ring 2 is turned to, while ring 3 drops: its rod
    /// leans aside so that the sword can slide back toward the tip past it.
    var ringOneAside: Curve
    var ringTwo: RingTurns
    var ringThree: RingTurns
    var swordSlide: Curve

    static let leanOn = RingTurns.leanOnDegrees
    static let leanHanging = RingTurns.leanHangingDegrees
    /// Ring 3's tip when it rests on the rails or hangs: 180° less its lean.
    static let tipOn = 180 - RingTurns.leanOnDegrees
    static let tipHanging = 180 - RingTurns.leanHangingDegrees

    /// The keys as written, each curve's keys as (path parameter, value) pairs, angles in degrees and lengths in
    /// millimetres.
    static let keys: [String: [(Double, Double)]] = [
        "ring1.carry": [(0.04, 1), (0.085, 1.062), (0.12, 1), (0.2, 0), (0.8, 0), (0.88, 1), (0.915, 1.062), (0.96, 1)],
        "ring1.aside": [(0.32, 0), (0.3754, -13.225), (0.7898, -13.93), (0.85, 0)],
        "ring1.lid": [(0.1292, leanHanging), (0.8704, leanHanging)],
        "ring1.swing": [(0.1294, 0), (0.8694, 0)],
        "ring1.eye": [(0.03, Layout.eyeHeightHanging), (0.1, 0), (0.2004, 17.951), (0.39, 19.6), (0.61, 18.8), (0.7996, 17.951), (0.9, 0), (0.97, Layout.eyeHeightHanging)],
        "ring2.lid": [(0, leanOn), (0.0908, 58.041), (0.1071, 65.872), (0.1657, 84.519), (0.1999, 108.265), (0.3358, 113.738), (0.6203, 114.377), (0.8001, 108.265), (0.8343, 84.519), (0.8929, 65.872), (0.9092, 58.041), (1, leanOn)],
        "ring2.tilt": [(0.1189, 0), (0.2004, 10.127), (0.3457, -2.397), (0.5769, -2.297), (0.7996, 10.127), (0.8811, 0)],
        "ring2.swing": [(0.12, 0), (0.2004, -40.241), (0.4038, -45.357), (0.5978, -45.356), (0.7996, -40.241), (0.88, 0)],
        "ring3.tip": [(0.2, tipOn), (0.348, 100), (0.6525, 84.815), (0.7564, tipHanging)],
        "ring3.tilt": [(0.4362, 90), (0.5726, 62.496), (0.82, 90)],
        "ring3.swing": [(0.4397, 0), (0.5135, 25.076), (0.6338, 4.599), (0.694, -27.087), (0.7756, 0)],
        "ring3.eye": [(0.5019, Layout.eyeHeightOn), (0.6475, -4.462), (0.7429, -5.92), (0.7953, Layout.eyeHeightHanging)],
        "sword": [(0, Layout.swordHome), (0.1114, 36.496), (0.1568, 39.246), (0.3, 40.4), (0.4111, 42.357), (0.5699, 30.784), (0.7909, 30.92), (0.8432, 39.246), (0.8886, 36.496), (1, Layout.swordHome)],
    ]

    /// The path from a set of keys, named as in ``keys``.
    init(keys: [String: [(Double, Double)]]) {
        func curve(_ name: String, degrees: Bool) -> Curve {
            guard let keys = keys[name] else { preconditionFailure("no keys for \(name)") }
            return degrees ? RingTurns.degrees(keys) : RingTurns.millimetres(keys)
        }
        ringOne = RingTurns(
            lid: curve("ring1.lid", degrees: true),
            turn: Curve(constant: 0),
            tip: Curve(constant: 0),
            tilt: Curve(constant: 0),
            swing: curve("ring1.swing", degrees: true),
            eyeHeight: curve("ring1.eye", degrees: false)
        )
        ringOneCarry = curve("ring1.carry", degrees: false)
        ringOneAside = curve("ring1.aside", degrees: false)
        ringTwo = RingTurns(
            lid: curve("ring2.lid", degrees: true),
            turn: Curve(constant: 0),
            tip: Curve(constant: 0),
            tilt: curve("ring2.tilt", degrees: true),
            swing: curve("ring2.swing", degrees: true),
            eyeHeight: Curve(constant: Layout.eyeHeightOn)
        )
        ringThree = RingTurns(
            lid: Curve(constant: .pi),
            turn: Curve(constant: .pi / 2),
            tip: curve("ring3.tip", degrees: true),
            tilt: curve("ring3.tilt", degrees: true),
            swing: curve("ring3.swing", degrees: true),
            eyeHeight: curve("ring3.eye", degrees: false)
        )
        swordSlide = curve("sword", degrees: false)
    }

    /// The path as written.
    static let written = RingThreeOff(keys: keys)

    /// The toy at `progress` along the path's own parameter.
    func pose(at progress: Double) -> ToyPose {
        var rings = PuzzleState.rings.map(RestPoses.on)
        let ringTwo = ringTwo.held(2, at: progress)
        let carried = HangingChain.carried(RestPoses.hanging(1), restingOn: RestPoses.on(2), now: ringTwo)
        var own = ringOne.held(1, at: progress)
        own.eye.z += ringOneAside.value(at: progress)
        let ringOne = HangingChain.blend(own, carried, ringOneCarry.value(at: progress))
        // Rings hanging below ring 1, if there were any, rise and fall with it.
        for (offset, ring) in HangingChain.below(1, eyeHeight: ringOne.eye.y).enumerated() { rings[1 - 2 - offset] = ring }
        rings[0] = ringOne
        rings[1] = ringTwo
        rings[2] = ringThree.held(3, at: progress)
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
