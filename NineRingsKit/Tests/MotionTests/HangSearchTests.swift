import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Searches for how ring 1 can hang off with ring 2 standing up, for writing the rest pose by hand.
/// Run with `NINE_RINGS_HANG=1`, optimized; `NINE_RINGS_FREE_ROD2=1` lets rod 2 lean.
@Suite struct HangSearchTests {
    static let freeRodTwo = ProcessInfo.processInfo.environment["NINE_RINGS_FREE_ROD2"] != nil
    /// For a what-if only: how much further under the bar the beads of rings that are on would rest, which lets
    /// rod 2 rise by that much. Zero is the model as written.
    static let beadRoom = Double(ProcessInfo.processInfo.environment["NINE_RINGS_BEAD_ROOM"] ?? "0")!

    /// Ring 2's lean, side and roll; ring 1's eye, lean, side and roll; rod 2's eye offsets. Degrees and mm.
    static let names = ["lean2", "side2", "roll2", "eye1x", "eye1y", "eye1z", "lean1", "side1", "roll1", "eye2dx", "eye2dy", "eye2dz"]
    static let ranges: [ClosedRange<Double>] = [0...45, -40...40, -70...70, 30...52, -22...(-9.5), -9...9, -10...100, -70...70, -90...90, -14...6, -6...(Double(ProcessInfo.processInfo.environment["NINE_RINGS_BEAD_ROOM"] ?? "0")!), -9...9]

    static func direction(lean: Double, side: Double) -> SIMD3<Double> {
        let l = lean * .pi / 180, s = side * .pi / 180
        return SIMD3(-sin(l) * cos(s), -cos(l) * cos(s), sin(s))
    }

    static func held(_ v: [Double]) -> (ring1: HeldRing, ring2: HeldRing) {
        func ring(eye: SIMD3<Double>, lean: Double, side: Double, roll: Double) -> HeldRing {
            let center = direction(lean: lean, side: side)
            var reference = SIMD3<Double>(0, 0, 1) - simd_dot(SIMD3(0, 0, 1), center) * center
            if simd_length(reference) < 1e-6 { reference = SIMD3(1, 0, 0) }
            let wire = simd_quatd(angle: roll * .pi / 180, axis: center).act(simd_normalize(reference))
            return HeldRing(eye: eye, towardCenter: center, alongWire: wire)
        }
        let eye2 = RestPoses.on(2).eye + (freeRodTwo ? SIMD3(v[9], v[10], v[11]) : .zero)
        return (ring(eye: SIMD3(v[3], v[4], v[5]), lean: v[6], side: v[7], roll: v[8]),
                ring(eye: eye2, lean: v[0], side: v[1], roll: v[2]))
    }

    static let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .ring(2), .eye(2), .shaft(2), .bead(2)]

    static func score(_ v: [Double]) -> Double {
        let (one, two) = held(v)
        for (index, ring) in [one, two].enumerated() {
            let down = simd_normalize(Layout.hole(index + 1) - ring.eye)
            let angle = asin(min(1, abs(simd_dot(ring.alongWire, down)))) * 180 / .pi
            if angle > 55 { return -20 - angle / 10 }
        }
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = one
        rings[1] = two
        let pose = RestPoses.pose(holding: rings, swordSlide: 0)
        var penalty = Double(Relations.failures(in: pose).count)
        if Relations.isRoundTheRails(1, in: pose) { penalty += 1 }
        let eyeTop = one.eye.y + Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius
        if eyeTop > Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius - 0.2 { penalty += 1 }
        // Ring 1 hangs on the tip side of ring 2.
        let ringTwo = pose.ring(2).circle
        let towardTip = ringTwo.normal.x < 0 ? ringTwo.normal : -ringTwo.normal
        if simd_dot(pose.ring(1).position - ringTwo.center, towardTip) < 0 { penalty += 1 }
        var shapes = pose.shapes
        if Self.beadRoom > 0 {
            // The bar as if the beads rested further under it: moved up by the extra room.
            shapes = shapes.map { shape in
                guard shape.name == .bar, case .stadium(var stadium) = shape.core else { return shape }
                stadium.center.y += Self.beadRoom
                return Shape(.bar, .stadium(stadium), radius: shape.radius)
            }
        }
        let gap = Gaps.smallest(in: shapes, involving: moving)?.distance ?? 10
        return penalty > 0 ? min(gap, 0) - 3 * penalty : min(gap, 2)
    }

    static func describe(_ v: [Double]) -> String {
        zip(names, v).map { "\($0)=\(String(format: "%.2f", $1))" }.joined(separator: " ")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_HANG"] != nil))
    func searchHang() {
        var generator = SystemRandomNumberGenerator()
        let count = Int(ProcessInfo.processInfo.environment["NINE_RINGS_SAMPLES"] ?? "40000")!
        let candidates = (0..<count).map { _ in Self.ranges.map { Double.random(in: $0, using: &generator) } }
        let scores = Sweep.inParallel(candidates.count) { Self.score(candidates[$0]) }
        let order = scores.indices.sorted { scores[$0] > scores[$1] }
        print("feasible: \(scores.filter { $0 > 0 }.count) of \(count)")
        var results: [(Double, [Double])] = []
        for start in order.prefix(12) {
            var best = candidates[start], bestScore = scores[start]
            var scale = 1.0
            while scale > 0.01 {
                var improved = false
                for index in best.indices where Self.freeRodTwo || index < 9 {
                    for sign in [-1.0, 1.0] {
                        var trial = best
                        let span = Self.ranges[index].upperBound - Self.ranges[index].lowerBound
                        trial[index] = min(max(trial[index] + sign * span * 0.05 * scale, Self.ranges[index].lowerBound), Self.ranges[index].upperBound)
                        let s = Self.score(trial)
                        if s > bestScore { (best, bestScore, improved) = (trial, s, true) }
                    }
                }
                if !improved { scale /= 2 }
            }
            results.append((bestScore, best))
            print(String(format: "%.3f  ", bestScore) + Self.describe(best))
        }
    }

    /// Starts from the rest written now (ring 2 leaning 43 degrees) and stands ring 2 up a step at a time,
    /// re-optimising everything else at each step, to find how upright it can stand with ring 1 hanging off.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_STANDUP"] != nil))
    func standRingTwoUp() {
        var current: [Double] = [43, 0, 0, 32, Layout.eyeHeightHanging, 0, 60, 0, 0, 0, 0, 0]
        print("start: \(Self.score(current))")
        let free = Self.freeRodTwo ? Array(1..<12) : Array(1..<9)
        for lean in stride(from: 41.0, through: 5.0, by: -2.0) {
            current[0] = lean
            var bestScore = Self.score(current)
            var scale = 1.0
            while scale > 0.02 {
                var improved = false
                for index in free {
                    for sign in [-1.0, 1.0] {
                        var trial = current
                        let span = Self.ranges[index].upperBound - Self.ranges[index].lowerBound
                        trial[index] = min(max(trial[index] + sign * span * 0.03 * scale, Self.ranges[index].lowerBound), Self.ranges[index].upperBound)
                        let s = Self.score(trial)
                        if s > bestScore { (current, bestScore, improved) = (trial, s, true) }
                    }
                }
                if !improved { scale /= 2 }
            }
            print(String(format: "lean2 %4.1f: %.3f  ", lean, bestScore) + Self.describe(current))
            print("    tightest: \(Self.tightest(current))")
            if bestScore < -2 { break }
        }
    }

    /// The tightest pair of parts in a configuration, and anything that fails.
    static func tightest(_ v: [Double]) -> String {
        let (one, two) = held(v)
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = one
        rings[1] = two
        let pose = RestPoses.pose(holding: rings, swordSlide: 0)
        let gap = Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: moving)
        return "\(gap.map(String.init(describing:)) ?? "none")  \(Relations.failures(in: pose))"
    }
}

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension HangSearchTests {
    /// Draws the configurations found while standing ring 2 up, side and tip views, into `scratch/hang`.
    /// Run with `NINE_RINGS_DRAW=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_DRAW"] != nil))
    func drawStandUp() throws {
        let cases: [(String, [Double])] = [
            ("now-43deg", [43, 0, 0, 32, Layout.eyeHeightHanging, 0, 60, 0, 0, 0, 0, 0]),
            ("nearest-working-37deg", [37, 1.27, -3.81, 34.64, -9.55, 0, 60, 0, 0, 0, 0, 0]),
            ("blocked-25deg", [25, 2.17, -9.71, 39.59, -9.55, 0, 60, 0, 0, 0, 0, 0]),
        ]
        let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../scratch/hang").standardized
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, values) in cases {
            let (one, two) = Self.held(values)
            var rings = PuzzleState.rings.map(RestPoses.on)
            rings[0] = one
            rings[1] = two
            let pose = RestPoses.pose(holding: rings, swordSlide: 0)
            let gap = Gaps.smallest(in: pose.shapes.filter { $0.name != .bar }, involving: Self.moving)
            for view in ["side", "tip"] {
                let url = directory.appending(path: "\(name)-\(view).png")
                try Self.draw(pose, view: view, mark: gap, title: "\(name): ring 2 lean \(Int(values[0])) deg, tightest \(gap.map(String.init(describing:)) ?? "")", to: url)
                print("drew \(url.path)")
            }
        }
    }

    static func draw(_ pose: ToyPose, view: String, mark: Gap?, title: String, to url: URL) throws {
        let width = 1400, height = 1000
        let scale = 16.0
        // Side: x to the right, y up. Tip: z to the right, y up, looking along +x.
        let center = SIMD3<Double>(40, -14, 0)
        func project(_ p: SIMD3<Double>) -> CGPoint {
            let h = view == "side" ? p.x - center.x : p.z - center.z
            return CGPoint(x: Double(width) / 2 + h * scale, y: Double(height) / 2 + (p.y - center.y) * scale)
        }
        guard let context = unsafe CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        func stroke(_ points: [SIMD3<Double>], radius: Double, color: CGColor) {
            guard let first = points.first else { return }
            context.setStrokeColor(color)
            context.setLineWidth(2 * radius * scale)
            context.move(to: project(first))
            for point in points.dropFirst() { context.addLine(to: project(point)) }
            context.strokePath()
        }
        let grey = CGColor(gray: 0.55, alpha: 0.9)
        for side in [1.0, -1.0] { stroke(pose.swordCenterline(side: side), radius: Dimensions.Sword.wireRadius, color: CGColor(gray: 0.3, alpha: 0.9)) }
        let colors = [CGColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 0.9), CGColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 0.9)]
        for number in stride(from: 9, through: 1, by: -1) {
            let color = number <= 2 ? colors[number - 1] : grey
            stroke(Relations.loop(pose.ring(number).circle, pieces: 120), radius: Dimensions.Ring.wireRadius, color: color)
            let rod = pose.rod(number)
            stroke(Relations.loop(rod.eye, pieces: 60), radius: Dimensions.Rod.wireRadius, color: color)
            stroke([rod.shaft.start, rod.shaft.end], radius: Dimensions.Rod.wireRadius, color: color)
        }
        if let mark {
            context.setStrokeColor(CGColor(red: 0, green: 0.7, blue: 0.2, alpha: 1))
            context.setLineWidth(3)
            let p = project(mark.pointA)
            context.strokeEllipse(in: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36))
        }
        // Flip so that y is up in the file, and write.
        guard let image = context.makeImage() else { return }
        _ = title
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
