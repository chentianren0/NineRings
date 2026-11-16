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

    /// How a ring that is off rests, whatever the rings next to it are: below the sword, its eye just under the
    /// rails, so that its rod is out of the slot, and leaning toward the tip more than a ring that is on. Its rod
    /// runs through the next ring whether that ring is on or off: off rings next to one another lie like parallel
    /// plates, one hole apart. Ring 9 has no next ring and rests the same way.
    public static func hanging(_ ring: Int) -> HeldRing {
        HeldRing(
            eye: SIMD3(Layout.hole(ring).x, Layout.eyeHeightHanging, 0),
            towardCenter: SIMD3(-sin(Layout.leanHanging), -cos(Layout.leanHanging), 0),
            alongWire: SIMD3(0, 0, 1)
        )
    }

    /// How ring `ring` rests in `state`: on or off, decided by that ring alone.
    public static func resting(_ ring: Int, in state: PuzzleState) -> HeldRing {
        state.isOn(ring) ? on(ring) : hanging(ring)
    }

    /// The toy at rest in `state`.
    public static func pose(for state: PuzzleState) -> ToyPose {
        let held = PuzzleState.rings.map { resting($0, in: state) }
        return pose(holding: held, swordSlide: Layout.swordHome)
    }

    /// The toy with every ring held as given, each rod placed by the rod rule.
    static func pose(holding rings: [HeldRing], swordSlide: Double, swordHeight: Double = 0) -> ToyPose {
        precondition(rings.count == PuzzleState.ringCount, "the toy has nine rings")
        return ToyPose(
            rings: rings.map(\.ringPose),
            rods: zip(PuzzleState.rings, rings).map { ring, held in held.rodPose(hole: Layout.hole(ring)) },
            bar: Layout.bar,
            swordSlide: swordSlide,
            swordHeight: swordHeight
        )
    }
}
