import Motion
import Puzzle
import Testing
@testable import Session

/// The checks are written so that they stay true as more moves are written: where a test needs a move that is
/// not written yet, it looks for one, and is skipped, saying so, when there is none left.
@Suite struct PuzzleSessionTests {
    private let ringOneOff = PuzzleState.allOn.moving(1)
    private let ringTwoOff = PuzzleState.allOn.moving(2)

    /// Plays until nothing is playing, a whole move at a time.
    private func playOut(_ session: inout PuzzleSession) {
        var steps = 0
        while session.isPlaying {
            session.advance(by: 1)
            steps += 1
            precondition(steps < 1000, "playing never stopped")
        }
    }

    // MARK: Starting out

    @Test func beginsWithEveryRingOnAndNothingMade() {
        let session = PuzzleSession()
        #expect(session.state == .allOn)
        #expect(session.moveCount == 0)
        #expect(session.current == nil)
        #expect(!session.isPlaying)
        #expect(!session.canPlay)
        #expect(!session.canUndo)
        #expect(session.canSolve)
        #expect(session.status == .resting(.allOn))
        #expect(session.pose != nil)
        #expect(session.stages.isEmpty)
    }

    @Test func markersFollowTheRule() {
        let session = PuzzleSession()
        let markers = session.markers
        #expect(markers.map(\.ring) == Array(1...9))
        #expect(markers.allSatisfy { $0.isOn })
        #expect(markers.filter { $0.canMove }.map(\.ring) == [1, 2])
        // Ring 1 off and ring 2 off from every ring on are written.
        #expect(markers[0].isWritten && markers[1].isWritten)
        #expect(markers[2].block == .earlierRingOn(1))
        #expect(markers[8].block == .earlierRingOn(7))
        #expect(markers.dropFirst(2).allSatisfy { !$0.isWritten })
    }

    // MARK: Tapping

    @Test func ringOnePlaysAndTheStateChangesWhenItEnds() {
        var session = PuzzleSession()
        session.tap(1)
        #expect(session.isPlaying)
        #expect(session.current == Move(ring: 1, from: .allOn))
        #expect(session.markers[0].isMoving)
        session.advance(by: 0.5)
        #expect(session.progress == 0.5)
        #expect(session.state == .allOn, "the state changes only when the move ends")
        #expect(session.moveCount == 0)
        if case .playing(let move, let stage, let undoing) = session.status {
            #expect(move.ring == 1 && move.takesOff && !undoing)
            #expect(stage == MoveMotion(move)!.stage(at: 0.5))
        } else {
            Issue.record("expected a playing status, got \(session.status)")
        }
        session.advance(by: 0.6)
        #expect(session.progress == 1)
        #expect(!session.isPlaying)
        #expect(session.state == ringOneOff)
        #expect(session.moveCount == 1)
        #expect(session.status == .resting(ringOneOff))
        #expect(session.markers[0].isOn == false)
    }

    @Test func ringTwoPlaysFromEveryRingOn() {
        var session = PuzzleSession()
        session.tap(2)
        #expect(session.isPlaying)
        playOut(&session)
        #expect(session.state == ringTwoOff)
        #expect(session.moveCount == 1)
    }

    @Test func aRingCanGoBackOnByTappingItAgain() {
        var session = PuzzleSession()
        session.tap(1)
        playOut(&session)
        session.tap(1)
        #expect(session.current == Move(ring: 1, from: ringOneOff))
        playOut(&session)
        #expect(session.state == .allOn)
        #expect(session.moveCount == 2)
    }

    @Test func aRingWithAnEarlierRingOnIsBlockedByTheNearestOne() {
        var session = PuzzleSession()
        session.tap(5)
        #expect(!session.isPlaying)
        #expect(session.current == nil)
        #expect(session.note == .blocked(ring: 5, block: .earlierRingOn(3)))
        #expect(session.status == .note(.blocked(ring: 5, block: .earlierRingOn(3))))
        let markers = session.markers
        #expect(markers[4].isRefused)
        #expect(markers[2].isBlocking)
        #expect(markers.filter { $0.isBlocking }.count == 1)
        #expect(markers.filter { $0.isRefused }.count == 1)
    }

    @Test func aRingWhosePreviousRingIsOffIsBlockedByIt() {
        var session = PuzzleSession()
        session.tap(1)
        playOut(&session)
        session.tap(2)
        #expect(session.note == .blocked(ring: 2, block: .previousRingOff(1)))
        #expect(session.markers[0].isBlocking)
        #expect(session.state == ringOneOff)
        #expect(session.current == Move(ring: 1, from: .allOn), "the slider keeps the move played last")
    }

    @Test func theNextThingClearsTheNote() {
        var session = PuzzleSession()
        session.tap(4)
        #expect(session.note != nil)
        session.tap(1)
        #expect(session.note == nil)
        #expect(session.markers.allSatisfy { !$0.isBlocking && !$0.isRefused })
    }

    @Test(.enabled(if: UnwrittenMove.nearest() != nil, "every move reachable from every ring on is written"))
    func aLegalMoveThatIsNotWrittenDoesNotPlay() throws {
        let found = try #require(UnwrittenMove.nearest(), "every move reachable from every ring on is written")
        var session = PuzzleSession()
        for ring in found.path {
            session.tap(ring)
            playOut(&session)
        }
        #expect(session.state == found.move.from)
        let countBefore = session.moveCount
        let currentBefore = session.current
        session.tap(found.move.ring)
        #expect(!session.isPlaying)
        #expect(session.note == .notWritten(found.move, whileSolving: false))
        #expect(session.moveCount == countBefore)
        #expect(session.current == currentBefore)
        #expect(session.markers[found.move.ring - 1].canMove)
        #expect(!session.markers[found.move.ring - 1].isWritten)
    }

    // MARK: Taps while a move plays

    @Test func aTapWhileAMovePlaysWaitsItsTurn() {
        var session = PuzzleSession()
        session.tap(1)
        session.advance(by: 0.3)
        session.tap(1)
        #expect(session.queue == [1])
        #expect(session.current == Move(ring: 1, from: .allOn), "the move in hand goes on")
        session.advance(by: 1)
        #expect(session.state == ringOneOff)
        #expect(session.current == Move(ring: 1, from: ringOneOff), "then the waiting ring begins")
        #expect(session.isPlaying)
        playOut(&session)
        #expect(session.state == .allOn)
        #expect(session.moveCount == 2)
    }

    @Test func aWaitingTapIsJudgedWhenItsTurnComes() {
        var session = PuzzleSession()
        session.tap(1)
        // Ring 2 can move now, but not once ring 1 is off.
        session.tap(2)
        playOut(&session)
        #expect(session.state == ringOneOff)
        #expect(session.queue.isEmpty)
        #expect(session.note == .blocked(ring: 2, block: .previousRingOff(1)))
    }

    @Test func aRefusedTapStopsTheRestOfTheQueue() {
        var session = PuzzleSession()
        session.tap(1)
        session.tap(5)
        session.tap(1)
        playOut(&session)
        #expect(session.state == ringOneOff)
        #expect(session.queue.isEmpty)
        #expect(session.note == .blocked(ring: 5, block: .earlierRingOn(3)))
    }

    @Test func aTapWhilePausedPartWayCarriesOn() {
        var session = PuzzleSession()
        session.tap(2)
        session.advance(by: 0.4)
        session.togglePlay()
        #expect(!session.isPlaying)
        if case .paused(let move, _, false) = session.status {
            #expect(move.ring == 2)
        } else {
            Issue.record("expected a paused status, got \(session.status)")
        }
        session.tap(2)
        #expect(session.isPlaying)
        #expect(session.queue == [2])
        playOut(&session)
        #expect(session.state == .allOn)
    }

    // MARK: Play, pause and the slider

    @Test func pauseAndPlayCarryOn() {
        var session = PuzzleSession()
        session.tap(1)
        session.advance(by: 0.25)
        session.togglePlay()
        session.advance(by: 0.5)
        #expect(session.progress == 0.25, "nothing moves while paused")
        #expect(session.canPlay)
        session.togglePlay()
        session.advance(by: 0.5)
        #expect(session.progress == 0.75)
    }

    @Test func playIsNotOfferedWithNothingToPlay() {
        var session = PuzzleSession()
        session.tap(1)
        playOut(&session)
        #expect(!session.canPlay)
        session.togglePlay()
        #expect(!session.isPlaying)
    }

    @Test func scrubbingToEitherEndMakesOrUnmakesTheMove() {
        var session = PuzzleSession()
        session.tap(1)
        session.advance(by: 0.5)
        session.scrub(to: 0.2)
        #expect(!session.isPlaying)
        #expect(session.state == .allOn)
        session.scrub(to: 1)
        #expect(session.state == ringOneOff)
        #expect(session.moveCount == 1)
        session.scrub(to: 0.6)
        #expect(session.state == ringOneOff, "the state is where the slider last reached an end")
        session.scrub(to: 0)
        #expect(session.state == .allOn)
        #expect(session.moveCount == 0)
        // From the beginning, play runs the move forward again.
        #expect(session.canPlay)
        session.togglePlay()
        playOut(&session)
        #expect(session.state == ringOneOff)
    }

    @Test func scrubbingDoesNothingBeforeTheFirstMove() {
        var session = PuzzleSession()
        session.scrub(to: 0.5)
        #expect(session.progress == 0)
        #expect(session.current == nil)
    }

    // MARK: Undo and reset

    @Test func undoPlaysTheLastMoveBackwards() {
        var session = PuzzleSession()
        session.tap(1)
        playOut(&session)
        #expect(session.canUndo)
        session.undo()
        #expect(session.isPlaying)
        #expect(session.direction == .backward)
        session.advance(by: 0.3)
        #expect(abs(session.progress - 0.7) < 1e-12)
        #expect(session.state == ringOneOff, "the state changes back only when the move has run back")
        if case .playing(let move, let stage, let undoing) = session.status {
            #expect(undoing)
            #expect(move == Move(ring: 1, from: ringOneOff), "the ring is going back on")
            #expect(stage == MoveMotion(move)!.stage(at: 0.3))
        } else {
            Issue.record("expected a playing status, got \(session.status)")
        }
        #expect(!session.canUndo, "undo is not offered while undoing")
        playOut(&session)
        #expect(session.progress == 0)
        #expect(session.state == .allOn)
        #expect(session.moveCount == 0)
        #expect(session.current == Move(ring: 1, from: .allOn), "the slider keeps the move, to drag forward again")
        #expect(!session.canUndo)
    }

    @Test func undoAgainTakesTheMoveBeforeIt() {
        var session = PuzzleSession()
        session.tap(1)
        playOut(&session)
        session.tap(1)
        playOut(&session)
        session.undo()
        playOut(&session)
        #expect(session.state == ringOneOff)
        session.undo()
        #expect(session.current == Move(ring: 1, from: .allOn))
        #expect(session.progress == 1, "the move before starts back from its end, where the toy already is")
        playOut(&session)
        #expect(session.state == .allOn)
        #expect(session.moveCount == 0)
    }

    @Test func undoPartWayTurnsTheMoveBack() {
        var session = PuzzleSession()
        session.tap(2)
        session.advance(by: 0.4)
        session.undo()
        session.advance(by: 0.1)
        #expect(abs(session.progress - 0.3) < 1e-12)
        playOut(&session)
        #expect(session.state == .allOn)
        #expect(session.moveCount == 0)
    }

    @Test func undoDropsTheQueue() {
        var session = PuzzleSession()
        session.tap(1)
        session.tap(1)
        session.undo()
        #expect(session.queue.isEmpty)
        playOut(&session)
        #expect(session.state == .allOn)
    }

    @Test func resetReturnsToEveryRingOn() {
        var session = PuzzleSession()
        session.tap(2)
        playOut(&session)
        session.tap(1)
        session.reset()
        #expect(session == PuzzleSession())
    }

    // MARK: Solve

    @Test func solvePlaysTheShortestWayAndStopsAtAMoveNotWritten() throws {
        var session = PuzzleSession()
        session.solve()
        #expect(session.isSolving)
        playOut(&session)

        // What solving should have done: the shortest way, as far as it is written.
        let path = PuzzleState.allOn.moves(to: .allOff)
        var state = PuzzleState.allOn
        var played = 0
        var unwritten: Move?
        for ring in path {
            let move = try #require(Move(ring: ring, from: state))
            guard MoveMotion(move) != nil else {
                unwritten = move
                break
            }
            state = move.to
            played += 1
        }
        #expect(session.state == state)
        #expect(session.moveCount == played)
        #expect(!session.isSolving)
        #expect(session.queue.isEmpty)
        if let unwritten {
            #expect(session.note == .notWritten(unwritten, whileSolving: true))
        } else {
            #expect(session.state == .allOff)
        }
    }

    @Test func solveStartsAfterTheMoveInHand() {
        var session = PuzzleSession()
        session.tap(2)
        session.advance(by: 0.5)
        session.solve()
        #expect(session.current?.ring == 2, "the move in hand goes on")
        #expect(session.queue == ringTwoOff.moves(to: .allOff))
    }

    @Test func aTapWhileSolvingTakesOver() {
        var session = PuzzleSession()
        session.solve()
        session.tap(1)
        #expect(!session.isSolving)
        #expect(session.queue == [1])
    }

    // MARK: Beginning at a chosen move

    @Test func aSessionCanBeginAtAWrittenMove() throws {
        for move in MoveMotion.written {
            let session = PuzzleSession(at: move, progress: 0.5)
            #expect(session.start == move.from)
            #expect(session.current == move)
            #expect(session.progress == 0.5)
            #expect(!session.isPlaying)
            #expect(session.canPlay)
            #expect(session.stages == MoveMotion(move)!.stages)
            #expect(session.pose != nil)
        }
        let atEnd = PuzzleSession(at: try #require(MoveMotion.written.first), progress: 1)
        #expect(atEnd.moveCount == 1)
    }
}

/// The nearest legal move that is not written, among the states that written moves reach from every ring on,
/// and the rings to tap to get there.
private enum UnwrittenMove {
    static func nearest() -> (move: Move, path: [Int])? {
        var paths: [PuzzleState: [Int]] = [.allOn: []]
        var frontier: [PuzzleState] = [.allOn]
        while !frontier.isEmpty {
            var next: [PuzzleState] = []
            for state in frontier {
                for ring in state.movableRings {
                    guard let move = Move(ring: ring, from: state) else { continue }
                    if MoveMotion(move) == nil { return (move, paths[state]!) }
                    if paths[move.to] == nil {
                        paths[move.to] = paths[state]! + [ring]
                        next.append(move.to)
                    }
                }
            }
            frontier = next
        }
        return nil
    }
}
