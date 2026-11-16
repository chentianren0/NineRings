import Foundation
import Motion
import Testing

/// The move to profile: ring 1's, or ring 2's when `NINE_RINGS_PROFILE` is 2.
private var profiledMove: Move {
    ProcessInfo.processInfo.environment["NINE_RINGS_PROFILE"] == "2" ? ringTwoOff : ringOneOff
}

/// Prints the smallest gap through the move, a line per step of progress, for tuning the path by hand.
/// Run with `NINE_RINGS_PROFILE=1`, or `NINE_RINGS_PROFILE=2` for ring 2's move.
@Suite struct ProfileTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_PROFILE"] != nil))
    func profile() throws {
        let motion = MoveMotion(profiledMove)
        let sweep = Sweep(motion, samples: 400)
        for (index, gap) in sweep.gaps.enumerated() where index % 2 == 0 {
            let flag = gap.distance < smallestAllowedGap ? "  <<<" : ""
            print(String(format: "%.4f ", sweep.progress[index]) + "\(gap)" + flag)
        }
    }
}

extension ProfileTests {
    /// Prints, for each fiftieth of the move's time, the fastest any point moves, in millimetres per second at full
    /// speed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_PROFILE"] != nil))
    func speeds() throws {
        let motion = MoveMotion(profiledMove)
        let samples = 4000
        let timing = motion.timing
        let poses = (0...samples).map { motion.pose(at: timing.progress(atTime: timing.duration * Double($0) / Double(samples))) }
        let steps = zip(poses, poses.dropFirst()).map { Relations.largestStep(from: $0, to: $1) }
        let perSecond = Double(samples) / timing.duration
        for bin in 0..<50 {
            let slice = steps[(bin * samples / 50)..<((bin + 1) * samples / 50)]
            let fastest = slice.max { $0.distance < $1.distance }!
            print(String(format: "%.2f  %6.1f mm/s  %@", Double(bin) / 50, fastest.distance * perSecond, fastest.part))
        }
    }
}
