import Foundation
import Puzzle
import Toy
import simd

/// The second ring on the sword coming off: one path, written once, for ring k from 2 to 9.
///
/// The rule lets ring k move only when ring k−1 is on and every ring before it is off. With the sword drawn back
/// past the rings that are off, ring k−1 and ring k are the first two rings on the sword, as rings 1 and 2 are when
/// every ring is on. So the move is the same for every k, one hole further along for each ring after ring 2, and it
/// asks nothing of the rings in front or behind:
///
/// - Every ring in front of ring k, ring k−1 included, keeps still where it rests, with its rod. The rings that are
///   off hang below the rails, their eyes just under them, so the sword can slide over them as it does at home.
/// - The sword slides back toward the grip until its tip is past the eyes of the rings that are off, then dips and
///   goes down, taking with it ring k and every ring behind it, as one stiff piece with their rods, which slide down
///   through the bar. Going down, its tip leaves ring k−1, which is now off the rails without having moved, while
///   rod k−1 still stands in the slot in front of the tip.
/// - Ring k comes off below ring k−1, relative to the sword, as ring 2 does in ``RingTwoOff``: it swings up over the
///   tip until it lies nearly flat, then goes down through the slot round rod k−1 and comes to hang.
/// - For the drop the sword slides forward under ring k−1, but only as far as the rod of the ring in front of ring
///   k−1 allows: that rod hangs down through the bar 30 mm in front of ring k's eye. Ring k's eye moves back toward
///   the grip by a few millimetres, its rod leaning in its hole, so that the slot in front of the eye is as long as
///   ring 2's drop needs. The eye comes back above its hole as the ring hangs.
/// - The sword slides back, comes up, its tip entering ring k−1 again, and slides home.
///
/// Every key is written for ring 2, in millimetres along the sword and degrees; for ring k the sword's slide and
/// every ring's place move along by k−2 holes. The rule this needs beyond the other moves is the one the sword-away
/// trial brought: the sword may move down and up as well as slide, and the rings that ride on it move with it.
struct PairMoveOff: Sendable {
    /// The ring that comes off.
    let ring: Int
    /// The state before the move: ring k and ring k−1 on, the rings in front of ring k−1 off.
    let from: PuzzleState

    var turns: RingTurns
    /// How far ring k's eye is moved toward the grip from above its hole.
    var back: Curve
    var swordSlide: Curve
    var swordHeight: Curve

    static let tipOn = 180 - RingTurns.leanOnDegrees
    static let tipHanging = 180 - RingTurns.leanHangingDegrees

    /// The keys as written, for ring 2, each curve's keys as (path parameter, value) pairs, angles in degrees and
    /// lengths in millimetres. The ring's swing up over the tip and its eye's height are ``RingTwoOff``'s, mapped onto
    /// this path; the drop's keys and the eye's move back were found by a search for the path with the most room (see
    /// `PairMoveTuneTests`), and the sword's were written by hand.
    static let keys: [String: [(Double, Double)]] = [
        "ring.tip": [(0.28, tipOn), (0.4263, 93.718), (0.6407, 81.455), (0.7991, tipHanging)],
        "ring.tilt": [(0.5221, 90), (0.6071, 64.182), (0.82, 90)],
        "ring.swing": [(0.4893, 0), (0.5835, 29.202), (0.6467, 9.059), (0.7023, -28.121), (0.7982, 0)],
        "ring.eye": [(0.5432, Layout.eyeHeightOn), (0.6702, -4.475), (0.752, -5.977), (0.7991, Layout.eyeHeightHanging)],
        "ring.back": [(0.45, 0), (0.5403, 2.811), (0.6616, 3.272), (0.7067, 0)],
        // Out: back toward the grip at the height it rests at, dipping 3 mm so that the tip, which rises toward its
        // end, passes under ring k−1; then down 20 mm, once the tip is behind the eye of the ring in front of ring
        // k−1, which hangs in the middle under the slot. Forward under ring k−1 for the drop, as far as rod k−2
        // allows; back, up and home the same way.
        "sword.slide": [
            (0, Layout.swordHome), (0.16, 21.5), (0.20, 23.4), (0.24, 23.9), (0.3497, 25.4), (0.4455, 27.8),
            (0.57, dropSlide), (0.80, dropSlide), (0.86, 23.9), (0.90, 23.4), (0.93, 21.5), (1, Layout.swordHome),
        ],
        "sword.height": [(0, 0), (0.16, -3), (0.20, -6), (0.26, -drop), (0.85, -drop), (0.90, -6), (0.93, -3), (1, 0)],
    ]

    /// How far down the sword goes. Ring k must pass under ring k−1 to come off, which needs about 17 mm; with a ring
    /// hanging behind, the sword and what rides on it can go down about 27 mm before coming within 0.3 mm of the bar.
    static let drop = 20.0

    /// Where the sword's tip is for the drop, for ring 2: 2.4 mm behind where rod k−2 hangs, 15 mm in front of ring
    /// k−1's eye, so that the tip's wire keeps 0.45 mm from that rod.
    static let dropSlide = 19.4

    /// The stages, as spans of the path's own parameter.
    static func stagesAlongThePath(ring: Int) -> [Stage] {
        [
            Stage(name: "Sword moves away", start: 0, end: 0.28),
            Stage(name: "Ring \(ring) over the tip", start: 0.28, end: 0.4542),
            Stage(name: "Down through the slot", start: 0.4542, end: 0.759),
            Stage(name: "Ring \(ring) hangs", start: 0.759, end: 0.82),
            Stage(name: "Sword comes back", start: 0.82, end: 1),
        ]
    }

    init(ring: Int, from: PuzzleState, keys: [String: [(Double, Double)]] = Self.keys) {
        precondition(ring >= 2 && from.canMove(ring) && from.isOn(ring), "ring \(ring) comes off from \(from)")
        self.ring = ring
        self.from = from
        func curve(_ name: String, degrees: Bool) -> Curve {
            guard let keys = keys[name] else { preconditionFailure("no keys for \(name)") }
            return degrees ? RingTurns.degrees(keys) : RingTurns.millimetres(keys)
        }
        turns = RingTurns(
            lid: Curve(constant: .pi),
            turn: Curve(constant: .pi / 2),
            tip: curve("ring.tip", degrees: true),
            tilt: curve("ring.tilt", degrees: true),
            swing: curve("ring.swing", degrees: true),
            eyeHeight: curve("ring.eye", degrees: false)
        )
        back = curve("ring.back", degrees: false)
        // Every key of the slide but home, at the two ends, moves along with the ring.
        let shift = Dimensions.Bar.holePitch * Double(ring - 2)
        let slide = curve("sword.slide", degrees: false).keys
        swordSlide = Curve(slide.indices.map { index in
            let key = slide[index]
            let isHome = index == 0 || index == slide.count - 1
            return Curve.Key(key.progress, isHome ? key.value : key.value + shift)
        })
        swordHeight = curve("sword.height", degrees: false)
    }

    /// The toy at `progress` along the path's own parameter.
    func pose(at progress: Double) -> ToyPose {
        let height = swordHeight.value(at: progress)
        let rings = PuzzleState.rings.map { number -> HeldRing in
            var held: HeldRing
            if number == ring {
                held = turns.held(number, at: progress)
                held.eye.x += back.value(at: progress)
            } else {
                held = RestPoses.resting(number, in: from)
            }
            if number >= ring { held.eye.y += height }
            return held
        }
        return RestPoses.pose(holding: rings, swordSlide: swordSlide.value(at: progress), swordHeight: height)
    }
}

extension PairMoveOff {
    /// The path with its pacing (see ``Pacing``): the toy a fraction of the way through the move, coming off.
    struct Paced: Sendable {
        let path: PairMoveOff
        let pacing: Pacing

        init(_ path: PairMoveOff) {
            self.path = path
            pacing = Pacing(path.pose(at:))
        }

        func pose(atProgress progress: Double) -> ToyPose {
            path.pose(at: pacing.pathParameter(atProgress: min(max(progress, 0), 1)))
        }

        var stages: [Stage] { pacing.stages(PairMoveOff.stagesAlongThePath(ring: path.ring)) }
    }
}
