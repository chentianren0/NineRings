import Foundation
import Toy
import simd

/// Where the parts that never move are, and the few numbers the written motion is built on.
///
/// Everything is in millimetres in the toy's frame (see ``ToyPose``): fixed to the bar, x along the sword toward
/// the grip, y up, z across, the origin where the tip's outermost point is with the sword at home.
public enum Layout {
    /// The gap left between two parts that rest against each other, so that they are drawn a hair apart
    /// rather than touching.
    public static let restingGap = 0.25

    /// Where the eye of ring 1's rod is when ring 1 is on: this far from the tip's outermost point, with the
    /// sword at home. Ring 1 then sits on the straight part of the rails, rod 9 is still clear of the rails
    /// where they begin to close, and there is as much slot as there can be in front of ring 1 for its drop.
    public static let firstEyeX = 32.0

    // MARK: A ring that is on

    /// How far a ring that is on leans from upright, its lower arc toward the tip. It is as small as it can
    /// be while rod k−1 still passes inside ring k's lower arc: the lower that rod crosses ring k, the further
    /// down ring k−1's eye can go when that ring is off.
    public static let leanOn = 43.0 * Double.pi / 180

    /// Height of the eye's centre of a ring that is on. The rails then cross the ring a little above its
    /// middle, with the same room above and below them, and the eye is just above the rails.
    public static let eyeHeightOn = 3.5

    // MARK: A ring that is off, hanging on the next ring

    /// Height of the eye's centre of a ring that is off and hangs from the next ring: just below the rails, so
    /// that its rod is out of the slot, and just above the next ring's lower arc, which holds it up.
    public static let eyeHeightHanging = -9.55

    /// How far a hanging ring leans from upright, its lower arc toward the tip, clear of the next ring's lower
    /// arc and of its own rod.
    public static let leanHanging = 60.0 * Double.pi / 180

    // MARK: The bar and the holes

    /// How far the bar is held above the height at which every bead of a ring that is on would rest against
    /// its underside. Held higher, the beads hang free below it, and every rod has that much room to rise: the
    /// ring that hangs from a ring stepping aside is lifted clear above that ring. Measured for rings 3 to 9 (see
    /// `PlateChainScanTests`): stepping aside needs at least about 9 mm and has the most room from about 15 mm; the
    /// rings hanging at rest stay clear of the bar up to about 27 mm.
    public static let barRaise = 18.0

    /// The bar, level and still, held `raise` above the height at which every bead of a ring that is on would
    /// rest a hair under it.
    public static func bar(raisedBy raise: Double) -> PartPose {
        // A rod of a ring that is on stands straight down from its eye to its hole.
        let beadTop = eyeHeightOn + Dimensions.Rod.beadCenterY + Dimensions.Rod.beadRadius
        let center = SIMD3(firstEyeX - Dimensions.Bar.holeX(1), beadTop + restingGap + raise + Dimensions.Bar.thickness / 2, 0)
        return PartPose(position: center, orientation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1))
    }

    /// The bar as the toy holds it.
    public static let bar = bar(raisedBy: barRaise)

    /// The middle of the hole that the rod of `ring` runs through, at mid-thickness of the bar.
    public static func hole(_ ring: Int, raisedBy raise: Double = barRaise) -> SIMD3<Double> {
        bar(raisedBy: raise).worldPoint(SIMD3(Dimensions.Bar.holeX(ring), 0, 0))
    }

    /// The sword's slide when nothing is being moved.
    public static let swordHome = 0.0
}
