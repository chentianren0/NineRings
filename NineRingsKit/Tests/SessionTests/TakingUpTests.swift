import Foundation
import Motion
import Puzzle
import Testing
@testable import Session

/// Taking up the toy another installation of the app left: a jump that brings that play here whole, and the moments when
/// a toy may be replaced without the person asking.
@Suite struct TakingUpTests {
    /// Rings 1 and 2 on: two moves before every ring is off.
    private let twoOn = PuzzleState("110000000")!

    private func playOut(_ state: inout PlayState) {
        var steps = 0
        while state.toy.isPlaying {
            state.advance(by: 10)
            steps += 1
            precondition(steps < 10_000, "playing never stopped")
        }
    }

    private func play(_ rings: [Int], on state: inout PlayState) {
        for ring in rings {
            state.tap(ring)
            playOut(&state)
        }
    }

    /// The toy another installation left: three moves into a play, with time spent and a journey under way.
    private func otherToy() throws -> ToySnapshot {
        var there = PlayState()
        play([1, 3, 1], on: &there)
        there.spend(42)
        return there.snapshot
    }

    // MARK: Taking up

    @Test func theToyTakenUpIsThePlayAsItWasLeft() throws {
        let snapshot = try otherToy()
        var here = PlayState()
        play([2], on: &here)
        let taken = here.takeUp(snapshot)
        #expect(taken)
        #expect(here.own.state == snapshot.toy?.state)
        #expect(here.own.made == snapshot.toy?.made, "undo goes back through the other's moves")
        #expect(here.play == snapshot.play, "the same play, its id, counts and time")
        #expect(here.snapshot == snapshot, "kept again, it is the toy taken up")
        #expect(here.snapshot.isSameToy(as: snapshot))
    }

    /// A play taken up at every ring on, from a toy that was not, keeps its id: no new play begins.
    @Test func aPlayTakenUpAtEveryRingOnKeepsItsID() throws {
        let fresh = PlayState().snapshot
        var here = PlayState()
        play([1, 3], on: &here)
        here.takeUp(fresh)
        #expect(here.play?.id == fresh.play?.id)
        #expect(here.snapshot == fresh)
    }

    /// A jump: nothing heard, the screen shows the parts changing place, and VoiceOver hears where the toy now rests.
    @Test func takingUpIsAJumpThatSaysWhereTheToyRests() throws {
        let snapshot = try otherToy()
        var here = PlayState()
        let jumps = here.jumps
        here.takeUp(snapshot)
        #expect(here.hearing.events.isEmpty)
        let travel = here.frame()
        #expect(travel == 0, "no travel of the sword across a jump")
        #expect(here.jumps == jumps + 1)
        #expect(here.narration == Narration([.rested(ToySummary(here.own.state))]))
        #expect(here.finished == nil && here.earned.isEmpty)
    }

    /// The play taken up goes on as it would have where it was left: finished here, it is that play's record.
    @Test func thePlayTakenUpFinishesHere() throws {
        var there = PlayState(PuzzleSession(resting: twoOn))
        let id = try #require(there.play?.id)
        there.spend(30)
        var here = PlayState()
        here.takeUp(there.snapshot)
        var records: [PlayRecord] = []
        for ring in [2, 1] {
            here.tap(ring)
            while here.toy.isPlaying {
                here.advance(by: 10)
                if let record = here.finished { records.append(record) }
            }
        }
        #expect(records.map(\.playID) == [id])
        #expect(records.first?.moves == 2 && records.first?.secondsSpent == 30)
        #expect(here.isCongratulating)
    }

    /// A finished play's toy, with no play in progress, is taken up as finished: no congratulation is armed until every
    /// ring is on again.
    @Test func aToyWithNoPlayInProgressIsTakenUpSo() throws {
        var there = PlayState(PuzzleSession(resting: twoOn))
        play([2, 1], on: &there)
        #expect(there.play == nil)
        var here = PlayState()
        here.takeUp(there.snapshot)
        #expect(here.play == nil)
        #expect(!here.congratulation.isArmed && !here.isCongratulating)
    }

    @Test func takingUpClosesTheLessonAndTheRingsBeingSet() throws {
        let snapshot = try otherToy()
        var inLesson = PlayState()
        inLesson.openLesson(at: 2)
        inLesson.takeUp(snapshot)
        #expect(inLesson.lesson == nil)
        #expect(inLesson.toy.state == snapshot.toy?.state)

        var setting = PlayState()
        setting.startSettingRings()
        setting.setRings(to: twoOn)
        setting.takeUp(snapshot)
        #expect(!setting.isSettingRings)
        #expect(setting.toy.state == snapshot.toy?.state)
    }

    /// A snapshot whose moves break the rule changes nothing.
    @Test func aToyThatBreaksTheRuleIsNotTakenUp() throws {
        let broken = Data(#"{"isSolving":false,"journeys":[],"moves":[9],"queue":[],"start":"111111111"}"#.utf8)
        let snapshot = try #require(ToySnapshot(data: broken, format: ToySnapshot.format))
        #expect(snapshot.toy == nil)
        var here = PlayState()
        play([1], on: &here)
        let before = here
        let taken = here.takeUp(snapshot)
        #expect(!taken)
        #expect(here.own == before.own && here.play == before.play && here.jumps == before.jumps)
    }

    // MARK: When a toy may be replaced

    @Test func aToyIsCalmOnlyAtRestWithNothingOpen() {
        var state = PlayState()
        #expect(state.isCalm)
        state.tap(1)
        #expect(!state.isCalm, "a move is playing")
        playOut(&state)
        #expect(state.isCalm)

        state.openLesson()
        #expect(!state.isCalm, "the lesson is open")
        state.closeLesson()
        #expect(state.isCalm)

        state.startSettingRings()
        #expect(!state.isCalm, "the rings are being set")
        state.cancelSettingRings()
        #expect(state.isCalm)

        var finishing = PlayState(PuzzleSession(resting: twoOn))
        play([2, 1], on: &finishing)
        #expect(finishing.isCongratulating)
        #expect(!finishing.isCalm, "the congratulation shows")
        finishing.dismissCongratulation()
        #expect(finishing.isCalm)
    }

    /// A move stopped part way is at rest: the person has stopped it, and nothing is moving.
    @Test func aMoveStoppedPartWayIsCalm() {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 0.1)
        state.pause()
        #expect(state.toy.isPartWay)
        #expect(state.isCalm)
    }

    // MARK: A toy nobody has touched

    @Test func aFirstLaunchsToyIsUntouched() {
        var state = PlayState()
        #expect(state.snapshot.isUntouched)
        state.spend(100)
        #expect(state.snapshot.isUntouched, "looking at the toy does not touch it")
    }

    @Test func aMoveMadeOrInHandTouchesTheToy() {
        var moving = PlayState()
        moving.tap(1)
        #expect(!moving.snapshot.isUntouched, "a move in hand")
        playOut(&moving)
        #expect(!moving.snapshot.isUntouched, "a move made")

        let elsewhere = PlayState(PuzzleSession(resting: twoOn))
        #expect(!elsewhere.snapshot.isUntouched, "not every ring on")
    }
}
