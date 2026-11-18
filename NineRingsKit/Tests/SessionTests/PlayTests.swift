import Foundation
import Motion
import Puzzle
import Testing
@testable import Session

/// The play in progress and the record of a finished play, as ``PlayState`` keeps them.
@Suite struct PlayTests {
    private let aMove = MoveTiming.baseDuration
    /// Rings 1 and 2 on: two moves before the end, ring 2 off and then ring 1 off.
    private let twoOn = PuzzleState("110000000")!

    /// Plays until nothing is playing, a whole move at a time. Returns the records finished on the way.
    @discardableResult
    private func playOut(_ state: inout PlayState) -> [PlayRecord] {
        var finished: [PlayRecord] = []
        var steps = 0
        while state.toy.isPlaying {
            state.advance(by: 10)
            if let record = state.finished { finished.append(record) }
            steps += 1
            precondition(steps < 10_000, "playing never stopped")
        }
        return finished
    }

    /// Taps each ring of `rings` and plays it out. Returns the records finished on the way.
    @discardableResult
    private func play(_ rings: [Int], on state: inout PlayState) -> [PlayRecord] {
        rings.flatMap { ring in
            state.tap(ring)
            return playOut(&state)
        }
    }

    // MARK: Counting

    @Test func aFreshToyBeginsAPlayWithNothingCounted() throws {
        let before = Date.now
        let state = PlayState()
        let play = try #require(state.play)
        #expect(play.startRings == .allOn)
        #expect(play.moves == 0 && play.undos == 0 && play.movesPlayedForThePerson == 0 && play.secondsSpent == 0)
        #expect(play.startedAt >= before && play.startedAt <= .now)
    }

    @Test func movesAndUndosAreCounted() throws {
        var state = PlayState()
        play([1, 3], on: &state)
        #expect(state.play?.moves == 2)
        state.undo()
        playOut(&state)
        #expect(state.play?.moves == 1)
        #expect(state.play?.undos == 1)
        // Dragging the slider back to the start takes the move back too.
        state.tap(3)
        playOut(&state)
        state.scrub(to: 0)
        #expect(state.play?.moves == 1)
        #expect(state.play?.undos == 2)
    }

    @Test func aMoveStoppedPartWayIsNotCountedUntilItEnds() {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 0.5 * aMove)
        state.pause()
        #expect(state.play?.moves == 0)
        state.togglePlay()
        playOut(&state)
        #expect(state.play?.moves == 1)
    }

    @Test func comingBackToEveryRingOnBeginsANewPlay() throws {
        var state = PlayState()
        let first = try #require(state.play?.id)
        play([1], on: &state)
        state.undo()
        playOut(&state)
        let play = try #require(state.play)
        #expect(play.id != first)
        #expect(play.moves == 0 && play.undos == 0)
    }

    @Test func resetBeginsANewPlay() throws {
        var state = PlayState()
        let first = try #require(state.play?.id)
        play([1, 3], on: &state)
        state.reset()
        let play = try #require(state.play)
        #expect(play.id != first)
        #expect(play.moves == 0)
    }

    @Test func settingTheRingsBeginsANewPlayOnlyWithEveryRingOn() throws {
        var state = PlayState()
        play([1], on: &state)
        state.startSettingRings()
        state.setRings(to: .allOn)
        state.finishSettingRings()
        let play = try #require(state.play)
        #expect(play.moves == 0 && play.startRings == .allOn)

        state.startSettingRings()
        state.setRings(to: twoOn)
        state.finishSettingRings()
        #expect(state.play == nil, "taking the last ring off from here is not taking all nine off")
        #expect(!state.congratulation.isArmed)
    }

    @Test func movesSolveMakesArePlayedForThePerson() {
        var state = PlayState()
        state.solve()
        state.advance(by: 10)
        state.advance(by: 10)
        #expect(state.play?.movesPlayedForThePerson == 2)
        #expect(state.play?.moves == 2)
    }

    @Test func spentTimeIsAddedToThePlay() {
        var state = PlayState()
        state.spend(5)
        state.spend(2.5)
        state.spend(-1)
        #expect(state.play?.secondsSpent == 7.5)
    }

    // MARK: Finishing

    /// The shortest way by hand, one tap at a time: one record, at the moment the congratulation is due.
    @Test func theShortestWayByHandLeavesOneRecord() throws {
        var state = PlayState()
        let id = try #require(state.play?.id)
        state.spend(60)
        let records = play(PuzzleState.allOn.moves(to: .allOff), on: &state)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.playID == id)
        #expect(record.startRings == .allOn && record.endRings == .allOff)
        #expect(record.moves == 341 && record.undos == 0 && record.movesPlayedForThePerson == 0)
        #expect(record.secondsSpent == 60)
        #expect(record.finishedAt >= record.startedAt)
        #expect(record.isShortestWay)
        #expect(state.isCongratulating)
        #expect(state.play == nil, "no play until every ring is on again")
        state.dismissCongratulation()
        state.tap(1)
        #expect(state.finished == nil, "the record belongs to the change that congratulated")
    }

    @Test func aPlayFinishedAfterSolveTookPartIsNotTheShortestWay() throws {
        var state = PlayState()
        play(Array(PuzzleState.allOn.moves(to: twoOn)), on: &state)
        // Solve begins ring 2 off; a tap on ring 1 takes over, and the person takes the last ring off.
        state.solve()
        state.tap(1)
        let record = try #require(playOut(&state).first)
        #expect(record.moves == 341)
        #expect(record.movesPlayedForThePerson == 1)
        #expect(!record.isShortestWay)
    }

    @Test func aPlayWithAnUndoIsNotTheShortestWay() throws {
        var state = PlayState()
        play([1, 3], on: &state)
        state.undo()
        playOut(&state)
        let record = try #require(play(state.toy.state.moves(to: .allOff), on: &state).first)
        #expect(record.moves == 341 && record.undos == 1)
        #expect(!record.isShortestWay)
    }

    @Test func solveTakingTheLastRingOffEndsThePlayUnrecorded() {
        var state = PlayState()
        play(Array(PuzzleState.allOn.moves(to: twoOn)), on: &state)
        state.solve()
        #expect(playOut(&state).isEmpty)
        #expect(state.toy.state == .allOff)
        #expect(state.play == nil)
    }

    /// Where the lesson gives the toy back from every ring on, its six moves are made on it, played for the person.
    @Test func theLessonsMovesArePlayedForThePerson() throws {
        var state = PlayState()
        state.openLesson(at: Lesson.steps.count - 1)
        let given = try #require(state.lesson?.movesPlayedForThePerson)
        #expect(given.count == 6)
        #expect(state.play?.moves == 6 && state.play?.movesPlayedForThePerson == 6)
        let records = play(state.toy.state.moves(to: .allOff), on: &state)
        let record = try #require(records.first)
        #expect(record.moves == 341 && record.movesPlayedForThePerson == 6)
        #expect(!record.isShortestWay)
    }

    @Test func goingBackToTheLastStepDoesNotCountTheLessonsMovesTwice() {
        var state = PlayState()
        state.openLesson(at: Lesson.steps.count - 1)
        state.goToLessonStep(0)
        state.goToLessonStep(Lesson.steps.count - 1)
        state.closeLesson()
        #expect(state.play?.movesPlayedForThePerson == 6)
        #expect(state.play?.moves == 6)
    }

    // MARK: The rule

    @Test func theShortestWayIsTheDistanceWithNoUndoAndNothingPlayedForThePerson() {
        #expect(PlayRecord.isShortestWay(from: .allOn, to: .allOff, moves: 341, undos: 0, movesPlayedForThePerson: 0))
        #expect(!PlayRecord.isShortestWay(from: .allOn, to: .allOff, moves: 343, undos: 0, movesPlayedForThePerson: 0))
        #expect(!PlayRecord.isShortestWay(from: .allOn, to: .allOff, moves: 341, undos: 1, movesPlayedForThePerson: 0))
        #expect(!PlayRecord.isShortestWay(from: .allOn, to: .allOff, moves: 341, undos: 0, movesPlayedForThePerson: 1))
        #expect(PlayRecord.isShortestWay(from: twoOn, to: .allOff, moves: 2, undos: 0, movesPlayedForThePerson: 0))
    }
}
