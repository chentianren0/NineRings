import Motion
import Puzzle
import Testing
@testable import Session

/// The puzzle as the screen plays it: jumps are silent, and the congratulation follows the person's own toy, in the
/// lesson too. These began as the probes of the review of sound and the player.
@Suite struct PlayStateTests {
    static let frame = 1.0 / 60

    /// Plays on, a frame at a time, until the toy stops: everything heard, and the sword's travel the frames saw.
    @discardableResult
    private func playOut(_ state: inout PlayState) -> (heard: [Hearing.Heard], travel: Double, congratulated: Int) {
        var heard: [Hearing.Heard] = [], travel = 0.0, congratulated = 0, count = 0
        while state.toy.isPlaying && count < 1_000_000 {
            state.advance(by: Self.frame)
            heard += state.hearing.events
            travel += state.frame()
            if state.congratulates { congratulated += 1 }
            count += 1
        }
        return (heard, travel, congratulated)
    }

    /// A jump hears nothing, and the next frame sees no travel across it.
    private func expectSilent(_ state: inout PlayState, _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let hearing = state.hearing
        #expect(hearing.events.isEmpty, "\(what): heard \(hearing.events.map(\.event.what))", sourceLocation: sourceLocation)
        #expect(hearing.refused == nil, "\(what): refused again", sourceLocation: sourceLocation)
        #expect(hearing.swordTravel == 0, "\(what): \(hearing.swordTravel) mm of sword", sourceLocation: sourceLocation)
        let travel = state.frame()
        #expect(travel == 0, "\(what): the slide sees \(travel) mm in one frame", sourceLocation: sourceLocation)
    }

    // MARK: - Jumps are silent

    /// Step 4 (ring 1 coming off) played out, then Play Again.
    @Test func playAgainOnStepFourIsSilent() {
        var state = PlayState()
        state.openLesson(at: 3)
        playOut(&state)
        state.goToLessonStep(3)
        expectSilent(&state, "Play Again on step 4")
    }

    /// Steps 4 and 5 walked forward, then Back to step 4.
    @Test func backFromStepFiveToStepFourIsSilent() {
        var state = PlayState()
        state.openLesson(at: 3)
        playOut(&state)
        state.goToLessonStep(4)
        playOut(&state)
        state.goToLessonStep(3)
        expectSilent(&state, "Back to step 4")
    }

    /// Forward to step 8, Back to step 7, Back to step 6.
    @Test func backFromStepSevenToStepSixIsSilent() {
        var state = PlayState()
        state.openLesson(at: 5)
        playOut(&state)
        for step in [6, 7, 6] {
            state.goToLessonStep(step)
            playOut(&state)
        }
        state.goToLessonStep(5)
        expectSilent(&state, "Back to step 6")
    }

    /// The lesson opened while the person's ring 1 plays, then closed from step 1, or with step 12 reached.
    @Test(arguments: [false, true])
    func openingAndClosingTheLessonDuringAMoveIsSilent(throughTheLastStep: Bool) {
        var state = PlayState()
        state.tap(1)
        _ = state.frame()
        for _ in 0..<72 {
            state.advance(by: Self.frame)
            _ = state.frame()
        }
        state.openLesson(at: 0)
        expectSilent(&state, "opening")
        if throughTheLastStep {
            state.goToLessonStep(11)
            expectSilent(&state, "step 12")
        }
        state.closeLesson()
        expectSilent(&state, "closing")
    }

    /// A ring refused, its "no" heard; then the lesson opened and closed.
    @Test func closingTheLessonDoesNotRepeatARefusal() {
        var state = PlayState()
        state.tap(4)
        #expect(state.hearing.refused == 4)
        state.openLesson(at: 0)
        state.closeLesson()
        expectSilent(&state, "closing")
    }

    /// Starting at a chosen move that has the same start and the same move as the toy now, part way: a jump, not the
    /// move dragged back.
    @Test func aJumpToTheSameMoveIsSilent() {
        var state = PlayState()
        state.tap(1)
        _ = state.frame()
        for _ in 0..<90 { state.advance(by: Self.frame); _ = state.frame() }
        guard let move = state.toy.current else { Issue.record("no move"); return }
        state.begin(at: move)
        expectSilent(&state, "starting at the same move")
    }

    /// Reset hears nothing, on the toy and on the lesson's steps.
    @Test func resetIsSilent() {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<60 { state.advance(by: Self.frame) }
        _ = state.frame()
        state.reset()
        expectSilent(&state, "Reset")
        state.openLesson(at: 3)
        for _ in 0..<60 { state.advance(by: Self.frame) }
        _ = state.frame()
        state.reset()
        expectSilent(&state, "Reset in the lesson")
    }

    /// Between jumps, the toy is heard as ever: a whole move, every event once, and its sword travel.
    @Test func movesAreStillHeard() {
        var state = PlayState()
        state.openLesson(at: 3)
        state.closeLesson()
        state.tap(1)
        let played = playOut(&state)
        let move = state.own.made[0]
        #expect(played.heard.map(\.event) == Score(move).events)
        #expect(abs(played.travel - Score(move).totalSwordTravel) < 1e-9)
    }

    // MARK: - The congratulation on the lesson's last step

    /// Solve on step 12 takes the last ring off: never congratulated, then or on closing.
    @Test func solveOnTheLastStepNeverCongratulates() {
        var state = PlayState(PuzzleSession(resting: PuzzleState("100000000")!))
        state.openLesson(at: 11)
        state.solve()
        let played = playOut(&state)
        #expect(state.toy.state == .allOff)
        #expect(played.congratulated == 0 && !state.isCongratulating)
        state.closeLesson()
        #expect(!state.isCongratulating && !state.congratulates, "the congratulation appears on closing, after Solve")
    }

    /// The person's own tap on step 12 takes the last ring off: congratulated at that moment, and not again on closing.
    @Test func theLastRingTakenOffByHandOnTheLastStepIsCongratulatedThere() {
        var state = PlayState(PuzzleSession(resting: PuzzleState("100000000")!))
        state.openLesson(at: 11)
        state.tap(1)
        let played = playOut(&state)
        #expect(played.congratulated == 1 && state.isCongratulating, "not congratulated when the last ring came off")
        state.closeLesson()
        #expect(!state.isCongratulating && !state.congratulates, "congratulated again on closing")
    }

    /// The lesson opened with every ring off; on step 12 the person puts every ring on and takes them off by hand.
    @Test func openedWithEveryRingOffTheLastStepStillCongratulates() {
        var state = PlayState(PuzzleSession(resting: .allOff))
        state.openLesson(at: 11)
        state.reset()
        #expect(state.toy.state == .allOn)
        var congratulated = 0
        for ring in PuzzleState.allOn.moves(to: .allOff) {
            state.tap(ring)
            congratulated += playOut(&state).congratulated
        }
        #expect(state.toy.state == .allOff)
        #expect(congratulated == 1 && state.isCongratulating)
    }

    /// Arriving at step 12 with every ring off, or closing the lesson, is not a move: it never congratulates.
    @Test func arrivingAndClosingNeverCongratulate() {
        var state = PlayState(PuzzleSession(resting: PuzzleState("100000000")!))
        state.tap(1)
        playOut(&state)
        #expect(state.isCongratulating)
        state.openLesson(at: 0)
        #expect(!state.isCongratulating)
        state.goToLessonStep(11)
        #expect(!state.isCongratulating && !state.congratulates)
        state.closeLesson()
        #expect(!state.isCongratulating && !state.congratulates)
    }

    /// Without the lesson: solving by hand congratulates once, at the last move; Solve does not.
    @Test func ownToyCongratulatesAsBefore() {
        var state = PlayState()
        var congratulated = 0
        for ring in PuzzleState.allOn.moves(to: .allOff).prefix(20) {
            state.tap(ring)
            congratulated += playOut(&state).congratulated
        }
        state.solve()
        congratulated += playOut(&state).congratulated
        #expect(state.toy.state == .allOff && congratulated == 0)
        state.reset()
        state = PlayState(PuzzleSession(resting: PuzzleState("100000000")!))
        state.tap(1)
        #expect(playOut(&state).congratulated == 1)
    }
}
