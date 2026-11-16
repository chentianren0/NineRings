import Geometry
import simd

/// The smallest gap between the surfaces of two shapes that are not joined by design.
struct Gap: CustomStringConvertible {
    var distance: Double
    var first: PartName
    var second: PartName
    var pointA: Vector
    var pointB: Vector

    var description: String {
        let format = { (value: Double) in String(format: "%.3f", value) }
        return "\(format(distance)) mm between \(first) and \(second) near (\(format(pointA.x)), \(format(pointA.y)), \(format(pointA.z)))"
    }
}

enum Gaps {
    /// The smallest gap between any two shapes of `shapes` not joined by design, looking only at pairs that can
    /// come within `reach` of each other; nil when none can.
    static func smallest(in shapes: [Shape], reach: Double = 3, involving parts: Set<PartName>? = nil) -> Gap? {
        var smallest: Gap?
        for (index, first) in shapes.enumerated() {
            for second in shapes[(index + 1)...] where !first.name.isJoined(to: second.name) {
                if let parts, !parts.contains(first.name), !parts.contains(second.name) { continue }
                if simd_distance(first.boundCenter, second.boundCenter) > first.boundRadius + second.boundRadius + reach {
                    continue
                }
                let (pointA, pointB) = nearest(first.core, second.core)
                let distance = simd_distance(pointA, pointB) - first.radius - second.radius
                if distance < smallest?.distance ?? .infinity {
                    smallest = Gap(distance: distance, first: first.name, second: second.name, pointA: pointA, pointB: pointB)
                }
            }
        }
        return smallest
    }

    /// The nearest points of two cores.
    static func nearest(_ a: ShapeCore, _ b: ShapeCore) -> (Vector, Vector) {
        switch (a, b) {
        case (.circle(let circle), _):
            return nearest(curve: circle, to: b, samples: 96)
        case (_, .circle):
            let (pointB, pointA) = nearest(b, a)
            return (pointA, pointB)
        case (.segment(let first), .segment(let second)):
            let approach = Approaches.nearest(first, second)
            return (approach.pointA, approach.pointB)
        case (.segment(let segment), _):
            return nearest(curve: segment, to: b, samples: 48)
        case (_, .segment):
            let (pointB, pointA) = nearest(b, a)
            return (pointA, pointB)
        case (.point(let point), _):
            return (point, nearestPoint(of: b, to: point))
        case (_, .point(let point)):
            return (nearestPoint(of: a, to: point), point)
        case (.stadium, .stadium):
            preconditionFailure("the toy has one bar")
        }
    }

    private static func nearestPoint(of core: ShapeCore, to point: Vector) -> Vector {
        switch core {
        case .circle(let circle): circle.nearestPoint(to: point)
        case .segment(let segment): segment.nearestPoint(to: point)
        case .point(let other): other
        case .stadium(let stadium): stadium.nearestPoint(to: point)
        }
    }

    /// The nearest points of a curve and another core, the curve's point first.
    private static func nearest(curve: some CurveCore, to other: ShapeCore, samples: Int) -> (Vector, Vector) {
        var approaches: [Approach] = []
        switch other {
        case .circle(let circle): Approaches.find(curve, circle, within: .infinity, samples: samples, into: &approaches)
        case .segment(let segment): Approaches.find(curve, segment, within: .infinity, samples: samples, into: &approaches)
        case .point(let point): Approaches.find(curve, PointCore(position: point), within: .infinity, samples: samples, into: &approaches)
        case .stadium(let stadium): Approaches.find(curve, stadium, within: .infinity, samples: samples, into: &approaches)
        }
        guard let best = approaches.min(by: { $0.distance < $1.distance }) else {
            preconditionFailure("a search within any distance always finds something")
        }
        return (best.pointA, best.pointB)
    }
}
