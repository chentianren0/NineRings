import Foundation
import Geometry
import Motion
import Puzzle
import Testing
import Toy
import simd

// How far the checker's numbers can be trusted: its nearest-points search against brute force, its pruning
// bounds, and its step bound against the true movement of points of the parts.

/// A small repeatable generator, so that a bad case can be found again.
private struct ProbeRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { .random(in: 0...1, using: &self) }

    mutating func vector(within extent: Double) -> Vector {
        Vector(.random(in: -extent...extent, using: &self), .random(in: -extent...extent, using: &self), .random(in: -extent...extent, using: &self))
    }

    mutating func direction() -> Vector {
        while true {
            let candidate = vector(within: 1)
            let length = simd_length(candidate)
            if length > 0.1 && length <= 1 { return candidate / length }
        }
    }

    mutating func rotation() -> simd_quatd {
        simd_quatd(angle: .random(in: 0...(2 * .pi), using: &self), axis: direction())
    }
}

/// The kinds of shape the toy has, with their sizes.
private enum ProbeKind: String, CaseIterable {
    case ring, eye, tipPiece, longPiece, bar, bead

    var radius: Double {
        switch self {
        case .ring: Dimensions.Ring.wireRadius
        case .eye: Dimensions.Rod.wireRadius
        case .tipPiece, .longPiece: Dimensions.Sword.wireRadius
        case .bar: Dimensions.Bar.thickness / 2
        case .bead: Dimensions.Rod.beadRadius
        }
    }

    func core(_ random: inout ProbeRandom) -> ShapeCore {
        switch self {
        case .ring: .circle(Circle(center: .zero, normal: random.direction(), radius: Dimensions.Ring.radius))
        case .eye: .circle(Circle(center: .zero, normal: random.direction(), radius: Dimensions.Rod.eyeRadius))
        case .tipPiece:
            // The tip's pieces are short: a quarter circle of 9.4 mm in 48 pieces is about 0.3 mm each.
            .segment(Segment(start: .zero, end: random.direction() * Double.random(in: 0.2...4, using: &random)))
        case .longPiece:
            .segment(Segment(start: .zero, end: random.direction() * Double.random(in: 4...130, using: &random)))
        case .bar:
            {
                let length = random.direction()
                let width = simd_normalize(simd_cross(length, random.direction()))
                return .stadium(Stadium(center: .zero, lengthAxis: length, widthAxis: width, halfLength: Dimensions.Bar.length / 2 - Dimensions.Bar.width / 2, radius: Dimensions.Bar.width / 2))
            }()
        case .bead: .point(.zero)
        }
    }
}

private func probePoint(on core: ShapeCore, _ random: inout ProbeRandom) -> Vector {
    switch core {
    case .circle(let circle): return circle.point(at: random.unit())
    case .segment(let segment): return segment.point(at: random.unit())
    case .point(let point): return point
    case .stadium(let stadium):
        let along = Double.random(in: -stadium.halfLength...stadium.halfLength, using: &random)
        let across = Double.random(in: -stadium.radius...stadium.radius, using: &random)
        return stadium.center + along * stadium.lengthAxis + across * stadium.widthAxis
    }
}

private func probeMoved(_ core: ShapeCore, by offset: Vector) -> ShapeCore {
    switch core {
    case .circle(var circle): circle.center += offset; return .circle(circle)
    case .segment(let segment): return .segment(Segment(start: segment.start + offset, end: segment.end + offset))
    case .point(let point): return .point(point + offset)
    case .stadium(var stadium): stadium.center += offset; return .stadium(stadium)
    }
}

/// The checker's distance between two cores.
private func checkerDistance(_ a: ShapeCore, _ b: ShapeCore) -> Double {
    let (pointA, pointB) = Gaps.nearest(a, b)
    return simd_distance(pointA, pointB)
}

@Suite struct CheckerAccuracyProbes {
    /// Random pairs of each kind, placed so that they come near each other or cut into each other, as the
    /// checker meets them. The checker's distance is a distance between two real points, so it can only be too
    /// large; the error is how much larger than the brute-force distance it is.
    @Test func theNearestPointsSearchAgreesWithBruteForce() {
        var random = ProbeRandom(state: 11)
        let kinds = ProbeKind.allCases
        var cases: [(ProbeKind, ProbeKind, ShapeCore, ShapeCore)] = []
        for first in kinds {
            for second in kinds where !(first == .bar && second == .bar) {
                for _ in 0..<300 {
                    let a = probeMoved(first.core(&random), by: random.vector(within: 20))
                    var b = second.core(&random)
                    b = probeMoved(b, by: random.vector(within: 0.5))
                    let target = probePoint(on: a, &random) + random.direction() * Double.random(in: 0...(first.radius + second.radius + 3), using: &random)
                    b = probeMoved(b, by: target - probePoint(on: b, &random))
                    cases.append((first, second, a, b))
                }
            }
        }
        // Threaded: an eye's middle on or near a ring's wire, as ring k and eye k are, and a ring's wire through
        // the middle of an eye, the cases where the distance along a curve has close minima.
        for _ in 0..<1500 {
            let ring = Circle(center: random.vector(within: 5), normal: random.direction(), radius: Dimensions.Ring.radius)
            let eye = Circle(center: ring.point(at: random.unit()) + random.vector(within: 1.5), normal: random.direction(), radius: Dimensions.Rod.eyeRadius)
            cases.append((.eye, .ring, .circle(eye), .circle(ring)))
            cases.append((.ring, .eye, .circle(ring), .circle(eye)))
        }

        let measured = Sweep.inParallel(cases.count) { [cases] index in
            let (_, _, a, b) = cases[index]
            return (checkerDistance(a, b), ProbeBrute.distance(a, b, steps: 8000))
        }
        var worst: [String: (error: Double, distance: Double)] = [:]
        var largest = (error: -Double.infinity, label: "", distance: 0.0)
        var nearLargest = -Double.infinity
        for (index, (checker, brute)) in measured.enumerated() {
            let (first, second, _, _) = cases[index]
            let label = "\(first.rawValue) / \(second.rawValue)"
            let error = checker - brute
            if error > (worst[label]?.error ?? -.infinity) { worst[label] = (error, brute) }
            if error > largest.error { largest = (error, label, brute) }
            if brute - first.radius - second.radius < 3 { nearLargest = max(nearLargest, error) }
        }
        for (label, value) in worst.sorted(by: { $0.key < $1.key }) {
            print(String(format: "accuracy %@: largest error %.2e mm (at a centreline distance of %.3f mm)", label, value.error, value.distance))
        }
        print(String(format: "accuracy: %d pairs, largest error %.2e mm (%@, centreline distance %.3f mm); among pairs whose surfaces are within 3 mm, %.2e mm", cases.count, largest.error, largest.label, largest.distance, nearLargest))
        #expect(largest.error < 1e-6)
    }

    /// The same comparison on every near pair of ring 1's move, at 400 samples each way.
    @Test func theNearestPointsSearchAgreesWithBruteForceThroughRingOnesMove() throws {
        let motion = try #require(MoveMotion(ringOneOff))
        let poses = (0...400).map { motion.pose(at: Double($0) / 400) }
        let errors = Sweep.inParallel(poses.count) { [poses] index in
            let shapes = poses[index].shapes
            var largest = (error: 0.0, pair: "", gap: 0.0)
            var largestNear = 0.0
            var smallestGap = Double.infinity
            for (offset, first) in shapes.enumerated() {
                for second in shapes[(offset + 1)...] where !first.name.isJoined(to: second.name) {
                    if simd_distance(first.boundCenter, second.boundCenter) > first.boundRadius + second.boundRadius + 3 { continue }
                    let checker = checkerDistance(first.core, second.core)
                    let brute = ProbeBrute.distance(first.core, second.core, steps: 4000)
                    let gap = brute - first.radius - second.radius
                    smallestGap = min(smallestGap, gap)
                    if checker - brute > largest.error { largest = (checker - brute, "\(first.name) / \(second.name)", gap) }
                    if gap < 1 { largestNear = max(largestNear, checker - brute) }
                }
            }
            return (largest, largestNear, smallestGap)
        }
        let worst = errors.max { $0.0.error < $1.0.error }!
        let worstNear = errors.map(\.1).max()!
        let smallestGap = errors.map(\.2).min()!
        print(String(format: "accuracy through ring 1's move: largest error %.2e mm (%@ at a gap of %.3f mm); among pairs within 1 mm, %.2e mm; smallest true gap %.3f mm", worst.0.error, worst.0.pair, worst.0.gap, worstNear, smallestGap))
        #expect(worstNear < 1e-6)
        #expect(smallestGap >= smallestAllowedGap - 1e-6)
        withKnownIssue("A sample where the distance has zero slope but is still falling is taken for the minimum, and the true minimum just past it is never bracketed (see aFlatSampleHidesTheMinimumJustPastIt).") {
            #expect(worst.0.error < 1e-6)
        }
    }

    /// The search looks for a falling slope followed by a rising one between two samples. A sample can have zero
    /// slope without being a minimum: a ring's sample whose nearest point on a straight piece is that piece's end,
    /// with the piece running on along the ring's own direction, inside its curve. The distance still falls past
    /// that sample, as the ring curves in toward the piece, and turns up again within one sample. The search
    /// takes the flat sample for the minimum and never brackets the true one. Ring 1's samples lie on the sword's
    /// middle plane, where the tip's apex begins both tip pieces, whenever ring 1 is square to the sword.
    @Test func aFlatSampleHidesTheMinimumJustPastIt() {
        var worst = (error: 0.0, label: "")
        for (name, radius, samples) in [("ring", Dimensions.Ring.radius, 96), ("eye", Dimensions.Rod.eyeRadius, 96)] {
            let circle = Circle(center: Vector(3, -2, 1), axisU: simd_normalize(Vector(1, 1, 0)), axisV: simd_normalize(Vector(-1, 1, 0.3) - simd_dot(Vector(-1, 1, 0.3), simd_normalize(Vector(1, 1, 0))) * simd_normalize(Vector(1, 1, 0))), radius: radius)
            let parameter = 24.0 / Double(samples)
            let sample = circle.point(at: parameter)
            let inward = simd_normalize(circle.center - sample)
            let along = simd_normalize(circle.velocity(at: parameter))
            let spacing = 2 * Double.pi * radius / Double(samples)
            let lengths = [("tip piece", 0.3076)] + (1...20).map { ("piece \(String(format: "%.2f", spacing * Double($0) / 20)) mm long", spacing * Double($0) / 20) }
            for (pieceName, length) in lengths {
                let pieceRadius = Dimensions.Sword.wireRadius
                let wireRadius = name == "ring" ? Dimensions.Ring.wireRadius : Dimensions.Rod.wireRadius
                // The piece starts the smallest allowed gap from the wire at the flat sample.
                let start = sample + (wireRadius + pieceRadius + smallestAllowedGap) * inward
                let piece = Segment(start: start, end: start + length * along)
                let checker = checkerDistance(.circle(circle), .segment(piece)) - wireRadius - pieceRadius
                let truth = ProbeBrute.distance(.circle(circle), .segment(piece), steps: 40_000) - wireRadius - pieceRadius
                if pieceName == "tip piece" {
                    print(String(format: "flat sample: %@ and a tip piece: the checker sees a gap of %.4f mm, the true gap is %.4f mm", name, checker, truth))
                }
                if checker - truth > worst.error { worst = (checker - truth, "\(name) and a \(pieceName)") }
            }
        }
        print(String(format: "flat sample: the largest error is %.4f mm (%@)", worst.error, worst.label))
        withKnownIssue("A sample with zero slope that is not a minimum hides the true minimum within the next sample: by about 0.005 mm for ring 1 at the tip's apex, and up to about 0.01 mm for a ring and a straight piece that ends part way to the next sample.") {
            #expect(worst.error < 1e-6)
        }
    }

    /// `Gaps.smallest` skips a pair whose bounding spheres are further apart than the reach. Every pair it would
    /// skip must really be further apart than the reach.
    @Test func everyPairThePruningSkipsIsReallyOutOfReach() {
        var random = ProbeRandom(state: 12)
        let kinds = ProbeKind.allCases
        var cases: [(Shape, Shape)] = []
        for first in kinds {
            for second in kinds where !(first == .bar && second == .bar) {
                var found = 0
                while found < 200 {
                    let a = Shape(.ring(1), probeMoved(first.core(&random), by: random.vector(within: 5)), radius: first.radius)
                    let b = Shape(.ring(2), probeMoved(second.core(&random), by: random.vector(within: 100)), radius: second.radius)
                    let skipped = simd_distance(a.boundCenter, b.boundCenter) > a.boundRadius + b.boundRadius + 3
                    // Keep pairs that are skipped by a small margin, where a wrong bound would show.
                    if skipped && simd_distance(a.boundCenter, b.boundCenter) < a.boundRadius + b.boundRadius + 6 {
                        cases.append((a, b))
                        found += 1
                    }
                }
            }
        }
        let gaps = Sweep.inParallel(cases.count) { [cases] index in
            let (a, b) = cases[index]
            return ProbeBrute.distance(a.core, b.core, steps: 4000) - a.radius - b.radius
        }
        print(String(format: "pruning: %d skipped pairs, the nearest at %.3f mm", gaps.count, gaps.min() ?? .infinity))
        #expect(gaps.allSatisfy { $0 > 3 })
    }

    /// Points of each moving part, in its own frame, over its whole surface.
    private static let ringPoints: [Vector] = {
        var points: [Vector] = []
        for step in 0..<360 {
            let angle = 2 * Double.pi * Double(step) / 360
            let radial = Vector(cos(angle), sin(angle), 0)
            for around in 0..<8 {
                let turn = 2 * Double.pi * Double(around) / 8
                points.append(Dimensions.Ring.radius * radial + Dimensions.Ring.wireRadius * (cos(turn) * radial + sin(turn) * Vector(0, 0, 1)))
            }
        }
        return points
    }()

    private static let rodPoints: [Vector] = {
        typealias Rod = Dimensions.Rod
        var points: [Vector] = []
        for step in 0..<120 {
            let angle = 2 * Double.pi * Double(step) / 120
            let radial = Vector(cos(angle), sin(angle), 0)
            for around in 0..<8 {
                let turn = 2 * Double.pi * Double(around) / 8
                points.append(Rod.eyeRadius * radial + Rod.wireRadius * (cos(turn) * radial + sin(turn) * Vector(0, 0, 1)))
            }
        }
        for step in 0...60 {
            let y = Rod.shaftTopY + (Rod.beadCenterY - Rod.shaftTopY) * Double(step) / 60
            for around in 0..<8 {
                let turn = 2 * Double.pi * Double(around) / 8
                points.append(Vector(Rod.wireRadius * cos(turn), y, Rod.wireRadius * sin(turn)))
            }
        }
        // The bead's surface, by a spiral of evenly spread points.
        for index in 0..<400 {
            let z = 1 - 2 * (Double(index) + 0.5) / 400
            let angle = Double(index) * Double.pi * (3 - 5.0.squareRoot())
            let ring = (1 - z * z).squareRoot()
            points.append(Vector(0, Rod.beadCenterY, 0) + Rod.beadRadius * Vector(ring * cos(angle), z, ring * sin(angle)))
        }
        return points
    }()

    private static func movement(_ a: PartPose, _ b: PartPose, _ points: [Vector]) -> Double {
        points.reduce(0) { max($0, simd_distance(a.worldPoint($1), b.worldPoint($1))) }
    }

    /// `largestStep` must bound how far any point of any part moves, including the far end of a part that turns.
    @Test func theStepBoundsTheMovementOfEveryPoint() throws {
        var random = ProbeRandom(state: 13)
        var tightest = 0.0
        for trial in 0..<400 {
            let base = probeAllOn
            let start = PartPose(position: random.vector(within: 50), orientation: random.rotation())
            let angle = trial < 200 ? Double.random(in: 0...0.02, using: &random) : Double.random(in: 0...Double.pi, using: &random)
            let end = PartPose(position: start.position + random.vector(within: 0.2), orientation: simd_normalize(simd_quatd(angle: angle, axis: random.direction()) * start.orientation))
            for isRing in [true, false] {
                let a = isRing ? base.probeReplacing(ring: 1, with: start) : base.probeReplacing(rod: 1, with: start)
                let b = isRing ? base.probeReplacing(ring: 1, with: end) : base.probeReplacing(rod: 1, with: end)
                let bound = Relations.largestStep(from: a, to: b).distance
                let moved = Self.movement(start, end, isRing ? Self.ringPoints : Self.rodPoints)
                tightest = max(tightest, moved / bound)
                #expect(moved <= bound + 1e-9, "trial \(trial): a point moved \(moved) mm, the bound is \(bound) mm")
            }
        }

        // And through ring 1's move, sample by sample.
        let motion = try #require(MoveMotion(ringOneOff))
        let poses = (0...Sweep.samples).map { motion.pose(at: Double($0) / Double(Sweep.samples)) }
        var largestMoved = 0.0
        var exceeded = 0
        for (a, b) in zip(poses, poses.dropFirst()) {
            let moved = max(
                abs(a.swordSlide - b.swordSlide),
                Self.movement(a.ring(1), b.ring(1), Self.ringPoints),
                Self.movement(a.rod(1), b.rod(1), Self.rodPoints)
            )
            largestMoved = max(largestMoved, moved)
            if moved > Relations.largestStep(from: a, to: b).distance + 1e-12 { exceeded += 1 }
        }
        print(String(format: "step bound: at worst %.3f of the bound is reached by a sampled point; through ring 1's move the farthest a point moves in one step is %.4f mm", tightest, largestMoved))
        #expect(exceeded == 0)
    }

    /// Between two samples the parts are not checked. Ten times finer sampling of everything that moves in
    /// ring 1's move shows how much smaller the gap gets between the checked samples.
    @Test func theGapBetweenSamplesThroughRingOnesMove() throws {
        let motion = try #require(MoveMotion(ringOneOff))
        let moving: Set<PartName> = [.ring(1), .eye(1), .shaft(1), .bead(1), .sword]
        let fine = 40_000
        let gaps = Sweep.inParallel(fine + 1) { index in
            Gaps.smallest(in: motion.pose(at: Double(index) / Double(fine)).shapes.filter { $0.name != .bar }, involving: moving)?.distance ?? .infinity
        }
        let coarse = stride(from: 0, through: fine, by: 10).map { gaps[$0] }.min()!
        let finest = gaps.min()!
        let index = gaps.firstIndex(of: finest)!
        print(String(format: "between samples: smallest gap of the moving parts, leaving out the bar, %.4f mm at the 4000 checked samples, %.4f mm at 40000 (progress %.5f)", coarse, finest, Double(index) / Double(fine)))
        #expect(coarse - finest < 0.01)
        #expect(finest >= smallestAllowedGap)
    }
}
