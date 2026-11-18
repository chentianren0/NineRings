import CoreGraphics
import Foundation

// The Shortest Way and All Nine Back On, designed from zero in the art of the Bauhaus and Constructivism, after the
// two pictures that stay (All Nine Off and The Far End, in Bauhaus.swift): their paper, their colours, the way the
// sword is drawn and its 30 degree rise. Drawn on the canvas itself, along an axis, not in Bauhaus.swift's frame.

// MARK: - What the two pictures share

/// A straight axis on the canvas: `t` runs along it and `s` across it. For an axis that rises to the right,
/// a positive `s` is below it.
struct Axis {
    var origin: CGPoint
    var degrees: CGFloat
    var radians: CGFloat { degrees * .pi / 180 }
    var u: CGPoint { CGPoint(x: cos(radians), y: sin(radians)) }
    var n: CGPoint { CGPoint(x: -u.y, y: u.x) }

    func at(_ t: CGFloat, _ s: CGFloat = 0) -> CGPoint {
        CGPoint(x: origin.x + u.x * t + n.x * s, y: origin.y + u.y * t + n.y * s)
    }

    /// Everything before the line across the axis at `t`, or everything after it.
    func side(of t: CGFloat, after: Bool) -> CGPath {
        let far: CGFloat = after ? 3000 : -3000
        return polygon([at(t, -3000), at(t + far, -3000), at(t + far, 3000), at(t, 3000)])
    }

    /// A square of this side that stands on the axis, from `t` on.
    func square(from t: CGFloat, side: CGFloat) -> CGPath {
        polygon([at(t, -side / 2), at(t + side, -side / 2), at(t + side, side / 2), at(t, side / 2)])
    }

    /// The line that runs along the axis at distance `d` below it up to `t`, turns round the point at `t`, and
    /// runs back above it: the shape of the sword's own loop, `d` away from the axis.
    func turn(at t: CGFloat, distance d: CGFloat, from start: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: at(start, d))
        p.addLine(to: at(t, d))
        p.addArc(center: at(t), radius: d, startAngle: radians + .pi / 2, endAngle: radians - .pi / 2, clockwise: true)
        p.addLine(to: at(start, -d))
        return p
    }
}

/// The family's direction: rising to the right at 30 degrees, here through the middle of the picture.
let diagonal = Axis(origin: middle, degrees: -30)

/// The sword as the family draws it: a long narrow loop of one black line, and a square handle.
/// `tip` is the centre of the round end on the axis and `loop` the length of the straight part. At `scale` 1 it has
/// the family's size: a line of 27, 88 between the two sides of the loop, a handle of 140.
struct Sword {
    var axis: Axis
    var tip: CGFloat
    var loop: CGFloat
    var scale: CGFloat = 1

    var line: CGFloat { 27 * scale }
    var rail: CGFloat { 44 * scale }
    var grip: CGFloat { 140 * scale }
    /// From the axis to the outside of the loop.
    var halfWidth: CGFloat { rail + line / 2 }
    var tipEnd: CGFloat { tip + halfWidth }
    var loopStart: CGFloat { tip - loop }
    var handleEnd: CGFloat { tip - loop - grip }

    func draw(_ c: CGContext) {
        let path = axis.turn(at: tip, distance: rail, from: loopStart)
        c.fill(outline(path, width: line, cap: .butt, join: .miter), ink)
        c.fill(
            polygon([
                axis.at(handleEnd, -grip / 2), axis.at(loopStart, -grip / 2), axis.at(loopStart, grip / 2),
                axis.at(handleEnd, grip / 2),
            ]), ink)
    }
}

/// A flat ring whose middle is on the axis at `t`.
struct Ring {
    var t: CGFloat
    var radius: CGFloat
    var width: CGFloat
    var color: CGColor

    func shape(on axis: Axis) -> CGPath {
        width >= radius ? circle(axis.at(t), radius) : annulus(axis.at(t), outer: radius, inner: radius - width)
    }
}

/// Rings with the sword through them: the half of each ring towards the handle passes behind the sword, and the
/// half towards the tip in front of it. `between` is drawn where the sword is, between the two halves.
func thread(_ c: CGContext, _ rings: [Ring], on axis: Axis, between: () -> Void) {
    for r in rings {
        c.clipped(to: axis.side(of: r.t + 0.75, after: false)) { c.fill(r.shape(on: axis), r.color) }
    }
    between()
    for r in rings {
        c.clipped(to: axis.side(of: r.t - 0.75, after: true)) { c.fill(r.shape(on: axis), r.color) }
    }
}

// MARK: - The Shortest Way

/// The ring each of the 341 moves of the shortest way moves: 0 for the ring that moves every other time, up to 8
/// for the ring that moves once. The puzzle's arrangements lie on one path; every ring on is 341 steps along it and
/// every ring off is step 0, and the move that leaves step b is of the ring "how many times 2 divides b".
let shortestWay: [Int] = (0..<341).map { (341 - $0).trailingZeroBitCount }

/// How many of the 341 moves each ring makes: 171, 85, 43, 21, 11, 5, 3, 1, 1.
let shares: [Int] = (0..<9).map { ring in shortestWay.filter { $0 == ring }.count }

/// A, the measure. Nine rings in a row, each as wide as the number of moves it makes: together they are 341 wide,
/// the length of the way and not one more. Each is about half the one before, so the row runs between two straight
/// lines into a point. The sword starts inside the first two rings, and the way leaves it as one straight red line.
func shortestWayMeasure(_ c: CGContext) {
    c.background(paper)
    let ax = diagonal
    let start: CGFloat = -318
    let end: CGFloat = 396
    let unit = (end - start) / 341

    // Rings that halve for ever would end at 342: there the two lines that touch them all meet.
    let apex = start + 342 * unit
    let spread = tan(asin(1.0 / 3))
    c.fill(polygon([ax.at(apex), ax.at(apex - 1400, -1400 * spread), ax.at(apex - 1400, 1400 * spread)]), yellow)

    var rings: [Ring] = []
    var t = start
    for share in shares {
        let d = CGFloat(share) * unit
        rings.append(Ring(t: t + d / 2, radius: d / 2, width: max(d * 0.085, 2.6), color: ink))
        t += d
    }

    // The sword's round end reaches the middle of the second ring.
    var sword = Sword(axis: ax, tip: 0, loop: 0, scale: 0.8)
    sword.tip = rings[1].t - sword.halfWidth
    sword.loop = sword.tip - (start - 22)

    // The way: a line from where the loop begins that narrows to the point.
    c.fill(polygon([ax.at(sword.loopStart, -6.5), ax.at(apex + 4, -2), ax.at(apex + 4, 2), ax.at(sword.loopStart, 6.5)]), red)
    thread(c, rings, on: ax) { sword.draw(c) }
    // The family's blue square, here the point the way ends on.
    c.fill(ax.square(from: apex + 2, side: 60), blue)
}

// MARK: - All Nine Back On

/// C, the full circle. A way that comes back to where it began is a circle. The thin ruled line of The Far End is
/// closed round a blue disc; its nine marks are spaced by the number of moves each ring makes, so one whole turn is
/// the 341 moves of the way back, and the red mark at the top is where it begins and ends. The nine rings sit on the
/// sword inside the circle, seen edge on.
func backOnFullCircle(_ c: CGContext) {
    c.background(paper)
    let ax = diagonal
    let sword = Sword(axis: ax, tip: 354, loop: 705, scale: 0.8)
    c.fill(circle(middle, 340), blue)

    let ruled: CGFloat = 388
    c.stroke(circle(middle, ruled), ink, width: 5)
    // Clockwise from the top: half the turn for the ring that moves 171 times, a quarter for the next, and so on.
    var turned: CGFloat = 0
    for (ring, share) in shares.enumerated() {
        turned += CGFloat(share) / 341 * 360
        let closing = ring == 8
        c.stroke(
            line(polar(middle, ruled - 32, 270 + turned), polar(middle, ruled + (closing ? 16 : 0), 270 + turned)),
            closing ? red : ink, width: closing ? 6 : 4.5, cap: .butt)
    }

    sword.draw(c)
    for k in 0..<9 {
        let t = 232 - 58 * CGFloat(k)
        c.stroke(line(ax.at(t, -88), ax.at(t, 88)), yellow, width: 21, cap: .butt)
    }
}
