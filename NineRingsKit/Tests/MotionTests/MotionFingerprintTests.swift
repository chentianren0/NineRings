import CryptoKit
import Foundation
import Motion
import Puzzle
import Testing
import Toy

/// A tool that writes a fingerprint of everything the app plays: for every one of the 511 moves, both ways, the
/// stages and a hash of the exact bits of the pose at 801 progress values; the rest pose of every state; and the
/// written moves menu. Two runs that write the same file played exactly the same motion, to the last bit, so a
/// change to the code that should not change the motion can be shown not to. Run with
/// `NINE_RINGS_FINGERPRINT_OUT=<file>`, optimized, before and after, and compare the files.
@Suite struct MotionFingerprintTests {
    static let environment = ProcessInfo.processInfo.environment

    static func bits(_ pose: ToyPose) -> [UInt64] {
        var numbers: [Double] = []
        for part in pose.rings + pose.rods + [pose.bar] {
            numbers += [part.position.x, part.position.y, part.position.z]
            numbers += [part.orientation.imag.x, part.orientation.imag.y, part.orientation.imag.z, part.orientation.real]
        }
        numbers += [pose.swordSlide, pose.swordHeight]
        return numbers.map(\.bitPattern)
    }

    static func hash(_ words: [UInt64]) -> String {
        var hasher = SHA256()
        words.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @Test(.enabled(if: environment["NINE_RINGS_FINGERPRINT_OUT"] != nil))
    func writeTheFingerprint() throws {
        let path = try #require(Self.environment["NINE_RINGS_FINGERPRINT_OUT"])
        let moves: [Move] = (0..<512).flatMap { bits in
            PuzzleState.rings.compactMap { ring -> Move? in Move(ring: ring, from: PuzzleState(bits: UInt16(bits))) }
        }
        let lines = Sweep.inParallel(moves.count) { index -> String in
            let move = moves[index]
            guard let motion = MoveMotion(move) else { return "ring \(move.ring) from \(move.from): not written" }
            let words = (0...800).flatMap { Self.bits(motion.pose(at: Double($0) / 800)) }
            let stages = motion.stages.map { "\($0.name) \(String($0.start.bitPattern, radix: 16)) \(String($0.end.bitPattern, radix: 16))" }
            return "ring \(move.ring) \(move.takesOff ? "off" : "on") from \(move.from): \(Self.hash(words)) | \(stages.joined(separator: " | "))"
        }
        let rests = (0..<512).map { bits -> String in
            let state = PuzzleState(bits: UInt16(bits))
            return "rest \(state): " + (RestPoses.pose(for: state).map { Self.hash(Self.bits($0)) } ?? "not written")
        }
        let menu = "written: " + MoveMotion.written.map { "ring \($0.ring) from \($0.from)" }.joined(separator: ", ")
        try (lines + rests + [menu]).joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        print("fingerprint: \(lines.count) moves, \(rests.count) rests written to the file")
    }
}
