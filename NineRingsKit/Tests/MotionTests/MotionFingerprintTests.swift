import CryptoKit
import Foundation
import Motion
import Puzzle
import Testing
import Toy

extension MotionTests {
    /// The fingerprint of every pose the app can show, held to a value written here.
    ///
    /// For every one of the 511 moves, both ways, it hashes the exact bits of the pose at 801 progress values; for every
    /// state, the bits of its rest pose; one line for each, and a hash of all the lines. A change to the code that should
    /// leave the motion alone leaves this value alone, to the last bit; a change meant to change the motion changes the
    /// value here with it. The stages' names and the menu of moves are not in it.
    ///
    /// With `NINE_RINGS_FINGERPRINT_OUT=<file>` it also writes the lines, so that two runs can be compared move by move.
    @Suite struct MotionFingerprintTests {
        /// The hash of every pose, as the motion was written when this check was made.
        static let expected = "d72a819cd5d4b1f1ac6c666eb99440d9d497c657cb293336c2bc27d4cb4645e5"

        static func bits(_ pose: ToyPose) -> [UInt64] {
            var numbers: [Double] = []
            for part in pose.rings + pose.rods + [pose.bar] {
                numbers += [part.position.x, part.position.y, part.position.z]
                numbers += [part.orientation.imag.x, part.orientation.imag.y, part.orientation.imag.z, part.orientation.real]
            }
            numbers += [pose.swordSlide, pose.swordHeight]
            return numbers.map(\.bitPattern)
        }

        static func hash(_ bytes: some DataProtocol) -> String {
            SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }

        static func hash(_ words: [UInt64]) -> String {
            words.withUnsafeBytes { hash(Data($0)) }
        }

        /// One line for each move, both ways, and one for each state's rest, each with the hash of its poses.
        static func lines() -> [String] {
            let moves: [Move] = (0..<512).flatMap { bits in
                PuzzleState.rings.compactMap { ring -> Move? in Move(ring: ring, from: PuzzleState(bits: UInt16(bits))) }
            }
            let movesLines = Sweep.inParallel(moves.count) { index -> String in
                let move = moves[index]
                let motion = MoveMotion(move)
                let words = (0...800).flatMap { bits(motion.pose(at: Double($0) / 800)) }
                return "ring \(move.ring) \(move.takesOff ? "off" : "on") from \(move.from): \(hash(words))"
            }
            let restLines = (0..<512).map { bits -> String in
                let state = PuzzleState(bits: UInt16(bits))
                return "rest \(state): \(hash(Self.bits(RestPoses.pose(for: state))))"
            }
            return movesLines + restLines
        }

        @Test func everyPoseIsAsItWasWritten() throws {
            let lines = Self.lines()
            let text = lines.map { $0 + "\n" }.joined()
            if let path = ProcessInfo.processInfo.environment["NINE_RINGS_FINGERPRINT_OUT"] {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
            }
            let found = Self.hash(Data(text.utf8))
            print("fingerprint: \(lines.count) lines, hash \(found)")
            #expect(lines.count == 1022 + 512)
            #expect(found == Self.expected, "the poses differ from those this check was made with")
        }
    }
}
