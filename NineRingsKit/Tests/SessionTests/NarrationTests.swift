import Motion
import Puzzle
import Testing
@testable import Session

/// What is said aloud by itself, for someone who cannot see the toy: the start of a move a request began, where each
/// ring went, a pause, a refusal every time, and the exceptions `PlayState` keeps.
@Suite struct NarrationTests {
    static let frame = 1.0 / 60

    /// Plays on, a frame at a time, until the toy stops: every line said on the way.
    private func playOut(_ state: inout PlayState) -> [Narration.Line] {
        var lines: [Narration.Line] = [], count = 0
        while state.toy.isPlaying && count < 1_000_000 {
            state.advance(by: Self.frame)
            lines += state.narration.lines
            count += 1
        }
        return lines
    }

    private func isBegan(_ line: Narration.Line, ring: Int, undoing: Bool = false) -> Bool {
        guard case .began(.playing(let move, _, let isUndoing)) = line else { return false }
        return move.ring == ring && isUndoing == undoing
    }

    @Test func askingForARingSaysTheMoveBeginningThenWhereTheRingWent() {
        var state = PlayState()
        state.tap(1)
        #expect(state.narration.lines.count == 1)
        #expect(state.narration.lines.first.map { isBegan($0, ring: 1) } == true)
        #expect(state.narration.lines.first == .began(state.toy.status))
        let lines = playOut(&state)
        #expect(lines == [.ended(ring: 1, state: PuzzleState("011111111")!)])
    }

    @Test func aRefusedRingIsSaidEveryTimeItIsAsked() {
        var state = PlayState()
        state.tap(3)
        #expect(state.narration.lines == [.refused(ring: 3, block: .earlierRingOn(1))])
        state.tap(3)
        #expect(state.narration.lines == [.refused(ring: 3, block: .earlierRingOn(1))])
    }

    @Test func pauseSaysTheStageAndPlaySaysTheMoveAgain() {
        var state = PlayState()
        state.tap(2)
        for _ in 0..<60 { state.advance(by: Self.frame) }
        state.togglePlay()
        guard case .paused(.paused(let move, let stage, false))? = state.narration.lines.first else {
            Issue.record("pause said \(state.narration.lines)")
            return
        }
        #expect(move.ring == 2)
        #expect(stage == MoveMotion(move).stage(at: state.toy.progress))
        state.togglePlay()
        #expect(state.narration.lines.count == 1)
        #expect(state.narration.lines.first.map { isBegan($0, ring: 2) } == true)
    }

    @Test func undoSaysTheMoveGoingBackAndTheRingBackOn() {
        var state = PlayState()
        state.tap(1)
        _ = playOut(&state)
        state.undo()
        #expect(state.narration.lines.count == 1)
        #expect(state.narration.lines.first.map { isBegan($0, ring: 1, undoing: true) } == true)
        #expect(playOut(&state) == [.ended(ring: 1, state: .allOn)])
    }

    /// Undo while a move plays turns it round: that is a start of its own.
    @Test func undoDuringAMoveSaysItGoingBack() {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<30 { state.advance(by: Self.frame) }
        state.undo()
        #expect(state.narration.lines.count == 1)
        #expect(state.narration.lines.first.map { isBegan($0, ring: 1, undoing: true) } == true)
    }

    /// A ring asked during a move waits; when its turn comes the rule refuses it, after the first ring's end is said.
    @Test func aChainSaysItsEndThenTheRefusalThatStopsIt() {
        var state = PlayState()
        state.tap(1)
        state.tap(2)
        #expect(state.narration.isEmpty)
        let lines = playOut(&state)
        #expect(lines == [.ended(ring: 1, state: PuzzleState("011111111")!), .refused(ring: 2, block: .previousRingOff(1))])
    }

    /// Solve says its first move beginning and where the last ring went, and nothing between: a chain of announcements,
    /// each interrupting the last, would drown out everything else.
    @Test func solveSaysOnlyItsStartAndItsEnd() {
        var state = PlayState(PuzzleSession(resting: PuzzleState("011000000")!))
        let expected = PuzzleState("011000000")!.moves(to: .allOff)
        #expect(expected.count > 2)
        state.solve()
        #expect(state.narration.lines.count == 1)
        #expect(state.narration.lines.first.map { isBegan($0, ring: expected[0]) } == true)
        #expect(playOut(&state) == [.ended(ring: expected.last!, state: .allOff)])
        #expect(!state.isCongratulating)
    }

    /// The whole Solve, every ring on to every ring off: 341 moves, two announcements.
    @Test func aWholeSolveSaysTwoThings() {
        var state = PlayState()
        state.solve()
        var said = state.narration.isEmpty ? 0 : 1
        var count = 0
        while state.toy.isPlaying && count < 10_000_000 {
            state.advance(by: 0.25)
            if !state.narration.isEmpty { said += 1 }
            count += 1
        }
        #expect(state.toy.state == .allOff)
        #expect(state.toy.moveCount == 341)
        #expect(said == 2)
    }

    /// The person's own move that takes the last ring off is said by the congratulation, not as a ring's end.
    @Test func theCongratulationSaysTheLastRingOff() {
        var state = PlayState(PuzzleSession(resting: PuzzleState("100000000")!))
        state.tap(1)
        var congratulated = false
        while state.toy.isPlaying {
            state.advance(by: Self.frame)
            if state.congratulates {
                congratulated = true
                #expect(state.narration.isEmpty, "said \(state.narration.lines)")
            }
        }
        #expect(congratulated)
    }

    @Test func aDragOfTheSliderSaysNothing() {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<30 { state.advance(by: Self.frame) }
        state.scrub(to: 0.5)
        #expect(state.narration.isEmpty)
        state.scrub(to: 1)
        #expect(state.narration.isEmpty)
    }

    @Test func resetSaysEveryRingOn() {
        var state = PlayState()
        state.tap(1)
        _ = playOut(&state)
        state.reset()
        #expect(state.narration.lines == [.rested(ToySummary(.allOn))])
    }

    /// While the lesson holds the toy its moves are not said; closing it says the person's toy, as it was.
    @Test func theLessonKeepsQuietAndClosingItSaysTheToy() {
        var state = PlayState(PuzzleSession(resting: PuzzleState("011111111")!))
        state.openLesson(at: 3)
        #expect(state.narration.isEmpty)
        #expect(playOut(&state).isEmpty)
        state.goToLessonStep(4)
        #expect(state.narration.isEmpty)
        #expect(playOut(&state).isEmpty)
        state.closeLesson()
        #expect(state.narration.lines == [.rested(ToySummary(PuzzleState("011111111")!))])
    }

    /// The step that gives the toy back gives back its voice too.
    @Test func theLessonsLastStepIsNarrated() {
        var state = PlayState()
        state.openLesson(at: Lesson.steps.count - 1)
        _ = playOut(&state)
        state.tap(1)
        #expect(state.narration.lines.first.map { isBegan($0, ring: 1) } == true)
    }

    /// The screen pauses quietly before it covers the toy for a jump: a pause then Reset says only what Reset says.
    @Test func aPauseBeforeAJumpSaysOnlyTheJump() {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<30 { state.advance(by: Self.frame) }
        state.pause(quiet: true)
        #expect(state.narration.isEmpty)
        state.reset()
        #expect(state.narration.lines == [.rested(ToySummary(.allOn))])

        state.tap(1)
        for _ in 0..<30 { state.advance(by: Self.frame) }
        state.pause(quiet: true)
        #expect(state.narration.isEmpty)
        state.openLesson()
        #expect(state.narration.isEmpty)
    }

    /// A pause asked for by the person still says where the move stopped.
    @Test func aPauseAskedForStillSaysTheStage() {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<30 { state.advance(by: Self.frame) }
        state.pause()
        guard case .paused? = state.narration.lines.first else {
            Issue.record("pause said \(state.narration.lines)")
            return
        }
    }

    /// A request that changes nothing does not say the last change again: here, going to a step after the lesson has
    /// closed, which the menu bar can ask for while the screen is still covering the toy.
    @Test func aRequestThatChangesNothingSaysNothing() {
        var state = PlayState()
        state.openLesson(at: 2)
        state.closeLesson()
        #expect(state.narration.lines == [.rested(ToySummary(.allOn))])
        state.goToLessonStep(3)
        #expect(state.narration.isEmpty)
        #expect(state.hearing == Hearing())
        state.closeLesson()
        #expect(state.narration.isEmpty)
    }
}
