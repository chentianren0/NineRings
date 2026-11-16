import Geometry
import Toy
import simd

/// A part of the toy, as the checker names it. A rod is three shapes (its eye, its shaft and its bead), and the
/// sword is one shape per straight piece of its centreline.
enum PartName: Hashable, CustomStringConvertible {
    case ring(Int), eye(Int), shaft(Int), bead(Int), bar, sword

    var description: String {
        switch self {
        case .ring(let number): "ring \(number)"
        case .eye(let number): "eye \(number)"
        case .shaft(let number): "shaft \(number)"
        case .bead(let number): "bead \(number)"
        case .bar: "bar"
        case .sword: "sword"
        }
    }

    /// The rod a shape belongs to, if any.
    var rod: Int? {
        switch self {
        case .eye(let number), .shaft(let number), .bead(let number): number
        default: nil
        }
    }

    /// Whether two shapes may touch or overlap because the toy is built that way: one piece of the same part, a
    /// ring and the eye that holds it, and a rod and the bar at its own hole.
    func isJoined(to other: PartName) -> Bool {
        if self == other { return true }
        if let rod, rod == other.rod { return true }
        switch (self, other) {
        case (.ring(let a), .eye(let b)), (.eye(let b), .ring(let a)): return a == b
        case (.shaft, .bar), (.bar, .shaft): return true
        default: return false
        }
    }
}

/// The middle of a shape, swept by a radius.
enum ShapeCore {
    case circle(Circle)
    case segment(Segment)
    case point(Vector)
    case stadium(Stadium)
}

struct Shape {
    var name: PartName
    var core: ShapeCore
    var radius: Double

    /// A sphere that holds the whole shape, for skipping pairs that are far apart.
    var boundCenter: Vector
    var boundRadius: Double

    init(_ name: PartName, _ core: ShapeCore, radius: Double) {
        self.name = name
        self.core = core
        self.radius = radius
        switch core {
        case .circle(let circle):
            (boundCenter, boundRadius) = (circle.center, circle.radius + radius)
        case .segment(let segment):
            boundCenter = (segment.start + segment.end) / 2
            boundRadius = simd_distance(segment.start, segment.end) / 2 + radius
        case .point(let point):
            (boundCenter, boundRadius) = (point, radius)
        case .stadium(let stadium):
            (boundCenter, boundRadius) = (stadium.center, stadium.halfLength + stadium.radius + radius)
        }
    }
}

extension ToyPose {
    /// Every shape of the toy in this pose.
    var shapes: [Shape] {
        var shapes: [Shape] = []
        typealias Rod = Dimensions.Rod
        for number in 1...9 {
            let ring = ring(number)
            shapes.append(Shape(.ring(number), .circle(ring.circle), radius: Dimensions.Ring.wireRadius))
            let rod = rod(number)
            shapes.append(Shape(.eye(number), .circle(rod.eye), radius: Rod.wireRadius))
            shapes.append(Shape(.shaft(number), .segment(rod.shaft), radius: Rod.wireRadius))
            shapes.append(Shape(.bead(number), .point(rod.worldPoint(SIMD3(0, Rod.beadCenterY, 0))), radius: Rod.beadRadius))
        }
        shapes.append(Shape(.bar, .stadium(bar.stadium), radius: Dimensions.Bar.thickness / 2))
        for side in [1.0, -1.0] {
            let points = swordCenterline(side: side)
            for (start, end) in zip(points, points.dropFirst()) {
                shapes.append(Shape(.sword, .segment(Segment(start: start, end: end)), radius: Dimensions.Sword.wireRadius))
            }
        }
        return shapes
    }

    /// One side of the sword's centreline, from the tip's outermost point to the end of the neck, where it is now.
    /// The grip loops beyond the neck are left out: nothing comes near them.
    func swordCenterline(side: Double) -> [Vector] {
        SwordShape.centerline(side: side, tipSegments: 48).map { $0 + SIMD3(swordSlide, 0, 0) }
    }
}

extension PartPose {
    /// A ring's centreline.
    var circle: Circle {
        Circle(center: position, axisU: worldDirection(SIMD3(1, 0, 0)), axisV: worldDirection(SIMD3(0, 1, 0)), radius: Dimensions.Ring.radius)
    }

    /// A rod's eye's centreline.
    var eye: Circle {
        Circle(center: position, axisU: worldDirection(SIMD3(1, 0, 0)), axisV: worldDirection(SIMD3(0, 1, 0)), radius: Dimensions.Rod.eyeRadius)
    }

    /// A rod's shaft, from where it leaves the eye to the middle of the bead.
    var shaft: Segment {
        Segment(start: worldPoint(SIMD3(0, Dimensions.Rod.shaftTopY, 0)), end: worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0)))
    }

    /// The bar's middle sheet.
    var stadium: Stadium {
        typealias Bar = Dimensions.Bar
        return Stadium(
            center: position,
            lengthAxis: worldDirection(SIMD3(1, 0, 0)),
            widthAxis: worldDirection(SIMD3(0, 0, 1)),
            halfLength: Bar.length / 2 - Bar.width / 2,
            radius: Bar.width / 2
        )
    }
}
