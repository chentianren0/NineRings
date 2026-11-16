import Foundation
import Puzzle
import Toy
import simd

/// A trial of a second way for ring k (k ≥ 2) to come off, beside the written ones: the sword moves away and the
/// rings in front keep still.
///
/// - The sword slides back toward the grip until its tip is out of ring k−1, dipping as it goes so that the tip,
///   which rises toward its end, passes under ring k−1's wire and eye. The tip's end stays in front of rod k−1,
///   which stays in the slot. Ring k−1 does not move.
/// - The sword goes down, taking with it every ring that rides on it: ring k and the rings behind it, with their
///   rods, which slide down through the bar. Ring k−1, and anything hanging from it in front, stay where they rest.
/// - Ring k comes off as ring 2 does in ``RingTwoOff``, relative to the sword: the very keys of that path, one hole
///   further along for each ring after ring 2, and the sword's slide moved along with it.
/// - The sword slides back from under ring k−1, comes up again and slides home, its tip entering ring k−1.
///
/// The rule this needs, and the only one that differs from the other moves: the sword may move down and up as well
/// as slide, and the rings that ride on it move down and up with it. The bar never moves.
struct SwordAwayOff: Sendable {
    /// The ring that comes off.
    let ring: Int
    /// The state before the move: ring k and ring k−1 on, the rings in front of ring k−1 off.
    let from: PuzzleState

    var ringTurns: RingTurns
    var swordSlide: Curve
    var swordHeight: Curve

    /// How far the sword goes down, and how far it has dipped by the time it is drawn back to where its tip
    /// leaves ring k−1. Below about 17.4 mm the tip, slid forward under ring 1 for ring 2's drop, meets ring 1's
    /// lowest point; above about 26.9 mm ring 2, hanging, comes within 0.3 mm of the bar.
    static let drop = 20.0
    static let dip = 5.0

    /// The stages, as spans of the path's own parameter.
    static func stagesAlongThePath(ring: Int) -> [Stage] {
        [
            Stage(name: "Sword moves away", start: 0, end: 0.28),
            Stage(name: "Ring \(ring) over the tip", start: 0.28, end: ringTwoStretch(onto: 0.40)),
            Stage(name: "Down through the slot", start: ringTwoStretch(onto: 0.40), end: ringTwoStretch(onto: 0.75)),
            Stage(name: "Ring \(ring) hangs", start: ringTwoStretch(onto: 0.75), end: 0.82),
            Stage(name: "Sword comes back", start: 0.82, end: 1),
        ]
    }

    /// The keys of the path for ring 2, each curve's keys as (path parameter, value) pairs, angles in degrees and
    /// lengths in millimetres. Ring 2's own keys are ``RingTwoOff``'s, from where ring 2 starts to move to where it
    /// hangs, mapped onto this path's stretch for them; the sword's are this path's own.
    ///
    /// The sword's slide is given for ring 2: `asideSlide` where it has gone down, `dropSlide` where it holds for the
    /// drop through the slot.
    static func keys(drop: Double, dip: Double, asideSlide: Double = 22.6, dropSlide: Double = 15.841) -> [String: [(Double, Double)]] {
        var keys: [String: [(Double, Double)]] = [:]
        for name in ["ring2.tip", "ring2.tilt", "ring2.swing", "ring2.eye"] {
            keys[name] = RingTwoOff.keys[name]!.map { (ringTwoStretch(onto: $0.0), $0.1) }
        }
        keys["sword.slide"] = [
            (0, Layout.swordHome), (0.18, 21.5), (0.28, asideSlide),
            (ringTwoStretch(onto: 0.28), 25.4), (ringTwoStretch(onto: 0.39), 27.8), (0.57, dropSlide),
            (0.80, dropSlide), (0.88, 21.5), (1, Layout.swordHome),
        ]
        keys["sword.height"] = [
            (0, 0), (0.18, -dip), (0.28, -drop), (0.84, -drop), (0.92, -dip), (1, 0),
        ]
        return keys
    }

    /// Where a parameter of ``RingTwoOff``'s path, in its stretch from ring 2's first key to its last, falls on this
    /// path.
    static func ringTwoStretch(onto parameter: Double) -> Double {
        let (start, end) = (0.20, 0.82)
        let (newStart, newEnd) = (0.28, 0.82)
        return newStart + (parameter - start) * (newEnd - newStart) / (end - start)
    }

    init(ring: Int, from: PuzzleState, keys: [String: [(Double, Double)]]) {
        precondition(ring >= 2 && from.canMove(ring) && from.isOn(ring), "ring \(ring) comes off from \(from)")
        self.ring = ring
        self.from = from
        func curve(_ name: String, degrees: Bool) -> Curve {
            guard let keys = keys[name] else { preconditionFailure("no keys for \(name)") }
            return degrees ? RingTurns.degrees(keys) : RingTurns.millimetres(keys)
        }
        ringTurns = RingTurns(
            lid: Curve(constant: .pi),
            turn: Curve(constant: .pi / 2),
            tip: curve("ring2.tip", degrees: true),
            tilt: curve("ring2.tilt", degrees: true),
            swing: curve("ring2.swing", degrees: true),
            eyeHeight: curve("ring2.eye", degrees: false)
        )
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

    /// Ring `number` as it rests in `state`, moved up by `height`.
    private static func resting(_ number: Int, in state: PuzzleState, raisedBy height: Double) -> HeldRing {
        var held = state.isOn(number) ? RestPoses.on(number) : RestPoses.hanging(number)
        held.eye.y += height
        return held
    }

    /// The toy at `progress` along the path's own parameter.
    func pose(at progress: Double) -> ToyPose {
        let height = swordHeight.value(at: progress)
        let rings = PuzzleState.rings.map { number -> HeldRing in
            if number < ring { return Self.resting(number, in: from, raisedBy: 0) }
            if number > ring { return Self.resting(number, in: from, raisedBy: height) }
            var held = ringTurns.held(number, at: progress)
            held.eye.y += height
            return held
        }
        return RestPoses.pose(holding: rings, swordSlide: swordSlide.value(at: progress), swordHeight: height)
    }
}

extension SwordAwayOff {
    /// The path with its pacing (see ``Pacing``): the toy a fraction of the way through the move.
    struct Paced: Sendable {
        let path: SwordAwayOff
        let pacing: Pacing

        init(_ path: SwordAwayOff) {
            self.path = path
            pacing = Pacing(path.pose(at:))
        }

        func pose(atProgress progress: Double) -> ToyPose {
            path.pose(at: pacing.pathParameter(atProgress: min(max(progress, 0), 1)))
        }
    }
}

/// Ring 2 coming off the second way, the sword moving away while ring 1 keeps still: a trial beside the written
/// move (``RingTwoOff``), which the app does not play. Only the capture mode of a debug build draws it.
public enum SwordAwayTrial {
    /// The move it is a way of making: ring 2 coming off with every other ring on.
    public static let move = Move(ring: 2, from: .allOn)!

    static let path = SwordAwayOff.Paced(
        SwordAwayOff(ring: 2, from: .allOn, keys: SwordAwayOff.keys(drop: SwordAwayOff.drop, dip: SwordAwayOff.dip))
    )

    /// The toy a fraction `progress` of the way through ring 2 coming off. Progress outside 0...1 is held at the
    /// ends.
    public static func pose(at progress: Double) -> ToyPose {
        path.pose(atProgress: progress)
    }

    /// The stages, as spans of the move's progress.
    public static let stages: [Stage] = path.pacing.stages(SwordAwayOff.stagesAlongThePath(ring: 2))

    /// The stage at `progress`; at a boundary, the one that begins there.
    public static func stage(at progress: Double) -> Stage {
        stages.last { $0.start <= progress } ?? stages[0]
    }
}
