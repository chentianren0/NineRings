import CoreGraphics
import Foundation

// Bauhaus and Constructivism: the sword as a rising diagonal bar, the rings as upright loops wrapped round it, a few
// strong colours with black on off-white paper, each picture built like a poster around one great plane of colour.
//
// Every picture is drawn in the sword's own frame: u runs along the sword from the grip towards the tip, v across it
// (positive below the sword).

// MARK: Palette

let paper = rgb(0xECE5D3)
let ink = rgb(0x151515)
let red = rgb(0xD42B1E)
let blue = rgb(0x1C4C9A)
let yellow = rgb(0xF0B91A)

// MARK: The frame

/// The sword rises at this angle, in degrees above the horizontal.
let rise: CGFloat = 30
/// Where the middle of the sword's axis sits on the canvas.
let origin = pt(512, 520)

let frame = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: -rise * .pi / 180)

// MARK: The sword

let gripStart: CGFloat = -425
let gripEnd: CGFloat = -285
let gripHalf: CGFloat = 60
let railHalf: CGFloat = 44  // half the distance between the middles of the two wires
let railWidth: CGFloat = 27
let tipCentre: CGFloat = 360

/// The sword's two wires: one loop from the grip, round the tip and back.
func wires() -> CGPath {
    let p = CGMutablePath()
    p.move(to: pt(gripEnd - 10, -railHalf))
    p.addLine(to: pt(tipCentre, -railHalf))
    p.addArc(center: pt(tipCentre, 0), radius: railHalf, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.addLine(to: pt(gripEnd - 10, railHalf))
    return outline(p, width: railWidth, cap: .butt, join: .round)
}

func grip() -> CGPath { rect(gripStart, -gripHalf, gripEnd - gripStart, 2 * gripHalf) }

// MARK: The rings

/// A ring on the sword stands across it and is seen edge on: a bar. Off the sword it lies flat: a circle.
let ringAcross: CGFloat = 110  // half its length, across the sword
let ringWidth: CGFloat = 30

/// Where ring `n` (1 at the tip, 9 by the grip) sits along the sword.
func ringU(_ n: Int) -> CGFloat { 300 - CGFloat(n - 1) * 68 }

func ringBand(_ centre: CGPoint) -> CGPath {
    rect(centre.x - ringWidth / 2, centre.y - ringAcross, ringWidth, 2 * ringAcross)
}

extension CGContext {
    /// The sword with these rings on it, woven: each ring passes over the upper wire and under the lower one.
    func sword(rings: [Int], ringColor: CGColor = ink, wire: CGColor = ink, gripColor: CGColor = ink) {
        fill(wires(), wire)
        for n in rings {
            let band = ringBand(pt(ringU(n), 0))
            fill(band, ringColor)
            clipped(to: band) { clipped(to: rect(-600, 0, 1200, 300)) { fill(wires(), wire) } }
        }
        fill(grip(), gripColor)
    }
}

// MARK: The ruler

/// A hairline parallel to the sword, with a tick under each ring's place: the measure every picture stands on.
let rulerV: CGFloat = 215

extension CGContext {
    func ruler(marked: [Int] = [], mark: CGColor = red) {
        fill(rect(-560, rulerV, 1120, 5), ink)
        for n in 1...9 {
            let u = ringU(n)
            let tick = marked.contains(n)
            fill(rect(u - (tick ? 5 : 2.5), rulerV - (tick ? 34 : 22), tick ? 10 : 5, tick ? 34 : 22), tick ? mark : ink)
        }
    }
}

// MARK: The pictures

func draw(_ picture: AchievementPicture, in c: CGContext) {
    c.background(paper)
    switch picture {
    case .allNineOff: allNineOff(c)
    case .shortestWay: shortestWay(c)
    case .allNineBackOn: allNineBackOn(c)
    case .farEnd: farEnd(c)
    }
}

/// A red sun; the sword empty across it, and the nine rings fallen off it, lying flat on the line beneath.
func allNineOff(_ c: CGContext) {
    c.fill(circle(pt(620, 390), 270), red)
    c.transformed(frame) {
        c.fill(rect(-150, -330, 64, 64), blue)
        c.fill(rect(-560, rulerV, 1120, 5), ink)
        c.sword(rings: [])
        // Lying flat, a ring is a circle; each one rests on the line, a little behind the one before.
        let r: CGFloat = 34
        for n in 1...9 {
            let centre = pt(ringU(n) - 34, rulerV - r - 6)
            c.fill(annulus(centre, outer: r + 7, inner: r - 7), ink)
        }
    }
}

/// The paper cut along the sword, black above and light below; a red wedge drives straight along it, through the tip.
func shortestWay(_ c: CGContext) {
    let above = rect(-1400, -1400, 2800, 1400)
    let below = rect(-1400, 0, 2800, 1400)
    c.transformed(frame) {
        c.fill(above, ink)
        c.ruler()
        // A disc at the tip, turned inside out by the cut.
        let disc = circle(pt(tipCentre + 10, 0), 132)
        c.clipped(to: above) { c.fill(disc, paper) }
        c.clipped(to: below) { c.fill(disc, ink) }
        c.clipped(to: above) { c.fill(wires(), ink) }
        c.clipped(to: below) { c.fill(wires(), paper) }
        c.clipped(outside: disc) {
            c.clipped(to: above) { c.fill(wires(), paper) }
            c.clipped(to: below) { c.fill(wires(), ink) }
        }
        let wedge = polygon([pt(gripEnd, -railHalf + 8), pt(tipCentre + 260, 0), pt(gripEnd, railHalf - 8)])
        c.fill(wedge, red)
        c.fill(grip(), red)
    }
}

/// A blue band behind, a red dot above; all nine rings back on the sword.
func allNineBackOn(_ c: CGContext) {
    c.transformed(frame) {
        c.fill(rect(-330, -175, 700, 350), blue)
        c.fill(circle(pt(-120, -300), 44), red)
        c.ruler()
        c.sword(rings: Array(1...9), ringColor: yellow)
    }
}

/// Only ring 9 left, by the grip, on a great yellow disc; the rest of the sword runs on empty to the tip.
func farEnd(_ c: CGContext) {
    c.transformed(frame) {
        c.fill(circle(pt(ringU(9) + 10, 0), 220), yellow)
        c.ruler(marked: [9])
        c.sword(rings: [9], ringColor: red)
        c.fill(rect(-20, -320, 60, 60), blue)
    }
}
