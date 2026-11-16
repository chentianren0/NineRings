import Foundation
import simd

/// The sword's centreline: the one definition of the sword's shape, which the app draws and the checker checks.
///
/// The sword is one wire. From the tip's outermost point, each side runs round a quarter of the tip's half circle,
/// which rises out of the plane of the rails, straight on to the end of the rise, along its rail, in to the
/// shoulder, where the two wires touch, along the neck, and round its grip loop, which comes back to lie against
/// the wire where the loop begins. Wherever the wire turns a corner, at the end of the rise, at the end of the
/// rail and at the shoulder, it bends round ``Dimensions/Sword/bendRadius``.
///
/// The centreline is a path of straight pieces, and that path is the sword: the app draws a tube of the wire's
/// radius along these very points, and the checker checks a capsule of that radius round each piece. The curves
/// are followed closely enough that the path is within about 0.006 mm of the true curve, but nothing measures
/// against the true curve.
///
/// Everything is in millimetres in the sword's frame (see ``Dimensions/Sword``).
public enum SwordShape {
    /// One side of the sword, from the tip's outermost point to the end of its grip loop.
    ///
    /// The two sides meet at the first point. The last point lies against the side's own wire, 0.3 mm from its
    /// centreline, where the grip loop closes.
    ///
    /// - Parameter side: `1` for the side at positive z, `-1` for the one at negative z.
    public static func centerline(side: Double) -> [SIMD3<Double>] {
        precondition(side == 1 || side == -1, "a side is 1 or -1")
        return side == 1 ? nearSide : farSide
    }

    /// The whole wire as one path, from the end of the far grip loop, round the tip, to the end of the near one.
    /// This is what the app draws.
    public static let wire: [SIMD3<Double>] = Array(farSide.reversed()) + nearSide.dropFirst()

    /// How many straight pieces follow a quarter of the tip's half circle: about 0.31 mm each.
    public static let tipPieces = 48
    /// The largest angle one straight piece of a bend turns through: 0.31 mm of wire at the bend radius.
    public static let largestBendStep = 6 * Double.pi / 180
    /// How many straight pieces follow each grip loop: about 0.4 to 0.8 mm each.
    public static let gripLoopPieces = 96
    /// How far short of closing each grip loop stops, as an angle round the loop, so that the end of its wire lies
    /// against the wire where the loop begins rather than on it.
    public static let gripLoopOpening = 0.3

    private static let nearSide = side(1)
    private static let farSide = side(-1)

    private static func side(_ side: Double) -> [SIMD3<Double>] {
        typealias Sword = Dimensions.Sword
        let radius = Sword.railOffset
        let level = Sword.railHeight

        // A quarter of the tip's half circle, on the surface that rises toward the tip's end.
        var points: [SIMD3<Double>] = (0...tipPieces).map { step in
            let angle = Double(step) / Double(tipPieces) * .pi / 2
            let x = radius * (1 - cos(angle))
            return SIMD3(x, Sword.height(atX: x), side * radius * sin(angle))
        }

        // The corners the wire turns: the end of the rise, the end of the rail and the shoulder. Between them,
        // and on to the grip loop, it is straight. The tip's quarter circle meets the rise along the rise's own
        // direction, so it needs no bend.
        let loop = gripLoop(side: side)
        let corners = [
            points[points.count - 1],
            SIMD3(Sword.tipRiseLength, level, side * radius),
            SIMD3(Sword.railEndX, level, side * radius),
            SIMD3(Sword.shoulderX, level, side * Sword.wireRadius),
            loop[0],
        ]
        for index in 1..<(corners.count - 1) {
            points += bend(corners[index - 1], corners[index], corners[index + 1])
        }
        points += loop
        return points
    }

    /// The wire round a corner, bending round the bend radius: points from where the bend leaves the straight
    /// piece coming in to where it joins the straight piece going out.
    private static func bend(_ previous: SIMD3<Double>, _ corner: SIMD3<Double>, _ next: SIMD3<Double>) -> [SIMD3<Double>] {
        let radius = Dimensions.Sword.bendRadius
        let incoming = simd_normalize(corner - previous)
        let outgoing = simd_normalize(next - corner)
        let turn = acos(min(max(simd_dot(incoming, outgoing), -1), 1))
        let reach = radius * tan(turn / 2)
        precondition(reach < simd_distance(previous, corner) / 2 && reach < simd_distance(corner, next) / 2, "a bend fits on its straight pieces")
        // Toward the inside of the bend, square to the wire coming in.
        let inward = simd_normalize(outgoing - simd_dot(outgoing, incoming) * incoming)
        let center = corner - incoming * reach + inward * radius
        let pieces = max(2, Int((turn / largestBendStep).rounded(.up)))
        return (0...pieces).map { step in
            let angle = turn * Double(step) / Double(pieces)
            return center + radius * (incoming * sin(angle) - inward * cos(angle))
        }
    }

    /// One grip loop: the wire comes straight along the neck and on past its end to the loop's first point, then
    /// turns outward round an oval in the plane of the rails and comes back to lie against itself.
    private static func gripLoop(side: Double) -> [SIMD3<Double>] {
        typealias Sword = Dimensions.Sword
        let wire = Sword.wireRadius
        // Half the oval's length and half its width, measured on the wire's centreline.
        let halfLength = (Sword.gripLoopLength - 2 * wire) / 2
        let halfWidth = (Sword.gripLoopSpan / 2 - 2 * wire) / 2
        let center = SIMD3(Sword.neckEndX + halfLength, Sword.railHeight, side * (wire + halfWidth))
        let sweep = 2 * Double.pi - gripLoopOpening
        return (0...gripLoopPieces).map { step in
            let angle = -Double.pi / 2 + sweep * Double(step) / Double(gripLoopPieces)
            return center + SIMD3(halfLength * cos(angle), 0, side * halfWidth * sin(angle))
        }
    }
}
