import Motion
import Puzzle
import Testing
@testable import Session

/// What is heard as a session plays: every event of every move once, in order, however the time is cut, across the
/// changes from one move to the next; the reversed move when going back; and nothing on a jump.
@Suite struct HearingTests {
    /// Steps of uneven length, in seconds of the move's own time: some tiny, some longer than a frame at 4×.
    static let steps = [0.013, 0.05, 0.0007, 0.1, 0.031, 0.4, 0.002, 0.07]

    /// Solving from every ring on, played on in uneven steps, hears every event of every move made, once and in
    /// order, and hears the sword travel its whole way.
    @Test func solvingHearsEveryEventOnce() {
        var session = PuzzleSession()
        session.solve()
        var heard: [Hearing.Heard] = [], travel = 0.0
        var step = 0
        while session.isPlaying {
            let before = session
            session.advance(by: Self.steps[step % Self.steps.count])
            step += 1
            let hearing = Hearing(from: before, to: session)
            heard += hearing.events
            travel += hearing.swordTravel
            #expect(hearing.refused == nil)
        }
        #expect(session.state == .allOff && session.moveCount == 341)
        let expected = session.made.enumerated().flatMap { number, move in
            Score(move).events.enumerated().map { Hearing.Heard(event: $1, move: move, index: $0, moveNumber: number) }
        }
        #expect(heard == expected)
        let whole = session.made.map { Score($0).totalSwordTravel }.reduce(0, +)
        #expect(abs(travel - whole) < 1e-6 * whole)
    }

    /// Dragged forward in steps and back again, a move is heard forward, then as the reversed move.
    @Test func draggingBackHearsTheReversedMove() {
        var session = PuzzleSession()
        session.tap(1)
        session.pause()
        let move = session.current!
        var forward: [Score.Event] = [], back: [Score.Event] = []
        for index in 1...40 {
            let before = session
            session.scrub(to: Double(index) / 40)
            forward += Hearing(from: before, to: session).events.map(\.event)
        }
        for index in (0..<40).reversed() {
            let before = session
            session.scrub(to: Double(index) / 40)
            back += Hearing(from: before, to: session).events.map(\.event)
        }
        #expect(forward == Score(move).events)
        #expect(back == Score(move.reversed).events)
    }

    /// Undo runs the move back: heard as the reversed move. Then undo again goes into the move before from its end,
    /// silently, and runs it back too.
    @Test func undoHearsTheReversedMoves() {
        var session = PuzzleSession()
        session.tap(1)
        run(&session)
        session.tap(3)
        run(&session)
        let first = session.made[0], second = session.made[1]
        session.undo()
        let back = run(&session)
        #expect(back.map(\.event) == Score(second.reversed).events)
        session.undo()
        let backAgain = run(&session)
        #expect(backAgain.map(\.event) == Score(first.reversed).events)
        #expect(session.state == .allOn)
    }

    /// The rule's refusal is heard every time a ring is asked for and refused, twice in a row too, and from the queue.
    @Test func refusalsAreHeard() {
        var session = PuzzleSession()
        for _ in 0..<2 {
            let before = session
            session.tap(4)
            #expect(Hearing(from: before, to: session, tapped: 4).refused == 4)
        }
        // A ring asked for while a move plays waits, and is refused when its turn comes.
        session.tap(1)
        let before = session
        session.tap(4)
        #expect(Hearing(from: before, to: session, tapped: 4).refused == nil)
        var refused: [Int] = []
        while session.isPlaying {
            let before = session
            session.advance(by: 0.05)
            if let ring = Hearing(from: before, to: session).refused { refused.append(ring) }
        }
        #expect(refused == [4])
    }

    /// A ring asked for again while it moves changes nothing, so nothing is heard and nothing refused.
    @Test func aRepeatedTapIsHeardAsNothing() {
        var session = PuzzleSession()
        session.tap(1)
        session.advance(by: 0.5)
        let before = session
        session.tap(1)
        #expect(session == before)
        #expect(Hearing(from: before, to: session, tapped: 1) == Hearing())
    }

    /// Reset and starting at a chosen move are jumps: nothing is heard.
    @Test func jumpsAreSilent() {
        var session = PuzzleSession()
        session.tap(1)
        run(&session)
        let made = session
        session.reset()
        #expect(Hearing(from: made, to: session) == Hearing())
        let chosen = PuzzleSession(at: MoveMotion.written[4], progress: 0.9)
        #expect(Hearing(from: made, to: chosen).events.isEmpty)
    }

    /// At full speed every event sounds when heard as the app hears it: frame by frame, at 60 and 120 frames a second,
    /// from eight phases of the frame, thinned by the frame's time, across the first forty moves of the solution.
    @Test(arguments: [60.0, 120.0])
    func atFullSpeedEveryEventSoundsFrameByFrame(fps: Double) {
        var dropped: [String] = []
        for phase in stride(from: 0.0, to: 1.0, by: 0.125) {
            var session = PuzzleSession()
            session.solve()
            var thinning = Thinning()
            var time = phase / fps
            var moves = 0
            while session.isPlaying && moves < 40 {
                let before = session
                session.advance(by: 1 / fps)
                time += 1 / fps
                for heard in Hearing(from: before, to: session).events where !thinning.admits(heard.event, at: time) {
                    dropped.append("move \(heard.moveNumber) ring \(heard.move.ring): \(heard.event.what) (phase \(phase))")
                }
                if session.moveCount != before.moveCount { moves += 1 }
            }
        }
        #expect(dropped.isEmpty, "\(dropped.count) dropped at \(Int(fps)) fps; first: \(dropped.prefix(4))")
    }

    /// Plays on until the session stops, and returns what was heard.
    @discardableResult
    private func run(_ session: inout PuzzleSession) -> [Hearing.Heard] {
        var heard: [Hearing.Heard] = []
        var step = 0
        while session.isPlaying {
            let before = session
            session.advance(by: Self.steps[step % Self.steps.count])
            step += 1
            heard += Hearing(from: before, to: session).events
        }
        return heard
    }
}
