import Toy
import simd

/// A box, in millimetres in the toy's frame, around the toy.
///
/// The box is measured for a given pose: the sword's box, where the sword has slid to, joined with every other
/// part.
struct ToyBounds {
    var lower: SIMD3<Float>
    var upper: SIMD3<Float>

    var center: SIMD3<Float> { (lower + upper) / 2 }
    var size: SIMD3<Float> { upper - lower }

    /// The sword alone, with the grip loops, at home.
    static let sword: ToyBounds = {
        let points = SwordPath.points()
        let radius = Float(Dimensions.Sword.wireRadius)
        return ToyBounds(
            lower: points.reduce(SIMD3(repeating: .infinity)) { simd_min($0, $1) } - radius,
            upper: points.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) } + radius
        )
    }()

    /// The whole toy in `pose`.
    init(_ pose: ToyPose) {
        let offset = SIMD3<Float>(pose.swordOffset)
        self.init(lower: Self.sword.lower + offset, upper: Self.sword.upper + offset)
        includeParts(of: pose)
    }

    /// Takes in every part of `pose` but the sword.
    private mutating func includeParts(of pose: ToyPose) {
        let ringReach = Float(Dimensions.Ring.radius + Dimensions.Ring.wireRadius)
        let eyeReach = Float(Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius)
        let bead = SIMD3(0, Dimensions.Rod.beadCenterY, 0)
        for ring in pose.rings {
            include(SIMD3<Float>(ring.position), radius: ringReach)
        }
        for rod in pose.rods {
            include(SIMD3<Float>(rod.position), radius: eyeReach)
            include(SIMD3<Float>(rod.worldPoint(bead)), radius: Float(Dimensions.Rod.beadRadius))
        }
        for end in [-1.0, 1.0] {
            include(SIMD3<Float>(pose.bar.worldPoint(SIMD3(end * Dimensions.Bar.length / 2, 0, 0))), radius: Float(Dimensions.Bar.width / 2))
        }
    }

    /// The box around every pose of `poses`.
    init(_ poses: some Sequence<ToyPose>) {
        var box: ToyBounds?
        for pose in poses {
            let next = ToyBounds(pose)
            box = box.map { ToyBounds(lower: simd_min($0.lower, next.lower), upper: simd_max($0.upper, next.upper)) } ?? next
        }
        guard let box else { preconditionFailure("a box needs at least one pose") }
        self = box
    }

    /// The box around the rings, rods, beads and bar in every pose of `poses`, stretched to the sword's tip end as
    /// it is at home. The rings and the bar never move along the sword, only the sword slides, so a box made from a
    /// few moves holds every move; the sword's grip may leave it when the sword is drawn back.
    static func rings(_ poses: some Sequence<ToyPose>) -> ToyBounds {
        var box = ToyBounds(lower: SIMD3(repeating: .infinity), upper: SIMD3(repeating: -.infinity))
        for pose in poses {
            box.includeParts(of: pose)
        }
        precondition(box.lower.x <= box.upper.x, "a box needs at least one pose")
        // The tip is the sword's end on the rings' side, the end with the smaller x.
        box.lower.x = min(box.lower.x, sword.lower.x)
        return box
    }

    /// A cube of side `size` around `center`.
    init(center: SIMD3<Float>, size: Float) {
        self.init(lower: center - size / 2, upper: center + size / 2)
    }

    private init(lower: SIMD3<Float>, upper: SIMD3<Float>) {
        self.lower = lower
        self.upper = upper
    }

    private mutating func include(_ point: SIMD3<Float>, radius: Float) {
        lower = simd_min(lower, point - radius)
        upper = simd_max(upper, point + radius)
    }
}
