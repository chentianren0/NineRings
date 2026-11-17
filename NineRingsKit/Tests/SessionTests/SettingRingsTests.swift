import Motion
import Puzzle
import Testing
@testable import Session

/// Setting the rings by hand: any of the 512 arrangements, set silently with no rule, becomes the person's toy on Done,
/// and play, undo and Solve go on from it; Cancel gives the toy back as it was.
@Suite struct SettingRingsTests {
    /// Plays every move in hand to its end, a move at a time.
    private func playOut(_ state: inout PlayState) -> Int {
        var congratulated = 0, count = 0
        while state.toy.isPlaying && count < 10_000 {
            state.advance(by: 1_000)
            if state.congratulates { congratulated += 1 }
            count += 1
        }
        return congratulated
    }

    /// Sets the rings to `chosen` from where the toy is, ring by ring, as the ring buttons do.
    private func set(_ state: inout PlayState, to chosen: PuzzleState) {
        state.startSettingRings()
        for ring in PuzzleState.rings where state.toy.state.isOn(ring) != chosen.isOn(ring) {
            state.tap(ring)
        }
    }

    private func expectSilent(_ state: inout PlayState, _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(state.hearing == Hearing(), "\(what) was heard", sourceLocation: sourceLocation)
        #expect(state.frame() == 0, "\(what): the slide saw the sword travel", sourceLocation: sourceLocation)
    }

    // MARK: - Any arrangement

    @Test func everyArrangementCanBeSetAndRestsWithNoMoveMade() {
        for bits in UInt16(0)..<512 {
            let chosen = PuzzleState(bits: bits)
            var state = PlayState()
            set(&state, to: chosen)
            #expect(state.toy.state == chosen)
            state.finishSettingRings()
            #expect(!state.isSettingRings)
            #expect(state.toy == PuzzleSession(resting: chosen), "\(chosen) is not the toy at rest")
            #expect(!state.toy.canUndo, "\(chosen): undo would go back past the arrangement")
        }
    }

    @Test func aRingTheRuleForbidsGoesOnAndOffWhileSetting() {
        var state = PlayState()
        state.startSettingRings()
        state.tap(9)
        #expect(state.toy.state == PuzzleState("111111110"))
        #expect(state.toy.note == nil)
        state.tap(9)
        #expect(state.toy.state == .allOn)
    }

    @Test func playUndoAndSolveGoOnFromTheArrangement() {
        let chosen = PuzzleState("010110001")!
        var state = PlayState()
        set(&state, to: chosen)
        state.finishSettingRings()

        let ring = chosen.movableRings[0]
        state.tap(ring)
        _ = playOut(&state)
        #expect(state.toy.state == Move(ring: ring, from: chosen)!.to)
        state.undo()
        _ = playOut(&state)
        #expect(state.toy.state == chosen, "undo goes back to the arrangement")
        state.undo()
        #expect(!state.toy.isPlaying, "and no further")

        state.solve()
        var moves = 0
        while state.toy.isPlaying && moves < 600 {
            state.advance(by: 1_000)
            moves += 1
        }
        #expect(state.toy.state == .allOff)
        #expect(state.toy.moveCount == chosen.moves(to: .allOff).count, "Solve takes the shortest way from the arrangement")
    }

    // MARK: - While setting

    @Test func requestsThatMoveTheToyDoNothingWhileSetting() {
        var state = PlayState()
        state.tap(1)
        _ = playOut(&state)
        let own = state.own
        state.startSettingRings()
        state.undo()
        state.solve()
        state.togglePlay()
        state.scrub(to: 0.5)
        state.advance(by: 1)
        state.openLesson()
        #expect(state.lesson == nil)
        #expect(state.toy == PuzzleSession(resting: own.state))
        #expect(state.own == own)
        state.tap(5)
        state.reset()
        #expect(state.toy.state == .allOn, "Reset puts every ring on in the arrangement")
        #expect(state.isSettingRings)
    }

    @Test func theRingsCannotBeSetWhileTheLessonIsOpen() {
        var state = PlayState()
        state.openLesson(at: 11)
        state.startSettingRings()
        #expect(!state.isSettingRings)
    }

    @Test func settingIsSilent() {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 0.3)
        #expect(state.settingRingsStartJumps, "a move part way jumps to rest")
        state.startSettingRings()
        expectSilent(&state, "starting part way")
        state.tap(4)
        expectSilent(&state, "ring 4 off")
        state.tap(4)
        expectSilent(&state, "ring 4 on")
        state.finishSettingRings()
        expectSilent(&state, "Done")
    }

    // MARK: - Cancel

    @Test func cancelGivesTheToyBackAsItWas() {
        var state = PlayState()
        state.tap(1)
        _ = playOut(&state)
        state.tap(3)
        state.advance(by: 0.3)
        let before = state.own
        #expect(before.isPlaying)
        set(&state, to: PuzzleState("000000000")!)
        #expect(state.settingRingsCancelJumps)
        state.cancelSettingRings()
        var paused = before
        paused.pause()
        #expect(state.toy == paused, "the toy comes back where it stopped, its moves kept")
        #expect(state.toy.canUndo)
        #expect(state.narration == Narration([.paused(paused.status)]))
    }

    @Test func cancelWithNothingChangedDoesNotJump() {
        var state = PlayState()
        state.startSettingRings()
        #expect(!state.settingRingsCancelJumps)
        state.tap(2)
        #expect(state.settingRingsCancelJumps)
        state.tap(2)
        #expect(!state.settingRingsCancelJumps)
    }

    // MARK: - What is said

    @Test func startingSaysHowAndDoneSaysWhatTheToyIs() {
        var state = PlayState()
        state.startSettingRings()
        #expect(state.narration == Narration([.settingRings]))
        state.tap(9)
        #expect(state.narration.isEmpty, "the ring's button says its new value")
        state.finishSettingRings()
        #expect(state.narration == Narration([.rested(ToySummary(PuzzleState("111111110")!))]))
    }

    // MARK: - The congratulation

    @Test func takingOffTheLastOfAFewRingsSetByHandDoesNotCongratulate() {
        var state = PlayState()
        set(&state, to: PuzzleState("100000000")!)
        state.finishSettingRings()
        state.tap(1)
        #expect(playOut(&state) == 0, "the person did not take all nine off")
    }

    @Test func everyRingSetOnArmsTheCongratulation() {
        var state = PlayState()
        set(&state, to: PuzzleState("100000000")!)
        state.finishSettingRings()
        #expect(!state.congratulation.isArmed)
        set(&state, to: .allOn)
        state.finishSettingRings()
        #expect(state.congratulation.isArmed)
    }

    @Test func startingHidesTheCongratulation() {
        var state = PlayState()
        for ring in PuzzleState.allOn.moves(to: .allOff) {
            state.tap(ring)
            _ = playOut(&state)
        }
        #expect(state.isCongratulating)
        state.startSettingRings()
        #expect(!state.isCongratulating)
    }

    // MARK: - The commands

    @Test func commandsWhileSetting() {
        let session = PuzzleSession(resting: PuzzleState("110000000")!)
        let commands = ToyCommands(
            markers: session.markers, canUndo: true, canPlay: true, isPlaying: false, canSolve: true, canScrub: true,
            progress: 0.5, stages: [], lessonHoldsToy: false, isSettingRings: true
        )
        #expect(PuzzleState.rings.filter(commands.canMove).isEmpty)
        #expect(!commands.canUndoMove)
        #expect(!commands.canPlayOrPause)
        #expect(!commands.canSolvePuzzle)
        #expect(!commands.canReset)
        #expect(commands.canSetRings, "Done is offered")
        #expect(!commands.canShowLesson)
    }

    @Test func theLessonOpenDisablesSettingTheRings() {
        let session = PuzzleSession()
        let commands = ToyCommands(
            markers: session.markers, canUndo: false, canPlay: false, isPlaying: false, canSolve: true, canScrub: false,
            progress: 0, stages: [], lessonHoldsToy: false, lessonIsOpen: true
        )
        #expect(!commands.canSetRings)
        #expect(commands.canShowLesson)
    }
}
