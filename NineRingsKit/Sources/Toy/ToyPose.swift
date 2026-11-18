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
    public var swordSlide: Double
    /// How far the sword is raised from home, in millimetres; negative when it is lowered. The sword stays level,
    /// so its slide and its height are all there is to its pose.
    public var swordHeight: Double

    public init(rings: [PartPose], rods: [PartPose], bar: PartPose, swordSlide: Double, swordHeight: Double = 0) {
        precondition(rings.count == 9 && rods.count == 9, "the toy has nine rings and nine rods")
        self.rings = rings
        self.rods = rods
        self.bar = bar
        self.swordSlide = swordSlide
        self.swordHeight = swordHeight
    }

    /// Where the sword's origin is: home moved by its slide and its height.
    public var swordOffset: SIMD3<Double> { SIMD3(swordSlide, swordHeight, 0) }

    /// The sword's frame in the toy's frame.
    public var sword: PartPose {
        PartPose(position: swordOffset, orientation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1))
    }

    public func ring(_ number: Int) -> PartPose { rings[number - 1] }
    public func rod(_ number: Int) -> PartPose { rods[number - 1] }
}

/// Some of the toy's parts, by name: which rings and which rods, by ring number, and whether the bar and the sword.
public struct ToyParts: Sendable, Equatable {
    public var rings: Set<Int> = []
    public var rods: Set<Int> = []
    public var bar = false
    public var sword = false

    public init(rings: Set<Int> = [], rods: Set<Int> = [], bar: Bool = false, sword: Bool = false) {
        self.rings = rings
        self.rods = rods
        self.bar = bar
        self.sword = sword
    }

    public var isEmpty: Bool { rings.isEmpty && rods.isEmpty && !bar && !sword }
}

extension ToyPose {
    /// The parts that are somewhere else in `other`: moved by more than a hundredth of a millimetre or turned by more
    /// than about a hundredth of a degree, a difference no one can see.
    public func parts(movedFrom other: ToyPose) -> ToyParts {
        func moved(_ a: PartPose, _ b: PartPose) -> Bool {
            simd_distance(a.position, b.position) >= 0.01 || abs(simd_dot(a.orientation.vector, b.orientation.vector)) <= 1 - 1e-8
        }
        var parts = ToyParts()
        for number in 1...9 {
            if moved(ring(number), other.ring(number)) { parts.rings.insert(number) }
            if moved(rod(number), other.rod(number)) { parts.rods.insert(number) }
        }
        parts.bar = moved(bar, other.bar)
        parts.sword = abs(swordSlide - other.swordSlide) >= 0.01 || abs(swordHeight - other.swordHeight) >= 0.01
        return parts
    }

    /// Whether every part is where it is in `other`, to within a difference no one can see.
    public func isClose(to other: ToyPose) -> Bool {
        parts(movedFrom: other).isEmpty
    }
}
