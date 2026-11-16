import Foundation
import Puzzle
import Toy
import simd

/// An attempt at the path of ring 3 coming off while ring 1 is off and every other ring is on: ring 2 steps aside,
/// carrying ring 1 with it, ring 3 comes off over the tip and goes down through the slot round rod 2, and ring 2
/// goes back on with ring 1 hanging from it again.
///
/// It is not one of the written moves: under the present rules no path for it has been found that the checker
/// passes, and this is the nearest. What blocks it is how high rod 1 can reach. Its bead rests under the bar, so
/// its eye can rise no higher than the eye of a ring that is on. Ring 1 hangs on the side of ring 2's plane
/// toward the tip, and cannot get to the other side: the two rings are the same size, so ring 1 cannot pass
/// through ring 2's hole, and going round its rim would link them. So when ring 2 swings up out of ring 3's way,
/// ring 1 ends up lying on top of it, and its eye must be higher than ring 2. Rod 1 can follow ring 2 only to about
/// 80° from upright, still drooping toward the tip, and there ring 3 cannot lift far enough for the tip to pass
/// out of it without coming within 0.1 mm of ring 2 or of eye 2. `RingThreeAsideScanTests` and
/// `RingThreeReachTests` are the scans that show this.
///
/// Four things move, by curves of the path's own parameter (see ``RingTurns``), and one more by rule:
///
/// - Ring 2 swings up about its wire through the eye, rolls and turns about the upright through its eye. Its eye
///   never moves: rod 2 stays where it is, down through the slot and through ring 3.
/// - Ring 1 hangs from ring 2 and is carried by it as one piece (see ``HangingChain``), so rod 1 slides up in its
///   hole and leans to reach it.
/// - Ring 3 is written as ring 2 is in ring 2's move, one hole further on: standing along the sword and then
///   tipped over toward the tip, tilted and swung.
/// - The sword slides toward the grip and back.
struct RingThreeOff: Sendable {
    /// The stages, as spans of the path's own parameter.
    static let stagesAlongThePath = [
        Stage(name: "Ring 2 steps aside", start: 0, end: 0.22),
        Stage(name: "Ring 3 over the tip", start: 0.22, end: 0.40),
        Stage(name: "Down through the slot", start: 0.40, end: 0.75),
        Stage(name: "Ring 3 hangs", start: 0.75, end: 0.82),
        Stage(name: "Ring 2 back on", start: 0.82, end: 1),
    ]

    var ringTwo: RingTurns
    var ringThree: RingTurns
    var swordSlide: Curve

    static let leanOn = RingTurns.leanOnDegrees
    /// Ring 3's tip when it rests on the rails or hangs: 180° less its lean.
    static let tipOn = 180 - RingTurns.leanOnDegrees
    static let tipHanging = 180 - RingTurns.leanHangingDegrees

    /// The state the move starts from: ring 1 off, every other ring on.
    static let from = PuzzleState.allOn.moving(1)

    /// Ring 1 hanging from ring 2, as it rests before the move.
    static let ringOneHanging = HangingChain(carrierAtRest: RestPoses.on(2), chainAtRest: [RestPoses.hanging(1)])

    /// The keys as written, each curve's keys as (path parameter, value) pairs, angles in degrees and lengths in
    /// millimetres.
    static let keys: [String: [(Double, Double)]] = [
        "ring2.lid": [(0, leanOn), (0.12, 62), (0.20, 80), (0.80, 80), (0.88, 62), (1, leanOn)],
        "ring2.tilt": [(0.10, 0), (0.20, 0), (0.80, 0), (0.90, 0)],
        "ring2.swing": [(0.10, 0), (0.20, 0), (0.80, 0), (0.90, 0)],
        "ring3.tip": [(0.20, tipOn), (0.368, 100), (0.642, 84.795), (0.776, tipHanging)],
        "ring3.tilt": [(0.4763, 90), (0.5629, 62.031), (0.82, 90)],
        "ring3.swing": [(0.4289, 0), (0.5428, 24.742), (0.6231, 4.12), (0.6951, -27.2), (0.7857, 0)],
        "ring3.eye": [(0.5022, Layout.eyeHeightOn), (0.6480, -4.475), (0.7419, -5.977), (0.796, Layout.eyeHeightHanging)],
        "sword": [(0, Layout.swordHome), (0.12, 40), (0.28, 40.4), (0.39, 42.4), (0.4911, 30.841), (0.78, 30.841), (0.88, 40), (1, Layout.swordHome)],
    ]


    /// The path from a set of keys, named as in ``keys``.
    init(keys: [String: [(Double, Double)]]) {
        func curve(_ name: String, degrees: Bool) -> Curve {
            guard let keys = keys[name] else { preconditionFailure("no keys for \(name)") }
            return degrees ? RingTurns.degrees(keys) : RingTurns.millimetres(keys)
        }
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
        rings[0] = Self.ringOneHanging.chain(carriedBy: ringTwo)[0]
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
