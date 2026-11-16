import Foundation
import Motion
import Testing

/// Prints the smallest gap through the move, a line per step of progress, for tuning the path by hand.
/// Run with `NINE_RINGS_PROFILE=1`.
@Suite struct ProfileTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_PROFILE"] != nil))
    func profile() throws {
        let motion = try #require(MoveMotion(ringOneOff))
        let sweep = Sweep(motion, samples: 400)
        for (index, gap) in sweep.gaps.enumerated() where index % 2 == 0 {
            let flag = gap.distance < smallestAllowedGap ? "  <<<" : ""
            print(String(format: "%.4f ", sweep.progress[index]) + "\(gap)" + flag)
        }
    }
}
