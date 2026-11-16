import Foundation
import simd

/// How a ring is turned about its eye, and how high its eye is, each a ``Curve`` of a path's own parameter.
///
/// The turns are applied one after another, starting from the ring leaning down toward the tip with its wire
/// running across the sword through the eye:
///
/// - `lid`: the ring swings about the line of its wire through the eye, from leaning down toward the tip, through
///   lying flat, to standing straight up over its eye. Turning about its own wire leaves the eye facing along the
///   wire all the way.
/// - `turn`: standing on its eye, the ring turns about the upright, from across the sword to along it.
/// - `tip`: the ring tips over toward the tip, about the line across the sword through the eye.
/// - `tilt`: it rolls about the line from the eye to its middle.
/// - `swing`: it swings about the upright through the eye.
///
/// The eye stays above the ring's own hole, at the height `eyeHeight` gives, so the rod stands straight.
///
/// A ring that never needs to stand up can be written with the lid at 180° and the turn at 90°, standing along
/// the sword, and then only tipped, tilted and swung: tipped by 180° less its lean and tilted by 90°, it leans
/// toward the tip across the sword, as a ring that is on rests.
struct RingTurns: Sendable {
    var lid: Curve
    var turn: Curve
    var tip: Curve
    var tilt: Curve
    var swing: Curve
    var eyeHeight: Curve

    /// Ring `ring` as its rod holds it, at `progress` along the path's own parameter.
    func held(_ ring: Int, at progress: Double) -> HeldRing {
        let lid = lid.value(at: progress)
        // Leaning down toward the tip, and running across the sword through the eye.
        var center = SIMD3(-sin(lid), -cos(lid), 0)
        var wire = SIMD3<Double>(0, 0, 1)

        let turn = simd_quatd(angle: turn.value(at: progress), axis: SIMD3(0, 1, 0))
        center = turn.act(center)
        wire = turn.act(wire)

        let tip = simd_quatd(angle: tip.value(at: progress), axis: SIMD3(0, 0, 1))
        center = tip.act(center)
        wire = tip.act(wire)

        let tilt = simd_quatd(angle: tilt.value(at: progress), axis: -center)
        wire = tilt.act(wire)

        let swing = simd_quatd(angle: swing.value(at: progress), axis: SIMD3(0, 1, 0))
        center = swing.act(center)
        wire = swing.act(wire)

        let eye = SIMD3(Layout.hole(ring).x, eyeHeight.value(at: progress), 0)
        return HeldRing(eye: eye, towardCenter: center, alongWire: wire)
    }

    /// A curve of angles given in degrees.
    static func degrees(_ keys: [(Double, Double)]) -> Curve {
        Curve(keys.map { Curve.Key($0.0, $0.1 * .pi / 180) })
    }

    /// A curve of lengths given in millimetres.
    static func millimetres(_ keys: [(Double, Double)]) -> Curve {
        Curve(keys.map { Curve.Key($0.0, $0.1) })
    }

    static let leanOnDegrees = Layout.leanOn * 180 / .pi
    static let leanHangingDegrees = Layout.leanHanging * 180 / .pi
}
