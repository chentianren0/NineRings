import simd

/// Where one rigid part is: its local origin in world coordinates, in millimetres, and the rotation that takes
/// its local axes to the world's.
///
/// Positions are in the toy's frame (see ``ToyPose``), and each part's local frame is described in ``Dimensions``.
public struct PartPose: Sendable, Equatable {
    public var position: SIMD3<Double>
    public var orientation: simd_quatd

    public init(position: SIMD3<Double>, orientation: simd_quatd) {
        self.position = position
        self.orientation = orientation
    }

    /// A point given in the part's local frame, in world coordinates.
    public func worldPoint(_ local: SIMD3<Double>) -> SIMD3<Double> {
        position + orientation.act(local)
    }

    /// A direction given in the part's local frame, in world coordinates.
    public func worldDirection(_ local: SIMD3<Double>) -> SIMD3<Double> {
        orientation.act(local)
    }
}

/// Where every part of the toy is. This is all a drawing needs.
///
/// The toy's frame is fixed to the bar, which stays still and level. Its axes are the sword's: x runs along the
/// sword from the tip toward the grip, y is up and z is across. Its origin is where the outermost point of the
/// tip's centreline is when the sword is at home, slid neither way.
public struct ToyPose: Sendable, Equatable {
    /// Nine poses, ring 1 first.
    public var rings: [PartPose]
    /// Nine poses, the rod of ring 1 first.
    public var rods: [PartPose]
    public var bar: PartPose
    /// How far the sword is slid along its own length from home, in millimetres; positive toward the grip.
    /// The sword stays level, so this is all there is to its pose.
    public var swordSlide: Double

    public init(rings: [PartPose], rods: [PartPose], bar: PartPose, swordSlide: Double) {
        precondition(rings.count == 9 && rods.count == 9, "the toy has nine rings and nine rods")
        self.rings = rings
        self.rods = rods
        self.bar = bar
        self.swordSlide = swordSlide
    }

    /// The sword's frame in the toy's frame.
    public var sword: PartPose {
        PartPose(position: SIMD3(swordSlide, 0, 0), orientation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1))
    }

    public func ring(_ number: Int) -> PartPose { rings[number - 1] }
    public func rod(_ number: Int) -> PartPose { rods[number - 1] }
}
