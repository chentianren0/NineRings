import Motion
import Puzzle
import Testing
@testable import Session

/// Many random sequences of requests, each checked after every step against what must always hold, whatever
/// the order: the state is the start plus the moves made, each move made is legal from where it was made, the
/// progress is between 0 and 1, and nothing plays without a written move on the slider.
@Suite struct PuzzleSessionSequenceTests {
    /// A small, fixed random source, so that a failing sequence can be run again.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Where a sequence begins: every ring on, or at a written move, or its way back, at some progress.
    private func start(_ random: inout SplitMix) -> (PuzzleSession, String) {
        let moves = MoveMotion.written.flatMap { [$0, $0.reversed] }.filter { MoveMotion($0) != nil }
        guard !moves.isEmpty, Int.random(in: 0..<3, using: &random) > 0 else { return (PuzzleSession(), "init()") }
        let move = moves.randomElement(using: &random)!
        let progress = [0, 1, 0.5, Double.random(in: 0...1, using: &random)].randomElement(using: &random)!
        return (PuzzleSession(at: move, progress: progress), "init(at: ring \(move.ring) from \(move.from), progress: \(progress))")
    }

    /// Runs one random request. Where a button is offered or not, checks that pressing it does something or
    /// nothing, as offered.
    private func step(_ session: inout PuzzleSession, _ random: inout SplitMix) -> String {
        let before = session
        let name = request(&session, &random)
        // Play may go on to a waiting ring that cannot play; then it plays nothing, but says why.
        if name == "togglePlay()" && !before.isPlaying && before.canPlay == (session == before) {
            return name + " [play was \(before.canPlay ? "" : "not ")offered, and it \(session == before ? "did nothing" : "did something")]"
        }
        if name == "undo()" && before.canUndo == (session == before) {
            return name + " [undo was \(before.canUndo ? "" : "not ")offered, and it \(session == before ? "did nothing" : "did something")]"
        }
        // Solve may meet a first move that is not written; then it plays nothing and says so, as it did before.
        let stoppedAtOnce: Bool = {
            guard case .notWritten(_, whileSolving: true) = session.note else { return false }
            return !session.isPlaying
        }()
        if name == "solve()" && before.canSolve == (session == before) && !(before.canSolve && stoppedAtOnce) {
            return name + " [solve was \(before.canSolve ? "" : "not ")offered, and it \(session == before ? "did nothing" : "did something")]"
        }
        return name
    }

    private func request(_ session: inout PuzzleSession, _ random: inout SplitMix) -> String {
        switch Int.random(in: 0..<20, using: &random) {
        case 0..<5:
            // Taps favour the rings that can move, or nothing much would happen.
            let ring = Bool.random(using: &random)
                ? (session.state.movableRings.randomElement(using: &random) ?? 1)
                : Int.random(in: 1...9, using: &random)
            session.tap(ring)
            return "tap(\(ring))"
        case 5..<8:
            let distance = [0.001, 0.1, 0.3, 0.5, 1, 7].randomElement(using: &random)!
            session.advance(by: distance)
            return "advance(by: \(distance))"
        case 8, 9:
            session.togglePlay()
            return "togglePlay()"
        case 10:
            session.pause()
            return "pause()"
        case 11, 12:
            session.undo()
            return "undo()"
        case 13:
            session.solve()
            return "solve()"
        case 14:
            session.reset()
            return "reset()"
        default:
            let progress = [0, 1, 0.5, Double.random(in: -0.2...1.2, using: &random)].randomElement(using: &random)!
            session.scrub(to: progress)
            return "scrub(to: \(progress))"
        }
    }

    /// What must hold after any sequence of requests. Returns what does not.
    private func broken(_ session: PuzzleSession) -> [String] {
        var problems: [String] = []
        var state = session.start
        for move in session.made {
            if Move(ring: move.ring, from: state) != move { problems.append("made \(move) is not legal from \(state)") }
            state = move.to
        }
        if session.state != state { problems.append("state is not the start plus the moves made") }
        if !(0...1).contains(session.progress) { problems.append("progress \(session.progress)") }
        if session.isPlaying && session.motion == nil { problems.append("playing without a written move on the slider") }
        if session.pose == nil { problems.append("no pose") }
        if let current = session.current {
            if session.progress >= 1 && session.made.last != current { problems.append("at the slider's right end the move is not made") }
            if session.progress <= 0 && session.state != current.from { problems.append("at the slider's left end the move is made") }
            if session.state != current.from && session.state != current.to { problems.append("the state is neither end of the move on the slider") }
        } else if !session.made.isEmpty {
            problems.append("moves made with no move on the slider")
        }
        if session.isPlaying && session.direction == .forward && session.progress >= 1 { problems.append("playing forward at the end") }
        let inHand = session.isPlaying || (session.current != nil && session.progress > 0 && session.progress < 1)
        if session.isSolving && session.queue.isEmpty && !inHand { problems.append("solving with nothing left to play") }
        if session.markers.filter(\.isMoving).count != (inHand ? 1 : 0) { problems.append("the moving marker does not match the move in hand") }
        return problems
    }

    @Test func invariantsHoldAfterAnySequenceOfRequests() {
        var random = SplitMix(state: 0x6E69_6E65_7269_6E67)
        for run in 0..<3000 {
            var (session, first) = start(&random)
            var log = [first]
            for _ in 0..<40 {
                let name = step(&session, &random)
                log.append(name)
                var problems = broken(session)
                if name.hasSuffix("]") { problems.append("a button did not do as offered") }
                if !problems.isEmpty {
                    Issue.record("run \(run): \(problems.joined(separator: "; ")) after \(log.joined(separator: ", "))")
                    return
                }
            }
        }
    }

    /// Play runs the move on the slider forward, as its button says, even after an undo was paused part way.
    @Test func playAfterAPausedUndoRunsForward() {
        var session = PuzzleSession()
        session.tap(1)
        session.advance(by: 1)
        session.undo()
        session.advance(by: 0.3)
        session.togglePlay()
        #expect(!session.isPlaying)
        session.togglePlay()
        #expect(session.isPlaying)
        #expect(session.direction == .forward)
        session.advance(by: 1)
        #expect(session.progress == 1)
        #expect(session.state == PuzzleState.allOn.moving(1))
    }
}
