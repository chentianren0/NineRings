import Foundation

/// The nominal sizes of the toy, in millimetres. Every shape, drawn or simulated, is built from these.
///
/// Each part has its own local frame, described with its sizes; ``ToyPose`` places those frames in the toy's frame.
public enum Dimensions {
    /// A ring is a circle of wire in its local x–y plane, centred on its origin, with its normal along local z.
    public enum Ring {
        /// Radius of the wire's centreline; the ring is 28 mm across outside.
        public static let radius = 12.85
        public static let wireRadius = 1.15
    }

    /// A rod is one piece with the eye at its top and the bead at its bottom.
    ///
    /// The origin is the centre of the eye, a small circle of wire in the local x–y plane.
    /// The straight shaft runs down the local −y axis from the bottom of the eye into the bead.
    public enum Rod {
        /// Radius of the eye's centreline.
        public static let eyeRadius = 3.75
        public static let wireRadius = 0.85
        /// Where the shaft leaves the eye.
        public static let shaftTopY = -eyeRadius
        public static let beadCenterY = -60.5
        public static let beadRadius = 5.0
    }

    /// The bar is a flat strip with rounded ends and a hole for each rod.
    ///
    /// The origin is the centre of the sheet. Local x runs along its length, toward the grip when the toy is at rest,
    /// and local y is the sheet's normal, pointing up.
    public enum Bar {
        public static let length = 150.0
        public static let width = 12.5
        public static let thickness = 1.0
        public static let holeRadius = 1.45
        public static let holePitch = 15.0

        /// Local x of the hole that the rod of `ring` runs through.
        public static func holeX(_ ring: Int) -> Double {
            holePitch * Double(ring) - 68
        }
    }

    /// The sword's own frame: x runs along it from the tip toward the grip, y is up and z is across it. The origin
    /// is the outermost point of the tip's centreline. The sword stays level; it slides along its length and may be
    /// lowered and raised, so its frame is the toy's frame moved by ``ToyPose/swordOffset``.
    ///
    /// Two rails run side by side and join at the tip in a half circle. The tip end rises out of the plane of the
    /// rails. Toward the grip the rails converge at the shoulder until their wires touch, then run on as the neck,
    /// which ends in a grip loop each side. ``SwordShape`` is the centreline these sizes describe.
    public enum Sword {
        public static let wireRadius = 1.1
        /// Distance of each rail's centreline from the middle of the slot; also the radius of the tip's half circle.
        public static let railOffset = 9.4
        /// The tip end rises at this angle over `tipRiseLength`, measured along x from the origin.
        public static let tipRiseAngle = 10.0 * Double.pi / 180
        public static let tipRiseLength = 20.0
        /// Where the straight rails end and start to converge.
        public static let railEndX = 150.0
        /// The corner where the rails, turning in, come to the line on which the two wires touch, which closes the
        /// slot. With the bend round the corner, they touch from about 2 mm further on.
        public static let shoulderX = 154.0
        /// Where the neck ends: its wire runs on straight from here into the grip loop.
        public static let neckEndX = 226.0

        /// Height of the rails' centreline at `x`. It is zero at the tip's end and level beyond the rise.
        public static func height(atX x: Double) -> Double {
            -min(max(x, 0), tipRiseLength) * tan(tipRiseAngle)
        }

        /// Height of the straight part of the rails.
        public static let railHeight = height(atX: tipRiseLength)

        /// Where the wire bends, at the end of the tip's rise, where the rails turn in to the shoulder and where
        /// they turn back along the neck, its centreline bends round this radius, as a bent wire does.
        public static let bendRadius = 3.0

        /// The two grip loops at the end of the neck, one each side, are this long and, together, this far across,
        /// outside the wire.
        public static let gripLoopLength = 27.0
        public static let gripLoopSpan = 31.0
    }
}
