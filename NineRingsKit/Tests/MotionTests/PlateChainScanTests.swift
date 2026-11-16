import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Scans a chain of hanging rings that hang like plates leaning on one another: every rod upright, the first
/// hanging ring as ring 1 hangs from ring 2, every deeper ring at one lean with its eye a set drop below the eye of
/// the ring it hangs from. In the step aside only the first hanging ring is lifted, drooping at its rest lean in
/// front of the ring that steps aside, and the deeper rings go straight up with it.
///
/// With every rod upright the bar's height changes nothing but the gaps to the bar, so each pose gives the range
/// of raises it allows. Run with `NINE_RINGS_PLATES=rest` or `NINE_RINGS_PLATES=aside`, optimized.
@Suite struct PlateChainScanTests {
    static let wanted = 0.3

    /// The chain below ring `carrier`, which is on, as rings by number.
    static func chain(below carrier: Int, lean: Double, drop: Double) -> [Int: HeldRing] {
        var held: [Int: HeldRing] = [:]
        guard carrier >= 2 else { return held }
        held[carrier - 1] = RestPoses.hanging(carrier - 1)
        var eyeHeight = Layout.eyeHeightHanging
        let angle = lean * .pi / 180
        for ring in stride(from: carrier - 2, through: 1, by: -1) {
            eyeHeight -= drop
            held[ring] = HeldRing(
                eye: SIMD3(Layout.hole(ring).x, eyeHeight, 0),
                towardCenter: SIMD3(-sin(angle), -cos(angle), 0),
                alongWire: SIMD3(0, 0, 1)
            )
        }
        return held
    }

    /// The shapes other than the bar, and the range of raises the bar can be held at with `wanted` to spare from
    /// everything above it and every bead below it.
    static func raiseRange(_ pose: ToyPose, beadsOf rods: Set<Int>) -> ClosedRange<Double>? {
        let shapes = pose.shapes
        func barGap(_ raise: Double, _ names: (PartName) -> Bool) -> Double {
            let bar = Shape(.bar, .stadium(Layout.bar(raisedBy: raise).stadium), radius: Dimensions.Bar.thickness / 2)
            var smallest = Double.infinity
            for shape in shapes where names(shape.name) {
                let (p, q) = Gaps.nearest(shape.core, bar.core)
                smallest = min(smallest, simd_distance(p, q) - shape.radius - bar.radius)
            }
            return smallest
        }
        let above: (PartName) -> Bool = { name in
            switch name { case .ring, .eye: return true; default: return false }
        }
        let beads: (PartName) -> Bool = { name in
            if case .bead(let rod) = name { return rods.contains(rod) }
            return false
        }
        // Beads only limit how low the bar may be, the rest how high: find each edge by halving.
        func edge(_ ok: (Double) -> Bool, low: Double, high: Double, rising: Bool) -> Double {
            var (low, high) = (low, high)
            for _ in 0..<30 {
                let middle = (low + high) / 2
                if ok(middle) == rising { high = middle } else { low = middle }
            }
            return rising ? high : low
        }
        guard barGap(0, above) >= wanted, barGap(60, beads) >= wanted else { return nil }
        let minimum = barGap(0, beads) >= wanted ? 0 : edge({ barGap($0, beads) >= wanted }, low: 0, high: 60, rising: true)
        let maximum = barGap(60, above) >= wanted ? 60 : edge({ barGap($0, above) >= wanted }, low: 0, high: 60, rising: false)
        return minimum <= maximum ? minimum...maximum : nil
    }

    /// The smallest gap among the shapes, leaving out the bar and pairs joined by design.
    static func room(_ pose: ToyPose, involving parts: Set<PartName>? = nil) -> (Double, String) {
        let shapes = pose.shapes.filter { $0.name != .bar }
        guard let gap = Gaps.smallest(in: shapes, involving: parts) else { return (10, "") }
        return (gap.distance, "\(gap.first) and \(gap.second)")
    }

    // MARK: Rest

    struct Rest { var lean: Double; var drop: Double; var room: Double; var why: String; var raises: ClosedRange<Double>? }

    static func rest(carrier: Int, lean: Double, drop: Double) -> Rest {
        let held = chain(below: carrier, lean: lean, drop: drop)
        let pose = StepAsideScanTests.pose(held, sword: Layout.swordHome, raise: 0)
        let failures = Relations.failures(in: pose, mayBeOff: Set(1..<carrier))
        if !failures.isEmpty { return Rest(lean: lean, drop: drop, room: -1, why: failures.joined(separator: ", "), raises: nil) }
        let (room, why) = room(pose)
        return Rest(lean: lean, drop: drop, room: room, why: why, raises: raiseRange(pose, beadsOf: Set(1...9)))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_PLATES"] == "rest"))
    func restPoses() {
        let clock = ContinuousClock()
        let started = clock.now
        var combos: [(Double, Double)] = []
        for lean in stride(from: 50.0, through: 80.0, by: 1) {
            for drop in stride(from: -2.0, through: 10.0, by: 0.25) { combos.append((lean, drop)) }
        }
        let all = combos
        for n in 3...9 {
            let carrier = n - 1
            let results = Sweep.inParallel(all.count) { Self.rest(carrier: carrier, lean: all[$0].0, drop: all[$0].1) }
            let good = results.filter { $0.room >= Self.wanted && $0.raises != nil }
            let best = good.max { $0.room < $1.room }
            let widest = good.max { ($0.raises!.upperBound) < ($1.raises!.upperBound) }
            func text(_ rest: Rest?) -> String {
                guard let rest else { return "none" }
                return String(format: "lean %.0f drop %.2f room %.3f (%@) raises %.2f...%.2f", rest.lean, rest.drop, rest.room, rest.why, rest.raises!.lowerBound, rest.raises!.upperBound)
            }
            print("ring \(n) rest, \(n - 2) hanging: \(good.count) of \(all.count) shapes; most room: \(text(best)); highest bar: \(text(widest))")
            if good.isEmpty, let nearest = results.max(by: { $0.room < $1.room }) {
                print(String(format: "   nearest: lean %.0f drop %.2f room %.3f ", nearest.lean, nearest.drop, nearest.room) + nearest.why)
            }
        }
        // One shape for every length of chain, every hanging rod out of the slot (no eye above the first's).
        let common = Sweep.inParallel(all.count) { index -> (Double, Double) in
            guard all[index].1 >= 0 else { return (-1, 0) }
            var room = Double.infinity, top = Double.infinity
            for n in 4...9 {
                let rest = Self.rest(carrier: n - 1, lean: all[index].0, drop: all[index].1)
                room = min(room, rest.room)
                top = min(top, rest.raises?.upperBound ?? -1)
            }
            return (room, top)
        }
        for lean in stride(from: 50.0, through: 80.0, by: 2) {
            let ok = common.indices.filter { all[$0].0 == lean && common[$0].0 >= Self.wanted && common[$0].1 > 0 }
            let text = ok.map { String(format: "%.2f:%.1f", all[$0].1, common[$0].1) }.prefix(8).joined(separator: " ")
            print(String(format: "every chain, lean %.0f (drop:bar up to): ", lean) + (text.isEmpty ? "none" : text))
        }
        print("rest scan took \(clock.now - started)")
    }

    // MARK: Step aside

    /// The pose of the step aside: the carrier turned, the first hanging ring's eye at `eyeHeight` and the deeper
    /// rings moved straight up with it, ring `n` at one point of its lift.
    static func aside(n: Int, carrier: HeldRing, eyeHeight: Double, lean: Double, drop: Double, step: StepAsideScanTests.Lift) -> ToyPose {
        var held = chain(below: n - 1, lean: lean, drop: drop)
        let rise = eyeHeight - Layout.eyeHeightHanging
        for (ring, ringHeld) in held {
            held[ring] = HeldRing(eye: ringHeld.eye + SIMD3(0, rise, 0), towardCenter: ringHeld.towardCenter, alongWire: ringHeld.alongWire)
        }
        held[n - 1] = carrier
        held[n] = StepAsideScanTests.lifting(n, tip: step.tip)
        return StepAsideScanTests.pose(held, sword: step.sword, raise: 0)
    }

    struct Aside { var room: Double; var why: String; var raises: ClosedRange<Double>? }

    static func aside(n: Int, lid: Double, tilt: Double, swing: Double, eyeHeight: Double, lean: Double, drop: Double) -> Aside {
        let carrier = StepAsideScanTests.turns(n - 1, lid: lid, tilt: tilt, swing: swing)
        // The side of the carrier's plane that the first hanging ring rests on, turned with the carrier.
        let restPose = RestPoses.on(n - 1).ringPose, now = carrier.ringPose
        let restNormal = restPose.worldDirection(SIMD3(0, 0, 1))
        let restSide = simd_dot(RestPoses.hanging(n - 2).ringPose.position - restPose.position, restNormal) > 0 ? restNormal : -restNormal
        let front = (now.orientation * restPose.orientation.inverse).act(restSide)
        let moving: Set<PartName> = Set((1..<n).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] })
        var worst = Aside(room: 10, why: "", raises: -100...100)
        let steps = StepAsideScanTests.lift(n)
        // The last step first: it is where the carrier and ring n are nearest, so most poses fail there quickly.
        for step in [steps[steps.count - 1]] + steps.dropLast() {
            let pose = aside(n: n, carrier: carrier, eyeHeight: eyeHeight, lean: lean, drop: drop, step: step)
            let firstCenter = pose.ring(n - 2).position
            if simd_dot(firstCenter - now.position, front) <= 0 { return Aside(room: -1, why: "first hanging ring behind the carrier", raises: nil) }
            // Upright rods always fit their holes; whether they reach through the bar is the bead's gap below it,
            // which the range of raises covers.
            let failures = StepAsideScanTests.failures(pose, n: n, rods: true).filter { !$0.hasSuffix("does not fit its hole") }
            if !failures.isEmpty { return Aside(room: -1, why: failures.joined(separator: ", "), raises: nil) }
            if Relations.isRoundTheRails(n - 1, in: pose) { return Aside(room: -1, why: "carrier on the rails", raises: nil) }
            let (room, why) = room(pose, involving: moving)
            if room < worst.room { (worst.room, worst.why) = (room, why) }
            if worst.room < wanted { return worst }
            guard let range = raiseRange(pose, beadsOf: Set(1..<n)), let current = worst.raises,
                  max(range.lowerBound, current.lowerBound) <= min(range.upperBound, current.upperBound)
            else { worst.raises = nil; return worst }
            worst.raises = max(range.lowerBound, current.lowerBound)...min(range.upperBound, current.upperBound)
        }
        return worst
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_PLATES"] == "aside"))
    func stepAside() {
        let env = ProcessInfo.processInfo.environment
        let lean = Double(env["NINE_RINGS_LEAN"] ?? "60") ?? 60
        let drop = Double(env["NINE_RINGS_DROP"] ?? "3") ?? 3
        let rings = (env["NINE_RINGS_RINGS"] ?? "3,4,5,6,7,8,9").split(separator: ",").compactMap { Int($0) }
        let clock = ContinuousClock()
        var combos: [(Double, Double, Double, Double)] = []
        for lid in stride(from: 80.0, through: 124.0, by: 4) {
            for tilt in stride(from: -20.0, through: 20.0, by: 10) {
                for swing in stride(from: -60.0, through: 60.0, by: 10) {
                    for eye in stride(from: 4.0, through: 22.0, by: 1) { combos.append((lid, tilt, swing, eye)) }
                }
            }
        }
        let all = combos
        for n in rings {
            let started = clock.now
            let results = Sweep.inParallel(all.count) { index in
                let (lid, tilt, swing, eye) = all[index]
                return Self.aside(n: n, lid: lid, tilt: tilt, swing: swing, eyeHeight: eye, lean: lean, drop: drop)
            }
            let good = results.indices.filter { results[$0].room >= Self.wanted && results[$0].raises != nil }
            let best = good.max { results[$0].room < results[$1].room }
            let lowest = good.min { results[$0].raises!.lowerBound < results[$1].raises!.lowerBound }
            func text(_ index: Int?) -> String {
                guard let index else { return "none" }
                let (lid, tilt, swing, eye) = all[index]
                let raises = results[index].raises!
                return String(format: "lid %.0f tilt %.0f swing %.0f eye %.0f: room %.3f (%@), raises %.2f...%.2f", lid, tilt, swing, eye, results[index].room, results[index].why, raises.lowerBound, raises.upperBound)
            }
            print("ring \(n) aside, \(n - 2) hanging: \(good.count) poses; most room: \(text(best)); lowest raise: \(text(lowest))")
            for raise in [9.0, 10, 11, 12, 13, 14, 15, 16, 18, 20, 24] {
                let fits = good.filter { results[$0].raises!.contains(raise) }
                if let top = fits.max(by: { results[$0].room < results[$1].room }) {
                    print(String(format: "   at raise %4.1f: %d poses, most room ", raise, fits.count) + text(top))
                }
            }
            var reasons: [String: Int] = [:]
            for result in results where result.room < Self.wanted || result.raises == nil {
                let key = result.room < 0 ? result.why : (result.room < Self.wanted ? "gap: " + result.why : "no raise fits")
                reasons[key, default: 0] += 1
            }
            for (reason, count) in reasons.sorted(by: { $0.value > $1.value }).prefix(8) { print("   \(count): \(reason)") }
            if good.isEmpty {
                let nearest = results.indices.max { results[$0].room < results[$1].room }!
                let (lid, tilt, swing, eye) = all[nearest]
                print(String(format: "   nearest: lid %.0f tilt %.0f swing %.0f eye %.0f room %.3f ", lid, tilt, swing, eye, results[nearest].room) + results[nearest].why)
            }
            print("   took \(clock.now - started)")
        }
    }
}
