import Foundation
import Motion
import Puzzle
import Testing
import Toy

/// Every one of the 511 moves through the checker, as each written move is checked: 4000 samples each way, the
/// smallest gap, the largest step and every relation, and the two ends the rest poses. It takes about an hour
/// on the Mac the project is developed on, so it runs only when asked: `NINE_RINGS_EVERY_MOVE=1`, optimized. It
/// splits the moves between copies (`NINE_RINGS_COPY` of `NINE_RINGS_COPIES`), so that it can run on GitHub as
/// several copies side by side, and writes a line for each move as it goes to `NINE_RINGS_EVERY_MOVE_OUT`, or on
/// GitHub to `tool-output/every-move-<copy>.txt`.
@Suite struct EveryMoveTests {
    static let environment = ProcessInfo.processInfo.environment

    /// Every move, coming off: each state paired with each ring that is on and may move. Each goes back on along
    /// the same path, which the test checks too.
    static let moves: [Move] = (0..<512).flatMap { bits in
        PuzzleState.rings.compactMap { ring -> Move? in
            let state = PuzzleState(bits: UInt16(bits))
            return state.isOn(ring) ? Move(ring: ring, from: state) : nil
        }
    }

    @Test func thereAre511Moves() {
        #expect(Self.moves.count == 511)
        #expect(Set(Self.moves.map { [$0.from, $0.to].sorted { $0.bits < $1.bits } }).count == 511)
    }

    @Test(.enabled(if: environment["NINE_RINGS_EVERY_MOVE"] != nil))
    func everyMovePassesTheChecker() throws {
        let copy = Int(Self.environment["NINE_RINGS_COPY"] ?? "1") ?? 1
        let copies = Int(Self.environment["NINE_RINGS_COPIES"] ?? "1") ?? 1
        let mine = Self.moves.indices.filter { $0 % copies == copy - 1 }.map { Self.moves[$0] }
        let onGitHub = Self.environment["GITHUB_WORKSPACE"].map { "\($0)/tool-output/every-move-\(copy).txt" }
        let path = Self.environment["NINE_RINGS_EVERY_MOVE_OUT"] ?? onGitHub
        var log = ""
        func write(_ line: String) {
            print(line)
            fflush(stdout)
            log += line + "\n"
            if let path { try? log.write(toFile: path, atomically: true, encoding: .utf8) }
        }
        write("copy \(copy) of \(copies): \(mine.count) moves, each both ways")
        var worstGap = (Double.infinity, ""), worstStep = (0.0, ""), failures = 0
        let clock = DispatchTime.now().uptimeNanoseconds
        for off in mine {
            for move in [off, off.reversed] {
                let motion = try #require(MoveMotion(move))
                let sweep = Sweep(motion)
                let gap = sweep.smallestGap, step = sweep.largestStep
                let failure = sweep.firstRelationFailure
                let before = try #require(RestPoses.pose(for: move.from)), after = try #require(RestPoses.pose(for: move.to))
                let ends = Relations.isClose(motion.pose(at: 0), before) && Relations.isClose(motion.pose(at: 1), after)
                let label = "ring \(move.ring) \(move.takesOff ? "off" : "on") from \(move.from)"
                let passes = gap.gap.distance >= smallestAllowedGap && step.distance <= largestAllowedStep && failure == nil && ends
                if !passes { failures += 1 }
                write(String(format: "%@: %@ gap %.3f (%@ and %@) at %.4f, step %.4f; %@",
                             label, passes ? "passes" : "FAILS", gap.gap.distance, "\(gap.gap.first)", "\(gap.gap.second)", gap.progress, step.distance,
                             failure.map { "at \($0.progress): \($0.failures.joined(separator: "; "))" } ?? (ends ? "every relation holds" : "the ends are not the rest poses")))
                if gap.gap.distance < worstGap.0 { worstGap = (gap.gap.distance, label) }
                if step.distance > worstStep.0 { worstStep = (step.distance, label) }
                #expect(passes, "\(label)")
            }
        }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - clock) / 1e9
        write(String(format: "copy %d: %d of %d checks fail; smallest gap %.3f in %@; largest step %.4f in %@; %.0f s",
                     copy, failures, 2 * mine.count, worstGap.0, worstGap.1, worstStep.0, worstStep.1, seconds))
    }
}
