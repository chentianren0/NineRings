import Foundation
import Puzzle
import Toy
import simd

/// The written path of ring 1 coming off while every other ring is on.
///
/// The path is a handful of numbers, each a ``Curve`` of the progress, and one rule that turns them into where the
/// ring is. Every turn of the ring is about an axis through its eye, so the eye is where the eye's numbers put it:
///
/// - `lid`: the ring swings about the line of its wire through the eye, from leaning down toward the tip, through
///   lying flat, to standing straight up over its eye. Turning about its own wire leaves the eye facing along the
///   wire all the way.
/// - `turn`: standing on its eye, the ring turns about the upright, from across the sword to along it.
/// - `tip`: the ring tips over toward the tip, about the line across the sword through the eye.
/// - `tilt`: at the same time it rolls about the line from the eye to its middle, so that its wire through the eye
///   stays within reach of level while it tips past lying on its side, and it ends hanging across the sword.
/// - `swing`: and it swings about the upright, first to one side and then to the other, so that the part of it
///   still above the rails is carried in over the slot rather than onto a rail.
///
/// The eye stays put above its hole until the ring goes down; then it goes down into the slot first. The ring
/// tips over and slips through the slot at a slant, partly over one rail and partly under the other, and comes to
/// hang across the sword in front of ring 2's lower arc. Only then does the eye sink below the rails, just above
/// ring 2's lower arc, and the rod leave the slot: while the eye is that low, ring 2's lower arc wraps round under
/// it so closely that ring 1 can only lie across the sword, and lying across it cannot pass between the rails.
///
/// The sword slides toward the grip to bring its tip end under the ring for the lift over it, then back home so
/// that the slot is long enough in front of the eye for the drop.
///
/// The drop's key values were found by a search for the path with the most room (see `TuneTests`), and are
/// written here as plain numbers.
struct RingOneOff: Sendable {
    /// The stages, as spans of the path's own parameter (see ``timing``).
    static let stagesAlongThePath = [
        Stage(name: "Flatten", start: 0, end: 0.16),
        Stage(name: "Over the tip", start: 0.16, end: 0.30),
        Stage(name: "Back over the slot", start: 0.30, end: 0.42),
        Stage(name: "Turn", start: 0.42, end: 0.56),
        Stage(name: "Down through the slot", start: 0.56, end: 0.84),
        Stage(name: "Hang", start: 0.84, end: 1),
    ]

    static func degrees(_ keys: [(Double, Double)]) -> Curve {
        Curve(keys.map { Curve.Key($0.0, $0.1 * .pi / 180) })
    }

    static func millimetres(_ keys: [(Double, Double)]) -> Curve {
        Curve(keys.map { Curve.Key($0.0, $0.1) })
    }

    static let leanOnDegrees = Layout.leanOn * 180 / .pi
    static let leanHangingDegrees = Layout.leanHanging * 180 / .pi

    var lid: Curve
    var turn: Curve
    var tip: Curve
    var tilt: Curve
    var swing: Curve
    var eyeHeight: Curve
    var swordSlide: Curve

    /// The path as written.
    static let written = RingOneOff(
        lid: degrees([(0, leanOnDegrees), (0.16, 76), (0.30, 130), (0.45, 180)]),
        turn: degrees([(0.39, 0), (0.56, 90)]),
        tip: degrees([(0.55, 0), (0.6036, 22.401), (0.7267, 84.416), (0.9384, 180 - leanHangingDegrees)]),
        tilt: degrees([(0.5694, 0), (0.677, 36.106), (0.6882, 58.639), (1, 90)]),
        swing: degrees([(0.585, 0), (0.6842, 29.932), (0.706, 2.61), (0.7734, -26.703), (0.8983, 0)]),
        eyeHeight: millimetres([(0.56, Layout.eyeHeightOn), (0.6583, -3.653), (0.8198, -6.088), (0.9549, Layout.eyeHeightHanging)]),
        swordSlide: millimetres([(0, Layout.swordHome), (0.18, 12.5), (0.40, Layout.swordHome)])
    )

    /// Ring 1 as its rod holds it, at `progress` along the path's own parameter.
    func held(at progress: Double) -> HeldRing {
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

        let eye = SIMD3(Layout.hole(1).x, eyeHeight.value(at: progress), 0)
        return HeldRing(eye: eye, towardCenter: center, alongWire: wire)
    }

    /// The toy at `progress` along the path's own parameter.
    func pose(at progress: Double) -> ToyPose {
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = held(at: progress)
        return RestPoses.pose(holding: rings, swordSlide: swordSlide.value(at: progress))
    }

    // MARK: Timing

    /// How the move's progress maps onto the path's own parameter.
    ///
    /// The curves above are keyed for where things happen, not for how fast they happen, and some stretches of
    /// the path move the ring much faster than others. This curve gives each stretch time in proportion to how far
    /// the ring travels in it, mostly, so the move flows at a steady pace and starts and ends at rest. It is
    /// worked out once, from the path, and changes only when the move is played, never where the ring goes.
    static let timing: Curve = {
        let path = RingOneOff.written
        let pieces = 400
        let poses = (0...pieces).map { path.pose(at: Double($0) / Double(pieces)) }
        // How far the farthest point of anything moves along each piece of the path.
        let travel = zip(poses, poses.dropFirst()).map { a, b in
            var largest = abs(a.swordSlide - b.swordSlide)
            for (first, second) in zip(a.rings + a.rods, b.rings + b.rods) {
                let turn = first.orientation.inverse * second.orientation
                let angle = 2 * atan2(simd_length(turn.imag), abs(turn.real))
                largest = max(largest, simd_distance(first.position, second.position) + angle * reachOfARing)
            }
            return largest
        }
        // Time for each piece: mostly in proportion to its travel, partly the same for every piece, so that the
        // nearly still stretches near the ends are not skipped through.
        let mean = travel.reduce(0, +) / Double(travel.count)
        let weights = travel.map { 0.8 * $0 + 0.2 * mean }
        let total = weights.reduce(0, +)
        var keys = [Curve.Key(0, 0)]
        var elapsed = 0.0
        for (index, weight) in weights.enumerated() {
            elapsed += weight / total
            if (index + 1) % 10 == 0 {
                keys.append(Curve.Key(min(elapsed, 1), Double(index + 1) / Double(pieces)))
            }
        }
        keys[keys.count - 1] = Curve.Key(1, 1)
        return Curve(keys)
    }()

    /// The farthest a point of a ring is from the ring's middle.
    private static let reachOfARing = Dimensions.Ring.radius + Dimensions.Ring.wireRadius

    /// The stages as spans of the move's progress.
    static let stages: [Stage] = stagesAlongThePath.map { stage in
        Stage(name: stage.name, start: progress(atPathParameter: stage.start), end: progress(atPathParameter: stage.end))
    }

    /// The progress at which the move reaches `parameter` along the path, found by halving.
    private static func progress(atPathParameter parameter: Double) -> Double {
        if parameter <= 0 { return 0 }
        if parameter >= 1 { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if timing.value(at: middle) < parameter { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// The toy a fraction `progress` of the way through the move.
    static func pose(atProgress progress: Double) -> ToyPose {
        written.pose(at: timing.value(at: progress))
    }
}
