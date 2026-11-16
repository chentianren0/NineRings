import Foundation
import Puzzle
import Toy
import simd

/// The toy at rest, placed by rule rather than solved.
///
/// Each ring rests in one of a few ways, each written once relative to its own hole, and its rod follows by the
/// rod rule. The sword is at home and the bar never moves.
public enum RestPoses {
    /// How a ring that is on rests: round both rails, its eye on top, just above the rails, its rod straight down
    /// through the slot to its hole, and its lower arc leaning toward the tip.
    public static func on(_ ring: Int) -> HeldRing {
        HeldRing(
            eye: SIMD3(Layout.hole(ring).x, Layout.eyeHeightOn, 0),
            towardCenter: SIMD3(-sin(Layout.leanOn), -cos(Layout.leanOn), 0),
            alongWire: SIMD3(0, 0, 1)
        )
    }

    /// How a ring that is off rests while the next ring is on: below the sword, hanging from its eye, which is
    /// held up just above the next ring's lower arc; its rod has slid down and is out of the slot.
    public static func hanging(_ ring: Int) -> HeldRing {
        precondition(ring < PuzzleState.ringCount, "ring 9 has no next ring to hang from")
        return HeldRing(
            eye: SIMD3(Layout.hole(ring).x, Layout.eyeHeightHanging, 0),
            towardCenter: SIMD3(-sin(Layout.leanHanging), -cos(Layout.leanHanging), 0),
            alongWire: SIMD3(0, 0, 1)
        )
    }

    /// The states whose rest has been written and checked so far: every ring on, ring 1 alone off, and ring 2
    /// alone off. A ring that is off hangs from the next ring the same way wherever it is, so ring 2 off rests as
    /// ring 1 off does, one hole further on, with ring 1 on in front of it and rod 1 down through it.
    ///
    /// Other arrangements, such as a chain of off rings hanging from one another or ring 9 off on the bar, come
    /// with the moves that reach them.
    public static func isWritten(_ state: PuzzleState) -> Bool {
        state == .allOn || state == PuzzleState.allOn.moving(1) || state == PuzzleState.allOn.moving(2)
    }

    /// The toy at rest in `state`, or nil when that rest has not been written yet.
    public static func pose(for state: PuzzleState) -> ToyPose? {
        guard isWritten(state) else { return nil }
        let held = PuzzleState.rings.map { ring in
            state.isOn(ring) ? on(ring) : hanging(ring)
        }
        return pose(holding: held, swordSlide: Layout.swordHome)
    }

    /// The toy with every ring held as given, each rod placed by the rod rule.
    static func pose(holding rings: [HeldRing], swordSlide: Double, barRaise: Double = Layout.barRaise) -> ToyPose {
        precondition(rings.count == PuzzleState.ringCount, "the toy has nine rings")
        return ToyPose(
            rings: rings.map(\.ringPose),
            rods: zip(PuzzleState.rings, rings).map { ring, held in held.rodPose(hole: Layout.hole(ring, raisedBy: barRaise)) },
            bar: Layout.bar(raisedBy: barRaise),
            swordSlide: swordSlide
        )
    }
}
