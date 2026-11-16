import Foundation
import Geometry
import Motion
import Puzzle
import Testing
import Toy
import simd

// Probes of the checker itself. Each builds a pose or a run of poses with a fault put in on purpose, makes sure
// with a brute-force measure that the fault is real, and asserts that the checker reports it. Where the checker
// misses a fault, the probe says so inside `withKnownIssue`, so that the suite stays green and the gap stays in
// sight; if the checker is fixed, that probe fails until its `withKnownIssue` is taken away.

// MARK: - Brute force, independent of the checker's search

/// Measures written without the checker's sampling and root finding: walk a curve in many small steps, project
/// each point onto the other core, and polish every local minimum that comes near the best by golden section.
enum ProbeBrute {
    static func nearestPoint(of core: ShapeCore, to point: Vector) -> Vector {
        switch core {
        case .circle(let circle): circle.nearestPoint(to: point)
        case .segment(let segment): segment.nearestPoint(to: point)
        case .point(let other): other
        case .stadium(let stadium): stadium.nearestPoint(to: point)
        }
    }

    static func curve(_ core: ShapeCore) -> (any CurveCore)? {
        switch core {
        case .circle(let circle): circle
        case .segment(let segment): segment
        default: nil
        }
    }

    /// The smallest distance from points of `curve` to `other`.
    static func walk(_ curve: any CurveCore, onto other: ShapeCore, steps: Int) -> Double {
        func distance(_ parameter: Double) -> Double {
            let point = curve.point(at: parameter)
            return simd_distance(point, nearestPoint(of: other, to: point))
        }
        let values = (0...steps).map { distance(Double($0) / Double(steps)) }
        let bestSample = values.min() ?? .infinity
        var best = bestSample
        for index in 0...steps {
            let here = values[index]
            guard here <= bestSample + 0.05 else { continue }
            if index > 0 && values[index - 1] < here { continue }
            if index < steps && values[index + 1] < here { continue }
            var low = Double(index - 1) / Double(steps), high = Double(index + 1) / Double(steps)
            if !curve.isClosed { low = max(low, 0); high = min(high, 1) }
            let ratio = (5.0.squareRoot() - 1) / 2
            var a = high - ratio * (high - low), b = low + ratio * (high - low)
            var valueA = distance(a), valueB = distance(b)
            for _ in 0..<50 {
                if valueA < valueB {
                    high = b; b = a; valueB = valueA
                    a = high - ratio * (high - low); valueA = distance(a)
                } else {
                    low = a; a = b; valueA = valueB
                    b = low + ratio * (high - low); valueB = distance(b)
                }
            }
            best = min(best, valueA, valueB)
        }
        return best
    }

    /// The distance between two cores, walking each that is a curve and projecting onto the other.
    static func distance(_ a: ShapeCore, _ b: ShapeCore, steps: Int = 8000) -> Double {
        var best = Double.infinity
        if let curve = curve(a) { best = min(best, walk(curve, onto: b, steps: steps)) }
        if let curve = curve(b) { best = min(best, walk(curve, onto: a, steps: steps)) }
        if best == .infinity {
            // Neither is a curve: a point and a point, or a point and the bar.
            switch (a, b) {
            case (.point(let point), _): best = simd_distance(point, nearestPoint(of: b, to: point))
            case (_, .point(let point)): best = simd_distance(point, nearestPoint(of: a, to: point))
            default: preconditionFailure("the toy has one bar")
            }
        }
        return best
    }

    /// The smallest gap between the surfaces of two parts of a pose.
    static func gap(_ first: PartName, _ second: PartName, in pose: ToyPose, steps: Int = 8000) -> Double {
        let shapes = pose.shapes
        var best = Double.infinity
        for a in shapes where a.name == first {
            for b in shapes where b.name == second {
                best = min(best, distance(a.core, b.core, steps: steps) - a.radius - b.radius)
            }
        }
        return best
    }

    /// How much room a rod's shaft has in its hole: the least distance from the shaft's axis to the bar's
    /// material round the hole (a slab one thickness deep, with a round hole through it), less the shaft's
    /// radius. Negative where the shaft would cut into the bar.
    static func holeClearance(_ rod: PartPose, hole number: Int, bar: PartPose) -> Double {
        typealias Bar = Dimensions.Bar
        let shaft = rod.shaft
        let hole = bar.worldPoint(SIMD3(Bar.holeX(number), 0, 0))
        let up = bar.worldDirection(SIMD3(0, 1, 0))
        let startHeight = simd_dot(shaft.start - hole, up)
        let endHeight = simd_dot(shaft.end - hole, up)
        guard startHeight > 0, endHeight < 0 else { return -.infinity }
        let crossing = startHeight / (startHeight - endHeight)
        let length = simd_distance(shaft.start, shaft.end)
        var least = Double.infinity
        let half = 5.0 / length
        let steps = 10_000
        for index in 0...steps {
            let parameter = crossing - half + 2 * half * Double(index) / Double(steps)
            guard parameter >= 0, parameter <= 1 else { continue }
            let point = shaft.point(at: parameter)
            let height = simd_dot(point - hole, up)
            let radial = simd_length((point - hole) - height * up)
            let distance: Double
            if abs(height) <= Bar.thickness / 2 {
                distance = radial >= Bar.holeRadius
                    ? -min(radial - Bar.holeRadius, Bar.thickness / 2 - abs(height))
                    : Bar.holeRadius - radial
            } else {
                let above = abs(height) - Bar.thickness / 2
                let inward = max(0, Bar.holeRadius - radial)
                distance = (above * above + inward * inward).squareRoot()
            }
            least = min(least, distance)
        }
        return least - Dimensions.Rod.wireRadius
    }
}

// MARK: - Building faulty poses

let probeAllOn = RestPoses.pose(for: .allOn)!
let probeRingOneOff = RestPoses.pose(for: PuzzleState.allOn.moving(1))!

extension ToyPose {
    func probeHolding(_ number: Int, _ held: HeldRing) -> ToyPose {
        var pose = self
        pose.rings[number - 1] = held.ringPose
        pose.rods[number - 1] = held.rodPose(hole: Layout.hole(number))
        return pose
    }

    func probeReplacing(ring number: Int, with part: PartPose) -> ToyPose {
        var pose = self
        pose.rings[number - 1] = part
        return pose
    }

    func probeReplacing(rod number: Int, with part: PartPose) -> ToyPose {
        var pose = self
        pose.rods[number - 1] = part
        return pose
    }
}

func probeOrientation(_ x: Vector, _ y: Vector, _ z: Vector) -> simd_quatd {
    simd_normalize(simd_quatd(simd_double3x3(columns: (x, y, z))))
}

/// A ring lying flat, its plane level.
let probeFlat = probeOrientation(Vector(1, 0, 0), Vector(0, 0, -1), Vector(0, 1, 0))
/// A ring standing across the sword, its plane at right angles to the sword's length.
let probeAcross = probeOrientation(Vector(0, 1, 0), Vector(0, 0, 1), Vector(1, 0, 0))
/// A ring standing along the sword.
let probeAlong = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)

/// A rod turned about a world axis through its eye.
func probeTurned(_ rod: PartPose, by angle: Double, about axis: Vector) -> PartPose {
    PartPose(position: rod.position, orientation: simd_normalize(simd_quatd(angle: angle, axis: simd_normalize(axis)) * rod.orientation))
}

/// What the checker says about one pose: the smallest gap of all, the smallest gap between two named parts,
/// and the relations that fail.
struct ProbeVerdict: CustomStringConvertible {
    let smallest: Gap?
    let pairGap: Double
    let relations: [String]

    init(_ pose: ToyPose, _ first: PartName, _ second: PartName) {
        smallest = Gaps.smallest(in: pose.shapes)
        pairGap = Gaps.smallest(in: pose.shapes.filter { $0.name == first || $0.name == second }, reach: .infinity)?.distance ?? .infinity
        relations = Relations.failures(in: pose)
    }

    var gapCaught: Bool { (smallest?.distance ?? .infinity) < smallestAllowedGap }
    var pairCaught: Bool { pairGap < smallestAllowedGap }

    var description: String {
        "smallest gap \(smallest.map(\.description) ?? "none"); checker's gap for the pair \(String(format: "%.3f", pairGap)); relations: \(relations.isEmpty ? "none" : relations.joined(separator: "; "))"
    }
}

let probeRailHeight = Dimensions.Sword.railHeight
let probeBarTop = Layout.bar.position.y + Dimensions.Bar.thickness / 2

// MARK: - Faults the gap rule must catch

@Suite struct CheckerGapProbes {
    /// Checks one probe: the fault is real by brute force, and the checker's gap for the pair is below the rule.
    private func expectCaught(_ name: String, _ pose: ToyPose, _ first: PartName, _ second: PartName) {
        let truth = ProbeBrute.gap(first, second, in: pose)
        let verdict = ProbeVerdict(pose, first, second)
        print("probe \(name): true gap \(String(format: "%.3f", truth)) between \(first) and \(second); \(verdict)")
        #expect(truth < 0, "the probe \(name) does not build the fault it means to")
        #expect(verdict.pairCaught, "\(name): \(verdict)")
        #expect(verdict.gapCaught, "\(name): \(verdict)")
        #expect(abs(verdict.pairGap - truth) < 1e-3, "\(name): the checker's gap \(verdict.pairGap) is not the true gap \(truth)")
    }

    @Test func aRingPushedIntoARail() {
        // Ring 5 and its rod, slid sideways until the ring's wire is well into the far rail.
        let rest = RestPoses.on(5)
        var shift = 0.0
        var pose = probeAllOn
        while ProbeBrute.gap(.ring(5), .sword, in: pose, steps: 2000) > -0.3 && shift < 12 {
            shift += 0.05
            pose = probeAllOn.probeHolding(5, HeldRing(eye: rest.eye + Vector(0, 0, shift), towardCenter: rest.towardCenter, alongWire: rest.alongWire))
        }
        print("probe ring into rail: ring 5 slid \(shift) mm across")
        expectCaught("ring into rail", pose, .ring(5), .sword)
    }

    @Test func aRingsWireThroughAnotherRingsWire() throws {
        // Ring 1 placed so that its wire crosses ring 3's wire at ring 3's lowest point, at right angles.
        let ring = probeAllOn.ring(3).circle
        let down = Vector(0, -1, 0)
        let inPlane = down - simd_dot(down, ring.normal) * ring.normal
        let outward = simd_normalize(inPlane)
        let lowest = ring.center + ring.radius * outward
        let part = PartPose(position: lowest + ring.radius * outward, orientation: probeOrientation(-outward, ring.normal, simd_cross(-outward, ring.normal)))
        expectCaught("ring through ring", probeAllOn.probeReplacing(ring: 1, with: part), .ring(1), .ring(3))
    }

    @Test func aShaftThroughARingsWire() {
        // Ring 1 standing along the sword, its wire through the middle of shaft 5.
        let shaftX = Layout.hole(5).x
        let part = PartPose(position: Vector(shaftX + Dimensions.Ring.radius, -30, 0), orientation: probeAlong)
        expectCaught("shaft through ring", probeAllOn.probeReplacing(ring: 1, with: part), .ring(1), .shaft(5))
    }

    @Test func anEyeIntoARail() {
        // Eye 1 moved onto the near rail, which then runs through the eye's middle and across its wire twice.
        let part = PartPose(position: Vector(39.5, probeRailHeight, Dimensions.Sword.railOffset), orientation: probeAlong)
        expectCaught("eye into rail", probeAllOn.probeReplacing(rod: 1, with: part), .eye(1), .sword)
    }

    @Test func aBeadIntoAnotherBead() {
        // Rod 4 swung about its eye so that its bead moves 6.5 mm toward bead 5, which is 5 mm away.
        let rod = probeAllOn.rod(4)
        let angle = asin(6.5 / -Dimensions.Rod.beadCenterY)
        expectCaught("bead into bead", probeAllOn.probeReplacing(rod: 4, with: probeTurned(rod, by: angle, about: Vector(0, 0, 1))), .bead(4), .bead(5))
    }

    @Test func aRingIntoTheBar() {
        // Ring 1 lying flat over the bar's end, its wire 0.4 mm into the bar.
        let part = PartPose(position: Vector(5, probeBarTop + Dimensions.Ring.wireRadius - 0.4, 0), orientation: probeFlat)
        expectCaught("ring into bar", probeAllOn.probeReplacing(ring: 1, with: part), .ring(1), .bar)
    }

    @Test func aBeadUpIntoTheBar() {
        // Ring 4 and its rod lifted half a millimetre more than the bar is raised, so the bead, which hangs that much
        // and a quarter millimetre under the bar, goes into it.
        let rest = RestPoses.on(4)
        let held = HeldRing(eye: rest.eye + Vector(0, Layout.barRaise + 0.5, 0), towardCenter: rest.towardCenter, alongWire: rest.alongWire)
        expectCaught("bead into bar", probeAllOn.probeHolding(4, held), .bead(4), .bar)
    }

    @Test func aRingAcrossTheNeck() {
        // Ring 1 standing along the sword round the neck, so that its wire cuts both wires of the neck.
        let part = PartPose(position: Vector(190, probeRailHeight, 0), orientation: probeAlong)
        expectCaught("ring across neck", probeAllOn.probeReplacing(ring: 1, with: part), .ring(1), .sword)
    }

    @Test func aRingAcrossTheShoulder() {
        // Ring 1 standing across the sword, its wire through the middle of the near rail's shoulder piece.
        let shoulder = Vector((Dimensions.Sword.railEndX + Dimensions.Sword.shoulderX) / 2, probeRailHeight, (Dimensions.Sword.railOffset + Dimensions.Sword.wireRadius) / 2)
        let part = PartPose(position: shoulder + Vector(0, Dimensions.Ring.radius, 0), orientation: probeAcross)
        expectCaught("ring across shoulder", probeAllOn.probeReplacing(ring: 1, with: part), .ring(1), .sword)
    }

    @Test func aRingOverTheTipsRise() {
        // Ring 1 standing across the sword where the tip rises, its wire through the near side of the tip.
        let x = 4.0
        let angle = acos(1 - x / Dimensions.Sword.railOffset)
        let onTip = Vector(x, Dimensions.Sword.height(atX: x), Dimensions.Sword.railOffset * sin(angle))
        let part = PartPose(position: onTip + Vector(0, Dimensions.Ring.radius, 0), orientation: probeAcross)
        expectCaught("ring over tip", probeAllOn.probeReplacing(ring: 1, with: part), .ring(1), .sword)
    }
}

// MARK: - Faults the relations must catch

@Suite struct CheckerRelationProbes {
    private func expectReported(_ name: String, _ pose: ToyPose, _ sentence: String) {
        let failures = Relations.failures(in: pose)
        print("probe \(name): relations: \(failures.joined(separator: "; "))")
        #expect(failures.contains(sentence), "\(name): expected \"\(sentence)\" among \(failures)")
    }

    @Test func aRodPulledOutOfTheRingItMustPassThrough() {
        // Ring 5 and its rod lifted 30 mm, so that ring 5's lower arc is above the top of rod 4's eye.
        let rest = RestPoses.on(5)
        let held = HeldRing(eye: rest.eye + Vector(0, 30, 0), towardCenter: rest.towardCenter, alongWire: rest.alongWire)
        expectReported("rod out of ring", probeAllOn.probeHolding(5, held), "rod 4 has come out of ring 5")
    }

    @Test func aRodThroughARingItMustNotPassThrough() {
        // Ring 1 lying flat round shaft 5.
        let part = PartPose(position: Vector(Layout.hole(5).x, -30, 0), orientation: probeFlat)
        expectReported("rod through wrong ring", probeAllOn.probeReplacing(ring: 1, with: part), "rod 5 passes through ring 1")
    }

    @Test func twoRingsLinked() {
        // Ring 1 centred on ring 3's lowest point and passing through ring 3's middle: linked, wires 12.85 mm apart.
        let ring = probeAllOn.ring(3).circle
        let down = Vector(0, -1, 0)
        let outward = simd_normalize(down - simd_dot(down, ring.normal) * ring.normal)
        let lowest = ring.center + ring.radius * outward
        let part = PartPose(position: lowest, orientation: probeOrientation(-outward, ring.normal, simd_cross(-outward, ring.normal)))
        let pose = probeAllOn.probeReplacing(ring: 1, with: part)
        #expect(ProbeBrute.gap(.ring(1), .ring(3), in: pose) > 10)
        expectReported("rings linked", pose, "rings 1 and 3 are linked")
    }

    @Test func aRingRoundOneRailOnly() {
        let part = PartPose(position: Vector(39.5, probeRailHeight, Dimensions.Sword.railOffset), orientation: probeAcross)
        expectReported("ring round one rail", probeAllOn.probeReplacing(ring: 1, with: part), "ring 1 goes round one rail of the sword but not the other")
    }

    @Test func aRingOffTheRails() {
        let rest = RestPoses.on(5)
        let held = HeldRing(eye: rest.eye + Vector(0, 30, 0), towardCenter: rest.towardCenter, alongWire: rest.alongWire)
        expectReported("ring off the rails", probeAllOn.probeHolding(5, held), "ring 5 has left the rails")
    }

    @Test func aBeadAboveTheBar() {
        // Ring 4 and its rod lifted 12 mm more than the bar is raised: the whole bead is above the bar and the shaft
        // no longer reaches it.
        let rest = RestPoses.on(4)
        let held = HeldRing(eye: rest.eye + Vector(0, Layout.barRaise + 12, 0), towardCenter: rest.towardCenter, alongWire: rest.alongWire)
        let pose = probeAllOn.probeHolding(4, held)
        expectReported("bead above bar", pose, "bead 4 is not below the bar")
        expectReported("bead above bar", pose, "rod 4 does not reach through the bar")
    }

    @Test func anEyeOffItsRingsWire() {
        let rod = probeAllOn.rod(3)
        let moved = PartPose(position: rod.position + Vector(0.5, 0, 0), orientation: rod.orientation)
        expectReported("eye off wire", probeAllOn.probeReplacing(rod: 3, with: moved), "eye 3 is off its ring's wire")
    }

    @Test func aRingsWireCuttingThroughItsOwnEye() {
        // Rod 3 turned 80° about its own length: the ring's wire, still through the eye's middle, now lies nearly in
        // the eye's plane and runs through the eye's wire. The gap rule excuses a ring and its own eye.
        let rod = probeAllOn.rod(3)
        let turned = probeTurned(rod, by: 80 * Double.pi / 180, about: rod.worldDirection(SIMD3(0, 1, 0)))
        let pose = probeAllOn.probeReplacing(rod: 3, with: turned)
        #expect(ProbeBrute.gap(.ring(3), .eye(3), in: pose) < 0)
        expectReported("wire cuts own eye", pose, "ring 3's wire cuts through its eye")
    }

    @Test func aShaftThroughTheBarAwayFromItsHole() {
        // Rod 4 swung 3.5° about its eye, so its shaft meets the bar about 3.3 mm from the middle of its hole. The
        // gap rule excuses every shaft and the bar.
        let rod = probeAllOn.rod(4)
        let pose = probeAllOn.probeReplacing(rod: 4, with: probeTurned(rod, by: 3.5 * Double.pi / 180, about: Vector(0, 0, 1)))
        let verdict = ProbeVerdict(pose, .shaft(4), .bar)
        print("probe shaft through bar: \(verdict)")
        #expect(ProbeBrute.holeClearance(pose.rod(4), hole: 4, bar: pose.bar) < -0.5)
        expectReported("shaft through bar", pose, "rod 4 does not fit through its hole")
    }

    /// A tilted shaft's section in the bar is an ellipse wider than the shaft, so it can cut into the wall or the
    /// rims of its hole with its axis through the hole's middle. The rod rule measures the shaft's true room in its
    /// hole, which must agree with brute force, so the largest tilt it lets through is the largest at which the
    /// shaft really fits.
    @Test func aTiltedShaftCutsIntoTheWallOfItsHole() {
        let rest = probeAllOn.rod(4)
        let hole = Layout.hole(4)
        let reach = simd_distance(rest.position, hole)
        func tilted(_ degrees: Double) -> PartPose {
            let turned = probeTurned(rest, by: degrees * Double.pi / 180, about: Vector(0, 0, 1))
            return PartPose(position: hole + reach * turned.worldDirection(SIMD3(0, 1, 0)), orientation: turned.orientation)
        }
        let pose = probeAllOn.probeReplacing(rod: 4, with: tilted(45))
        let clearance = ProbeBrute.holeClearance(tilted(45), hole: 4, bar: pose.bar)
        let holeFailures = Relations.failures(in: pose).filter { $0.hasPrefix("rod 4 does not") }

        // The largest tilt at which the shaft really fits, and the largest the rod rule lets through.
        let tilts = Array(stride(from: 0.0, through: 60, by: 0.1))
        let fits = tilts.last { ProbeBrute.holeClearance(tilted($0), hole: 4, bar: Layout.bar) >= 0 } ?? 0
        let allowed = tilts.last { Relations.failures(in: probeAllOn.probeReplacing(rod: 4, with: tilted($0))).allSatisfy { !$0.hasPrefix("rod 4 does not") } } ?? 0
        var largestDisagreement = 0.0
        for degrees in stride(from: 0.0, through: 50, by: 2.5) {
            let room = Relations.holeRoom(4, in: probeAllOn.probeReplacing(rod: 4, with: tilted(degrees))) ?? -.infinity
            largestDisagreement = max(largestDisagreement, abs(room - ProbeBrute.holeClearance(tilted(degrees), hole: 4, bar: Layout.bar)))
        }
        print("probe tilted shaft: at 45° the shaft cuts \(String(format: "%.3f", -clearance)) mm into its hole's wall; it fits up to \(String(format: "%.1f", fits))°, the rod rule allows up to \(String(format: "%.1f", allowed))°; the rule's room and brute force differ by at most \(String(format: "%.1e", largestDisagreement)) mm")
        #expect(clearance < 0)
        #expect(!holeFailures.isEmpty)
        #expect(abs(allowed - fits) < 0.15, "the scan steps by 0.1°")
        #expect(largestDisagreement < 1e-4)
    }

    /// The rod rule through ring 1's move: rod 1 tilts as ring 1 goes down, and must still fit its hole.
    @Test func rodOneFitsItsHoleThroughRingOnesMove() throws {
        let motion = try #require(MoveMotion(ringOneOff))
        var least = (clearance: Double.infinity, progress: 0.0, tilt: 0.0)
        var steepest = 0.0
        for index in 0...4000 {
            let progress = Double(index) / 4000
            let pose = motion.pose(at: progress)
            let rod = pose.rod(1)
            let tilt = acos(min(1, simd_dot(rod.worldDirection(SIMD3(0, 1, 0)), Vector(0, 1, 0)))) * 180 / .pi
            steepest = max(steepest, tilt)
            let clearance = ProbeBrute.holeClearance(rod, hole: 1, bar: pose.bar)
            if clearance < least.clearance { least = (clearance, progress, tilt) }
        }
        print("probe rod 1 in its hole: least room \(String(format: "%.3f", least.clearance)) mm at progress \(least.progress), tilted \(String(format: "%.1f", least.tilt))°; steepest tilt \(String(format: "%.1f", steepest))°")
        #expect(least.clearance >= 0)
    }
}

// MARK: - Faults between samples

@Suite struct CheckerStepProbes {
    @Test func aJumpOfOneMillimetreAtOneSampleIsCaught() throws {
        let motion = try #require(MoveMotion(ringOneOff))
        var poses = (0...Sweep.samples).map { motion.pose(at: Double($0) / Double(Sweep.samples)) }
        let jump = Vector(0, 0, 1)
        poses[2000].rings[0].position += jump
        poses[2000].rods[0].position += jump
        let steps = zip(poses, poses.dropFirst()).map { Relations.largestStep(from: $0, to: $1) }
        let largest = steps.map(\.distance).max() ?? 0
        print("probe jump: largest step \(String(format: "%.3f", largest)) mm")
        #expect(largest > largestAllowedStep)
    }

    /// Ring 1 lying flat at the bar's end, moved up through the bar in one step: clear of it at both samples by
    /// 0.3 mm, but through it in between. Only the step rule catches this; nothing about the bar is a relation.
    @Test func aRingThroughTheBarBetweenTwoSamplesIsCaughtByTheStepRule() {
        let clearCentre = Dimensions.Bar.thickness / 2 + Dimensions.Ring.wireRadius + 0.3
        func pose(_ height: Double) -> ToyPose {
            probeAllOn.probeReplacing(ring: 1, with: PartPose(position: Vector(5, Layout.bar.position.y + height, 0), orientation: probeFlat))
        }
        let below = pose(-clearCentre), middle = pose(0), above = pose(clearCentre)
        let gaps = [below, above].map { ProbeVerdict($0, .ring(1), .bar).pairGap }
        let step = Relations.largestStep(from: below, to: above).distance
        print("probe through bar between samples: gaps \(gaps), true gap half way \(ProbeBrute.gap(.ring(1), .bar, in: middle)), step \(step)")
        #expect(gaps.allSatisfy { $0 >= smallestAllowedGap })
        #expect(ProbeBrute.gap(.ring(1), .bar, in: middle) < 0)
        #expect(step > largestAllowedStep)
    }

    /// Rod 1 swung across the near rail about its eye, clear of the rail at both samples: the step rule catches it
    /// by the far end of the rod.
    @Test func aRodSwungThroughARailBetweenTwoSamplesIsCaughtByTheStepRule() {
        let rod = probeAllOn.rod(1)
        func pose(_ degrees: Double) -> ToyPose {
            probeAllOn.probeReplacing(rod: 1, with: probeTurned(rod, by: degrees * Double.pi / 180, about: Vector(1, 0, 0)))
        }
        let before = pose(-42), after = pose(-64.5), middle = pose(-53.2)
        let gaps = [before, after].map { ProbeVerdict($0, .shaft(1), .sword).pairGap }
        let step = Relations.largestStep(from: before, to: after)
        print("probe rod through rail between samples: gaps \(gaps), true gap half way \(ProbeBrute.gap(.shaft(1), .sword, in: middle)), step \(step)")
        #expect(gaps.allSatisfy { $0 >= smallestAllowedGap })
        #expect(ProbeBrute.gap(.shaft(1), .sword, in: middle) < 0)
        #expect(step.distance > largestAllowedStep)
    }

    /// The sword's centreline runs on past the end of the neck round the grip loops, whose ends lie against the
    /// wire. A ring round the neck that slides off its end runs into a grip loop, and the gap rule must catch it
    /// there, before the ring's going round the rails changes anywhere.
    @Test func aRingSlidingOffTheEndOfTheNeckRunsIntoTheGrip() {
        var caught: Double?
        var railFault: Double?
        var smallest = Double.infinity
        var previous: ToyPose?
        for index in 0...500 {
            let x = 200 + Double(index) * 0.1
            let pose = probeAllOn.probeReplacing(ring: 1, with: PartPose(position: Vector(x, probeRailHeight, 0), orientation: probeAcross))
            let gap = ProbeVerdict(pose, .ring(1), .sword).pairGap
            smallest = min(smallest, gap)
            if caught == nil && gap < smallestAllowedGap { caught = x }
            let failures = Relations.failures(in: pose).filter { $0.contains("rail") }
                + (previous.map { Relations.railChangeFailures(from: $0, to: pose) } ?? [])
            if railFault == nil && !failures.isEmpty { railFault = x }
            previous = pose
        }
        print("probe off the neck's end: the gap rule catches ring 1 at x = \(caught.map { String(format: "%.1f", $0) } ?? "never"), a sword relation fails at x = \(railFault.map { String(format: "%.1f", $0) } ?? "never"), smallest gap to the sword \(String(format: "%.3f", smallest))")
        #expect(smallest < 0)
        // Caught before the ring could reach the end of either grip loop.
        #expect(caught.map { $0 < SwordShape.centerline(side: 1).last!.x - Dimensions.Ring.wireRadius } == true)
        #expect(railFault.map { $0 > caught ?? .infinity } ?? true)
    }
}
