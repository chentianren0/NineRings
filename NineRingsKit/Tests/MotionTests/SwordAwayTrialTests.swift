import Foundation
import Geometry
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

/// A tool for the trial of the sword moving away: sweeps the path for a range of drops and dips and prints the
/// room. Run with `NINE_RINGS_SWORD_AWAY=1`, optimized; `NINE_RINGS_DROPS` and `NINE_RINGS_DIPS` list the values,
/// `NINE_RINGS_RING` the ring (2 or 3).
@Suite struct SwordAwayTrialTests {
    static let environment = ProcessInfo.processInfo.environment

    static func list(_ name: String, _ fallback: [Double]) -> [Double] {
        environment[name].map { $0.split(separator: ",").compactMap { Double($0) } } ?? fallback
    }

    @Test(.enabled(if: environment["NINE_RINGS_SWORD_AWAY"] != nil))
    func sweepTheDropAndTheDip() throws {
        let ring = Int(Self.environment["NINE_RINGS_RING"] ?? "2") ?? 2
        let from = ring == 2 ? PuzzleState.allOn : PuzzleState.allOn.moving(1)
        let move = try #require(Move(ring: ring, from: from))
        let samples = Int(Self.environment["NINE_RINGS_SAMPLES"] ?? "1000") ?? 1000
        for drop in Self.list("NINE_RINGS_DROPS", [SwordAwayOff.drop]) {
            for dip in Self.list("NINE_RINGS_DIPS", [SwordAwayOff.dip]) {
                let path = SwordAwayOff(ring: ring, from: from, keys: SwordAwayOff.keys(
                    drop: drop, dip: dip,
                    asideSlide: Double(Self.environment["NINE_RINGS_ASIDE_SLIDE"] ?? "22.6") ?? 22.6,
                    dropSlide: Double(Self.environment["NINE_RINGS_DROP_SLIDE"] ?? "15.841") ?? 15.841
                ))
                let paced = SwordAwayOff.Paced(path)
                let sweep = Sweep(move, samples: samples, pose: paced.pose(atProgress:))
                let label = "ring \(ring), drop \(drop), dip \(dip)"
                let records = Sweep.inParallel(sweep.poses.count) { index -> Gap in
                    Gaps.smallest(in: sweep.poses[index].shapes.filter { $0.name != .bar })!
                }
                // The room round the rings that keep still, and their rods.
                let still = Set((1..<ring).flatMap { [PartName.ring($0), .eye($0), .shaft($0), .bead($0)] })
                let stillRecords = Sweep.inParallel(sweep.poses.count) { index -> Gap in
                    Gaps.smallest(in: sweep.poses[index].shapes.filter { $0.name != .bar }, reach: 30, involving: still)!
                }
                let stillWorst = stillRecords.indices.min { stillRecords[$0].distance < stillRecords[$1].distance }!
                print("\(label): round the still rings \(stillRecords[stillWorst]) at path \(paced.pacing.pathParameter(atProgress: sweep.progress[stillWorst]))")
                // The room above the bar for anything but the beads, which slide below it.
                let barRecords = Sweep.inParallel(sweep.poses.count) { index -> Gap in
                    Gaps.smallest(in: sweep.poses[index].shapes.filter { if case .bead = $0.name { return false } else { return true } }, reach: 60, involving: [.bar])!
                }
                let barWorst = barRecords.indices.min { barRecords[$0].distance < barRecords[$1].distance }!
                print("\(label): above the bar \(barRecords[barWorst]) at path \(paced.pacing.pathParameter(atProgress: sweep.progress[barWorst]))")
                let worst = records.indices.min { records[$0].distance < records[$1].distance }!
                print("\(label): smallest gap \(sweep.smallestGap.gap) at progress \(sweep.smallestGap.progress)")
                print("\(label): leaving out the bar \(records[worst]) at progress \(sweep.progress[worst]), path \(paced.pacing.pathParameter(atProgress: sweep.progress[worst]))")
                print("\(label): largest step \(sweep.largestStep)")
                // The worst gap in each tenth of the path.
                for tenth in 0..<10 {
                    let indices = records.indices.filter {
                        let parameter = paced.pacing.pathParameter(atProgress: sweep.progress[$0])
                        return parameter >= Double(tenth) / 10 && parameter < Double(tenth + 1) / 10
                    }
                    guard let index = indices.min(by: { records[$0].distance < records[$1].distance }) else { continue }
                    print("\(label):   path \(tenth)/10: \(records[index])")
                }
                if let failure = sweep.firstRelationFailure {
                    print("\(label): at progress \(failure.progress) (path \(paced.pacing.pathParameter(atProgress: failure.progress))): \(failure.failures.joined(separator: "; "))")
                } else {
                    print("\(label): every relation holds")
                }
            }
        }
    }
}

/// How far the sword, and everything that rides on it, can go down before anything meets the bar. Run with
/// `NINE_RINGS_SWORD_AWAY=1`, optimized.
@Suite struct SwordAwayRoomBelowTests {
    /// The toy at rest in `state`, with the sword and every ring from `firstRiding` on moved down by `drop`.
    static func pose(_ state: PuzzleState, firstRiding: Int, drop: Double) -> ToyPose {
        let rings = PuzzleState.rings.map { number -> HeldRing in
            var held = state.isOn(number) ? RestPoses.on(number) : RestPoses.hanging(number)
            if number >= firstRiding { held.eye.y -= drop }
            return held
        }
        return RestPoses.pose(holding: rings, swordSlide: Layout.swordHome, swordHeight: -drop)
    }

    /// The smallest gap between the bar and anything but the beads, which hang below it and slide down with their
    /// rods.
    static func barGap(_ pose: ToyPose) -> Gap {
        let shapes = pose.shapes.filter { if case .bead = $0.name { return false } else { return true } }
        return Gaps.smallest(in: shapes, reach: .infinity, involving: [.bar])!
    }

    @Test(.enabled(if: SwordAwayTrialTests.environment["NINE_RINGS_SWORD_AWAY"] != nil))
    func howFarDownBeforeTheBar() throws {
        let cases: [(String, PuzzleState, Int)] = [
            ("every ring behind on (ring 2 and on ride)", .allOn, 2),
            ("ring 5 hanging behind (ring 3 and on ride)", PuzzleState(bits: 0x1FF & ~(1 << 4)), 3),
            ("ring 8 hanging behind (ring 3 and on ride)", PuzzleState(bits: 0x1FF & ~(1 << 7)), 3),
        ]
        for (label, state, firstRiding) in cases {
            let rest = Self.pose(state, firstRiding: firstRiding, drop: 0)
            let restGap = try #require(Gaps.smallest(in: rest.shapes.filter { $0.name != .bar }))
            var drop = 0.0
            var limits: [Double: Double] = [:]
            while drop < 60 {
                let gap = Self.barGap(Self.pose(state, firstRiding: firstRiding, drop: drop)).distance
                for wanted in [0.3, 0.2] where limits[wanted] == nil && gap < wanted { limits[wanted] = drop - 0.01 }
                if gap < 0.2 { break }
                drop += 0.01
            }
            let first = Self.barGap(Self.pose(state, firstRiding: firstRiding, drop: drop))
            print("room below, \(label): rest gap leaving out the bar \(restGap); 0.3 mm from the bar down to \(String(format: "%.2f", limits[0.3] ?? -1)) mm, 0.2 mm down to \(String(format: "%.2f", limits[0.2] ?? -1)) mm; first to meet it: \(first)")
        }
    }
}
