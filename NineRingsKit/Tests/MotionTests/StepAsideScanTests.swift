import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// Scans where the ring in front of ring `n` could step aside to, carrying the chain of rings that hang from it,
/// while ring `n` lifts over the tip; and how high the bar must be held for the rods of the chain to follow.
///
/// Run with `NINE_RINGS_STEP_ASIDE=3` (or 4, or 5), optimized. `NINE_RINGS_CHAIN=droop` hangs each ring of the
/// chain at a hanging ring's own lean rather than repeating ring 1's relation to ring 2 down the chain.
@Suite struct StepAsideScanTests {
    /// The raises tried, in millimetres.
    static let raises: [Double] = ProcessInfo.processInfo.environment["NINE_RINGS_RAISES"].map {
        $0.split(separator: ",").compactMap { Double($0) }
    } ?? [0, 2, 4, 6, 8, 10, 13, 16, 20, 24]
    static let wanted = 0.3

    static func turns(_ ring: Int, lid: Double, tilt: Double, swing: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: lid * .pi / 180), turn: Curve(constant: 0), tip: Curve(constant: 0),
            tilt: Curve(constant: tilt * .pi / 180), swing: Curve(constant: swing * .pi / 180),
            eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(ring, at: 0)
    }

    /// Ring `n` tipped toward the tip, as ring 3 lifts in its move.
    static func lifting(_ n: Int, tip: Double) -> HeldRing {
        RingTurns(
            lid: Curve(constant: .pi), turn: Curve(constant: .pi / 2), tip: Curve(constant: tip * .pi / 180),
            tilt: Curve(constant: .pi / 2), swing: Curve(constant: 0), eyeHeight: Curve(constant: Layout.eyeHeightOn)
        ).held(n, at: 0)
    }

    /// The rings hanging from ring `carrier` (on) at rest, the next lower ring first.
    static func chainAtRest(below carrier: Int, droop: Bool) -> [HeldRing] {
        var chain: [HeldRing] = []
        var above = RestPoses.on(carrier)
        for ring in stride(from: carrier - 1, through: 1, by: -1) {
            // Ring `ring` hangs from `above` as ring 1 hangs from ring 2 when ring 2 is on.
            let relation = HangingChain(carrierAtRest: RestPoses.on(ring + 1), chainAtRest: [RestPoses.hanging(ring)])
            var held = relation.chain(carriedBy: above)[0]
            if droop {
                // The same eye, but the ring at a hanging ring's own lean.
                let rest = RestPoses.hanging(ring)
                held = HeldRing(eye: held.eye, towardCenter: rest.towardCenter, alongWire: rest.alongWire)
            }
            chain.append(held)
            above = held
        }
        return chain
    }

    static func pose(_ held: [Int: HeldRing], sword: Double, raise: Double) -> ToyPose {
        let rings = PuzzleState.rings.map { held[$0] ?? RestPoses.on($0) }
        return RestPoses.pose(holding: rings, swordSlide: sword, barRaise: raise)
    }

    /// The relations that must hold among rings 1 to `n` and their rods, as one sentence each when they fail.
    static func failures(_ pose: ToyPose, n: Int, rods: Bool) -> [String] {
        var failures: [String] = []
        let circles = (1...9).map { pose.ring($0).circle }
        for ring in 1...min(n + 1, 9) {
            let (near, far) = Relations.swordCrossings(of: ring, in: pose)
            if near.count % 2 != far.count % 2 { failures.append("ring \(ring) on one rail") }
            for other in (ring + 1)..<10 where ring <= n && Relations.areLinked(circles[ring - 1], circles[other - 1]) {
                failures.append("rings \(ring) and \(other) linked")
            }
        }
        guard rods else { return failures }
        for rod in 1..<n {
            let thread = Relations.threadPath(of: pose.rod(rod))
            for ring in 1...min(n + 1, 9) where ring != rod {
                let through = Relations.crossings(of: thread, through: circles[ring - 1]).count % 2 == 1
                if through != (ring == rod + 1) { failures.append("rod \(rod) and ring \(ring)") }
            }
            for ring in 1...min(n + 1, 9) where ring != rod && Relations.areLinked(pose.rod(rod).eye, circles[ring - 1]) {
                failures.append("eye \(rod) linked with ring \(ring)")
            }
            if (Relations.holeRoom(rod, in: pose) ?? -1) < 0 { failures.append("rod \(rod) does not fit its hole") }
        }
        // Rod n-1 through ring n is the relation the lift keeps.
        if Relations.crossings(of: Relations.threadPath(of: pose.rod(n - 1)), through: circles[n - 1]).count % 2 != 1 {
            failures.append("rod \(n - 1) out of ring \(n)")
        }
        return failures
    }

    /// The smallest gap between a shape in `first` and any other shape not joined to it.
    static func gap(_ shapes: [Shape], _ first: Set<PartName>) -> (Double, String) {
        var smallest = (Double.infinity, "")
        for (index, a) in shapes.enumerated() {
            for b in shapes[(index + 1)...] where (first.contains(a.name) || first.contains(b.name)) && !a.name.isJoined(to: b.name) {
                if simd_distance(a.boundCenter, b.boundCenter) > a.boundRadius + b.boundRadius + 1 { continue }
                let (p, q) = Gaps.nearest(a.core, b.core)
                let distance = simd_distance(p, q) - a.radius - b.radius
                if distance < smallest.0 { smallest = (distance, "\(a.name) and \(b.name)") }
            }
        }
        return smallest
    }

    struct Lift { var tip: Double; var sword: Double }

    static func lift(_ n: Int) -> [Lift] {
        let shift = 15 * Double(n - 3)
        return stride(from: 137.0, through: 100, by: -2).map { Lift(tip: $0, sword: shift + 40 + min(1, (137 - $0) / 36) * 2.4) }
            + [Lift(tip: 100, sword: shift + 42.4)]
    }

    /// For one pose of the carrier: the room left without the rods, and for each raise the room with them.
    static func rooms(n: Int, carrier: HeldRing, chainRest: [HeldRing], restCarrier: HeldRing) -> (Double, [Double], String) {
        let (a, b, c, _) = roomsWithReasons(n: n, carrier: carrier, chainRest: chainRest, restCarrier: restCarrier)
        return (a, b, c)
    }

    static func roomsWithReasons(n: Int, carrier: HeldRing, chainRest: [HeldRing], restCarrier: HeldRing) -> (Double, [Double], String, [String]) {
        let chain = HangingChain(carrierAtRest: restCarrier, chainAtRest: chainRest).chain(carriedBy: carrier)
        var held: [Int: HeldRing] = [n - 1: carrier]
        for (offset, ring) in chain.enumerated() { held[n - 2 - offset] = ring }
        let ringsOnly: Set<PartName> = Set((1..<n).map { PartName.ring($0) })
        var withoutRods = Double.infinity
        var why = ""
        var poses: [ToyPose] = []
        for (index, step) in lift(n).enumerated() {
            held[n] = lifting(n, tip: step.tip)
            let pose = pose(held, sword: step.sword, raise: 0)
            if !failures(pose, n: n, rods: false).isEmpty { return (-1, [], "relations", []) }
            if Relations.isRoundTheRails(n - 1, in: pose) { return (-1, [], "carrier on the rails", []) }
            if index == lift(n).count - 1, Relations.isRoundTheRails(n, in: pose) { return (-1, [], "ring \(n) still on", []) }
            let shapes = pose.shapes.filter { if case .ring = $0.name { return true }; return $0.name == .sword }
            let (room, pair) = gap(shapes, ringsOnly)
            if room < withoutRods { (withoutRods, why) = (room, pair) }
            if withoutRods < wanted { return (withoutRods, [], why, []) }
            poses.append(pose)
        }
        let moving: Set<PartName> = Set((1..<n).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] } + [.bar])
        var byRaise: [Double] = []
        var reasons: [String] = []
        for raise in raises {
            var room = withoutRods
            var reason = ""
            for step in lift(n) {
                held[n] = lifting(n, tip: step.tip)
                let pose = pose(held, sword: step.sword, raise: raise)
                let failed = failures(pose, n: n, rods: true)
                if !failed.isEmpty { room = -1; reason = failed.joined(separator: ", "); break }
                let (gap, pair) = gap(pose.shapes, moving)
                if gap < room { (room, reason) = (gap, pair) }
                if room < wanted { break }
            }
            byRaise.append(room)
            reasons.append(reason)
        }
        return (withoutRods, byRaise, why, reasons)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_STEP_ASIDE"] != nil))
    func scan() {
        let n = Int(ProcessInfo.processInfo.environment["NINE_RINGS_STEP_ASIDE"] ?? "3") ?? 3
        let droop = ProcessInfo.processInfo.environment["NINE_RINGS_CHAIN"] == "droop"
        let clock = ContinuousClock()
        let started = clock.now
        let chainRest = Self.chainAtRest(below: n - 1, droop: droop)
        // The rest pose the move starts from, at each raise.
        var restHeld: [Int: HeldRing] = [:]
        for (offset, ring) in chainRest.enumerated() { restHeld[n - 2 - offset] = ring }
        for raise in Self.raises {
            let pose = Self.pose(restHeld, sword: Layout.swordHome, raise: raise)
            let all: Set<PartName> = Set((1...9).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] } + [.bar, .sword])
            let (room, pair) = Self.gap(pose.shapes, all)
            let failures = Self.failures(pose, n: n, rods: true)
            print(String(format: "ring %d rest, raise %4.1f: smallest gap %.3f (%@) %@", n, raise, room, pair, failures.description))
        }
        var combos: [(Double, Double, Double)] = []
        for lid in stride(from: 56.0, through: 132.0, by: 4) {
            for tilt in stride(from: -60.0, through: 60.0, by: 10) {
                for swing in stride(from: -180.0, to: 180.0, by: 10)
                where abs(Self.turns(n - 1, lid: lid, tilt: tilt, swing: swing).alongWire.y) < 0.9 {
                    combos.append((lid, tilt, swing))
                }
            }
        }
        let all = combos
        let restCarrier = RestPoses.on(n - 1)
        let results = Sweep.inParallel(all.count) { index in
            let (lid, tilt, swing) = all[index]
            return Self.rooms(n: n, carrier: Self.turns(n - 1, lid: lid, tilt: tilt, swing: swing), chainRest: chainRest, restCarrier: restCarrier)
        }
        let clear = results.indices.filter { results[$0].0 >= Self.wanted }
        print("ring \(n), chain \(droop ? "drooping" : "compounded"): \(clear.count) of \(all.count) poses leave ring \(n)'s lift \(Self.wanted) mm without the rods")
        for (column, raise) in Self.raises.enumerated() {
            let passing = clear.filter { results[$0].1[column] >= Self.wanted }
            let best = passing.max { results[$0].1[column] < results[$1].1[column] }
            let text = best.map { index -> String in
                let (lid, tilt, swing) = all[index]
                return String(format: "best room %.3f at lid %.0f tilt %.0f swing %.0f", results[index].1[column], lid, tilt, swing)
            } ?? "none"
            print(String(format: "ring %d raise %4.1f: %d poses with %.1f mm, ", n, raise, passing.count, Self.wanted) + text)
        }
        // Why the poses with the most room without the rods fail with them.
        for index in clear.sorted(by: { results[$0].0 > results[$1].0 }).prefix(3) {
            let (lid, tilt, swing) = all[index]
            let detail = Self.roomsWithReasons(n: n, carrier: Self.turns(n - 1, lid: lid, tilt: tilt, swing: swing), chainRest: chainRest, restCarrier: restCarrier)
            print(String(format: "pose lid %.0f tilt %.0f swing %.0f (%.3f without rods):", lid, tilt, swing, detail.0))
            for (raise, (room, reason)) in zip(Self.raises, zip(detail.1, detail.3)) {
                print(String(format: "   raise %4.1f: %.3f ", raise, room) + reason)
            }
        }
        let nearest = results.indices.filter { results[$0].0 < Self.wanted }.max { results[$0].0 < results[$1].0 }
        if let nearest {
            let (lid, tilt, swing) = all[nearest]
            print(String(format: "nearest miss without the rods: %.3f at lid %.0f tilt %.0f swing %.0f, ", results[nearest].0, lid, tilt, swing) + results[nearest].2)
        }
        print("scan took \(clock.now - started)")
    }
}
