import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy
import simd

// Probes of the checker for what the second ring's move brought: a sword that goes down and up, a ring in front that
// the sword leaves while it keeps still, and rings that are off and may be anywhere off the rails during a move.
// Each probe is the move as written with one thing wrong, or a pose function built from written moves, and asks
// whether the checker, used as the written moves' tests use it, fails it.

/// What the checker says of a run of poses, as `PairMoveTests` and `EveryMoveTests` judge a move: the smallest gap,
/// the largest step and the first relation that fails. The ends are checked apart, against the rest poses.
struct ProbeSweepVerdict: CustomStringConvertible {
    let gap: Gap
    let gapProgress: Double
    let step: Double
    let failure: (progress: Double, failures: [String])?

    init(_ sweep: Sweep) {
        (gap, gapProgress) = sweep.smallestGap
        step = sweep.largestStep.distance
        failure = sweep.firstRelationFailure
    }

    var gapCaught: Bool { gap.distance < smallestAllowedGap }
    var stepCaught: Bool { step > largestAllowedStep }
    var caught: Bool { gapCaught || stepCaught || failure != nil }

    var description: String {
        String(format: "smallest gap %@ at %.4f; largest step %.3f; ", gap.description, gapProgress, step)
            + (failure.map { "fails at \(String(format: "%.4f", $0.progress)): \($0.failures.joined(separator: "; "))" } ?? "no relation fails")
    }
}

/// Ring 3 coming off with ring 1 off in front and every ring behind on.
private let probePairMove = Move(ring: 3, from: state("011111111"))!

/// Ring 3's path with some keys replaced, paced as the written move is.
private func probePairPath(_ change: (inout [String: [(Double, Double)]]) -> Void) -> (Double) -> ToyPose {
    var keys = PairMoveOff.keys
    change(&keys)
    let path = PairMoveOff(ring: 3, from: probePairMove.from, keys: keys)
    let pacing = PairMoveOff.paced[1].pacing
    return { path.pose(at: pacing.pathParameter(atProgress: $0)) }
}

/// `pose` with the sword and every ring from `first` on moved down by `depth`, their rods sliding down through the bar,
/// as the second ring's move takes them.
private func probeLowered(_ pose: ToyPose, by depth: Double, from first: Int, state: PuzzleState) -> ToyPose {
    let held = PuzzleState.rings.map { number -> HeldRing in
        var ring = RestPoses.resting(number, in: state)
        if number >= first { ring.eye.y -= depth }
        return ring
    }
    return RestPoses.pose(holding: held, swordSlide: pose.swordSlide, swordHeight: pose.swordHeight - depth)
}

@Suite struct PairMoveCheckerProbes {
    /// The probes sample a quarter as finely as the written moves' tests, to keep the suite quick, so their steps are
    /// larger than the step rule allows; each fault must be caught by the gap rule or a relation.
    private func expectCaught(_ name: String, _ move: Move, samples: Int = Sweep.samples / 4, _ pose: @escaping (Double) -> ToyPose) -> ProbeSweepVerdict {
        let verdict = ProbeSweepVerdict(Sweep(move, samples: samples, pose: pose))
        print("pair probe \(name): \(verdict)")
        #expect(verdict.gapCaught || verdict.failure != nil, "\(name): \(verdict)")
        return verdict
    }

    /// The move as written passes, so that each probe below differs from a passing move by its fault alone.
    @Test func theWrittenMovePasses() throws {
        let verdict = ProbeSweepVerdict(Sweep(try #require(MoveMotion(probePairMove)), samples: Sweep.samples / 4))
        print("pair probe as written: \(verdict)")
        #expect(!verdict.gapCaught && verdict.failure == nil)
    }

    /// The sword goes down while its tip is still in ring 2, which keeps still: the rails come down through ring 2's
    /// lower arc.
    @Test func theSwordGoesDownThroughTheStillRingInFront() {
        let verdict = expectCaught("sword down through ring 2", probePairMove, probePairPath { keys in
            keys["sword.height"] = [(0, 0), (0.06, -PairMoveOff.drop), (0.85, -PairMoveOff.drop), (0.90, -6), (0.93, -3), (1, 0)]
        })
        #expect(verdict.gap.first == .ring(2) || verdict.gap.second == .ring(2) || verdict.failure != nil)
    }

    /// The sword goes straight down out of ring 2 between one sample and the next, through its wire: only the rule
    /// that a ring leaves the rails over the tip end sees it.
    @Test func theSwordJumpsDownOutOfTheRingInFrontBetweenTwoSamples() {
        let rest = RestPoses.pose(for: probePairMove.from)!
        let sweep = Sweep(probePairMove, samples: 1) { progress in
            probeLowered(rest, by: 30 * progress, from: 3, state: probePairMove.from)
        }
        let failure = sweep.firstRelationFailure
        print("pair probe jump out of ring 2: \(failure.map { $0.failures.joined(separator: "; ") } ?? "nothing fails")")
        #expect(failure?.failures.contains("ring 2 leaves the rails away from the tip end") == true)
    }

    /// The sword goes down only 8 mm: ring 3 cannot pass under ring 2.
    @Test func theSwordDoesNotGoDownFarEnough() {
        _ = expectCaught("drop of 8 mm", probePairMove, probePairPath { keys in
            keys["sword.height"] = keys["sword.height"]!.map { ($0.0, max($0.1, -8)) }
        })
    }

    /// The sword lowered until its rails are in the bar, every ring on as it rests: the gap between the sword and the
    /// bar is measured like any other.
    @Test func theSwordLoweredIntoTheBar() {
        var pose = RestPoses.pose(for: .allOn)!
        pose.swordHeight = probeBarTop - Dimensions.Sword.railHeight + Dimensions.Sword.wireRadius - 0.5
        let truth = ProbeBrute.gap(.sword, .bar, in: pose, steps: 500)
        let verdict = ProbeVerdict(pose, .sword, .bar)
        print("pair probe sword into the bar: true gap \(String(format: "%.3f", truth)); \(verdict)")
        #expect(truth < 0)
        #expect(verdict.pairCaught && abs(verdict.pairGap - truth) < 1e-3)
    }

    /// For the drop the sword slides 3 mm further forward: its tip runs into rod 1, which hangs in front of it.
    @Test func theTipRunsIntoTheRodInFront() {
        let verdict = expectCaught("tip into rod 1", probePairMove, probePairPath { keys in
            keys["sword.slide"] = keys["sword.slide"]!.map { ($0.0, $0.1 == PairMoveOff.dropSlide ? $0.1 - 3 : $0.1) }
        })
        #expect(verdict.gapCaught)
    }

    /// Ring 3's eye does not move back for the drop: ring 3 meets the tip's half circle (the reason for the move back).
    @Test func theRingDropsWithoutItsEyeMovingBack() {
        _ = expectCaught("no move back", probePairMove, probePairPath { keys in
            keys["ring.back"] = [(0, 0), (1, 0)]
        })
    }

    /// Ring 5, behind and on, stays where it rests while the sword goes down: the rails come down through its wire.
    @Test func aRingBehindDoesNotGoDownWithTheSword() {
        let move = probePairMove
        let path = probePairPath { _ in }
        let rest = RestPoses.pose(for: move.from)!
        _ = expectCaught("ring 5 stays up", move) { progress in
            var pose = path(progress)
            pose.rings[4] = rest.ring(5)
            pose.rods[4] = rest.rod(5)
            return pose
        }
    }

    /// Ring 1, off in front of ring 3, goes on and comes off again before ring 3's move: the two are written moves
    /// (ring 1's move, which is legal in every state, both ways), so nothing passes through anything and nothing jumps.
    /// Played as ring 3's move, a ring in front that is off has got onto the rails and off again: the move is three
    /// moves. Only the rule that a ring off before and after the move stays off the rails sees it.
    @Test func aRingInFrontThatIsOffGetsOnAndOffAgainDuringTheMove() throws {
        let move = probePairMove
        let ringOneOn = try #require(MoveMotion(Move(ring: 1, from: move.from)!))
        let ringOneOff = try #require(MoveMotion(Move(ring: 1, from: move.from.moving(1))!))
        let pair = try #require(MoveMotion(move))
        // A fifth of the move each for ring 1 on and off. Only the relations are asked about: the steps are larger
        // than the step rule allows at this sampling, and smaller than it at five times as many samples.
        let pose: (Double) -> ToyPose = { progress in
            switch progress {
            case ..<0.2: ringOneOn.pose(at: progress / 0.2)
            case ..<0.4: ringOneOff.pose(at: (progress - 0.2) / 0.2)
            default: pair.pose(at: (progress - 0.4) / 0.6)
            }
        }
        let sweep = Sweep(move, samples: 2000, pose: pose)
        let verdict = ProbeSweepVerdict(sweep)
        let roundOne = sweep.roundTheRails(1)
        let fine = (0...10_000).map { pose(Double($0) / 10_000) }
        #expect(zip(fine, fine.dropFirst()).map { Relations.largestStep(from: $0, to: $1).distance }.max()! <= largestAllowedStep)
        print("pair probe ring 1 on and off in front: ring 1 round the rails at \(roundOne.filter { $0 }.count) of \(roundOne.count) samples; \(verdict)")
        #expect(roundOne.contains(true), "the probe does not build the fault it means to")
        #expect(Relations.isClose(pose(0), RestPoses.pose(for: move.from)!) && Relations.isClose(pose(1), RestPoses.pose(for: move.to)!))
        #expect(verdict.failure?.failures.contains("ring 1 has got onto the rails") == true, "\(verdict)")
    }

    /// The same behind the moving ring: in ring 1's move with ring 2 off behind it, ring 2 goes on and comes off again
    /// (its move is legal while ring 1 is on) before ring 1 comes off.
    @Test func aRingBehindThatIsOffGetsOnAndOffAgainDuringTheMove() throws {
        let move = Move(ring: 1, from: state("101111111"))!
        let ringTwoOn = try #require(MoveMotion(Move(ring: 2, from: move.from)!))
        let ringTwoOff = try #require(MoveMotion(Move(ring: 2, from: move.from.moving(2))!))
        let ringOne = try #require(MoveMotion(move))
        let pose: (Double) -> ToyPose = { progress in
            switch progress {
            case ..<0.3: ringTwoOn.pose(at: progress / 0.3)
            case ..<0.6: ringTwoOff.pose(at: (progress - 0.3) / 0.3)
            default: ringOne.pose(at: (progress - 0.6) / 0.4)
            }
        }
        let sweep = Sweep(move, samples: 2000, pose: pose)
        let verdict = ProbeSweepVerdict(sweep)
        print("pair probe ring 2 on and off behind ring 1: \(verdict)")
        #expect(sweep.roundTheRails(2).contains(true), "the probe does not build the fault it means to")
        #expect(verdict.failure?.failures.contains("ring 2 has got onto the rails") == true, "\(verdict)")
    }
}
