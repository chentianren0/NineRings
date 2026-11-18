import Foundation
import Motion
import Puzzle
import Testing
@testable import Session

/// The toy kept between launches: what it keeps, and what it brings back.
@Suite struct ToySnapshotTests {
    private let aMove = MoveTiming.baseDuration

    private func playOut(_ session: inout PuzzleSession) {
        while session.isPlaying { session.advance(by: 10) }
    }

    /// The session `snapshot` brings back after a trip through JSON.
    private func roundTrip(_ session: PuzzleSession, play: Play? = nil) throws -> PuzzleSession {
        let data = try ToySnapshot(toy: session, play: play).encoded()
        let snapshot = try #require(ToySnapshot(data: data, format: ToySnapshot.format))
        return try #require(snapshot.toy)
    }

    /// Whether `restored` is `session` as far as the screen and undo can tell, at rest.
    private func expectSame(_ restored: PuzzleSession, _ session: PuzzleSession, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(restored.start == session.start, sourceLocation: sourceLocation)
        #expect(restored.made == session.made, sourceLocation: sourceLocation)
        #expect(restored.current == session.current, sourceLocation: sourceLocation)
        #expect(restored.progress == session.progress, sourceLocation: sourceLocation)
        #expect(restored.direction == session.direction, sourceLocation: sourceLocation)
        #expect(restored.pose == session.pose, sourceLocation: sourceLocation)
        #expect(!restored.isPlaying, sourceLocation: sourceLocation)
    }

    @Test func aFreshToyComesBack() throws {
        expectSame(try roundTrip(PuzzleSession()), PuzzleSession())
    }

    @Test func movesComeBackSoThatUndoStillWorks() throws {
        var session = PuzzleSession()
        for ring in [1, 3, 1] {
            session.tap(ring)
            playOut(&session)
        }
        var restored = try roundTrip(session)
        expectSame(restored, session)
        restored.undo()
        playOut(&restored)
        #expect(restored.state == PuzzleState.allOn.moving(1).moving(3))
        #expect(restored.moveCount == 2)
    }

    @Test func aMovePlayingComesBackStoppedWhereItWas() throws {
        var session = PuzzleSession()
        session.tap(2)
        session.advance(by: 0.4 * aMove)
        var restored = try roundTrip(session)
        session.pause()
        expectSame(restored, session)
        #expect(restored.isPartWay)
        restored.togglePlay()
        playOut(&restored)
        #expect(restored.state == PuzzleState.allOn.moving(2))
        #expect(restored.moveCount == 1)
    }

    @Test func aMoveStoppedOnItsWayBackComesBackSo() throws {
        var session = PuzzleSession()
        session.tap(1)
        playOut(&session)
        session.undo()
        session.advance(by: 0.3 * aMove)
        session.pause()
        var restored = try roundTrip(session)
        expectSame(restored, session)
        #expect(restored.moveCount == 1, "the move is still made until it is all the way back")
        // A tap on its ring carries it on the way it was going.
        restored.tap(1)
        playOut(&restored)
        #expect(restored.state == .allOn)
        #expect(restored.moveCount == 0)
    }

    @Test func aMoveTakenBackComesBackAtTheSlidersStart() throws {
        var session = PuzzleSession()
        for ring in [1, 3] {
            session.tap(ring)
            playOut(&session)
        }
        session.undo()
        playOut(&session)
        expectSame(try roundTrip(session), session)
    }

    @Test func aSessionBegunAtAChosenMoveComesBack() throws {
        let session = PuzzleSession(at: MoveMotion.written[4], progress: 0.6)
        expectSame(try roundTrip(session), session)
    }

    @Test func thePlayComesBackWhole() throws {
        var play = Play(startedAt: Date(timeIntervalSince1970: 1_000_000), startRings: .allOn)
        play.moves = 12
        play.undos = 3
        play.movesPlayedForThePerson = 6
        play.secondsSpent = 81.25
        let data = try ToySnapshot(toy: PuzzleSession(), play: play).encoded()
        #expect(ToySnapshot(data: data, format: 1)?.play == play)
    }

    /// Past the most moves kept, the oldest are folded into the start: undo goes back that far.
    @Test func theOldestMovesAreFoldedIntoTheStart() throws {
        var session = PuzzleSession()
        let count = ToySnapshot.movesKept + 3
        for _ in 0..<count {
            session.tap(1)
            playOut(&session)
        }
        let snapshot = ToySnapshot(toy: session, play: nil)
        #expect(snapshot.moves.count == ToySnapshot.movesKept)
        let restored = try #require(snapshot.toy)
        #expect(restored.state == session.state)
        #expect(restored.moveCount == ToySnapshot.movesKept)
        #expect(restored.start == session.made[2].to)
    }

    @Test func aSnapshotThatBreaksTheRuleBringsNothingBack() throws {
        let json = #"{"start":"111111111","moves":[1,5]}"#
        let snapshot = try #require(ToySnapshot(data: Data(json.utf8), format: 1))
        #expect(snapshot.toy == nil)
        #expect(PlayState(snapshot) == nil)
    }

    @Test func anotherFormatIsSkipped() throws {
        let data = try ToySnapshot(toy: PuzzleSession(), play: nil).encoded()
        #expect(ToySnapshot(data: data, format: 2) == nil)
        #expect(ToySnapshot(data: Data("not json".utf8), format: 1) == nil)
    }

    /// Format 1 as it is written, so that a later build still reads what this one kept.
    @Test func formatOneReadsAsWritten() throws {
        let json = """
            {"moves":[1,3],"play":{"id":"8F5C7A55-5D7B-4C55-9C35-0E2B4B5D7E11","moves":2,"movesPlayedForThePerson":0,\
            "secondsSpent":12.5,"startRings":"111111111","startedAt":1000000,"undos":0},\
            "slider":{"isMade":false,"isUndoing":false,"progress":0.25,"ring":1},"start":"111111111"}
            """
        let snapshot = try #require(ToySnapshot(data: Data(json.utf8), format: 1))
        let toy = try #require(snapshot.toy)
        #expect(toy.made.map(\.ring) == [1, 3])
        #expect(toy.current == Move(ring: 1, from: PuzzleState.allOn.moving(1).moving(3)))
        #expect(toy.progress == 0.25)
        #expect(snapshot.play?.secondsSpent == 12.5)
        #expect(snapshot.play?.startedAt == Date(timeIntervalSinceReferenceDate: 1_000_000))
        #expect(try snapshot.encoded() == Data(json.replacingOccurrences(of: "\n", with: "").utf8))
    }

    // MARK: Through the play state

    /// What is kept is the person's own toy, as closing the lesson would give it back, with the play in progress.
    @Test func theLessonsToyIsNotKept() throws {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 10)
        state.openLesson(at: 3)
        state.advance(by: 0.5)
        let restored = try #require(PlayState(state.snapshot))
        #expect(restored.lesson == nil)
        #expect(restored.own.state == PuzzleState.allOn.moving(1))
        #expect(restored.play == state.play)
    }

    @Test func aKeptPlayArmsTheCongratulation() throws {
        var state = PlayState()
        state.spend(4)
        let restored = try #require(PlayState(state.snapshot))
        #expect(restored.play == state.play)
        #expect(restored.congratulation.isArmed)

        state.startSettingRings()
        state.setRings(to: PuzzleState("110000000")!)
        state.finishSettingRings()
        let unarmed = try #require(PlayState(state.snapshot))
        #expect(unarmed.play == nil)
        #expect(!unarmed.congratulation.isArmed)
    }
}
