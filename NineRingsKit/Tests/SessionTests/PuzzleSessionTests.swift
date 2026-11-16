import Motion
import Puzzle
import Testing
@testable import Session
import Toy
import simd

@Suite struct PuzzleSessionTests {
    /// How long ring 1's move and ring 2's take at full speed; both go evenly, so a fraction of it is that fraction of
    /// the move.
    private let aMove = MoveTiming.baseDuration
    private let ringOneOff = PuzzleState.allOn.moving(1)
    private let ringTwoOff = PuzzleState.allOn.moving(2)

    /// Plays until nothing is playing, a whole move at a time.
    private func playOut(_ session: inout PuzzleSession) {
        var steps = 0
        while session.isPlaying {
            // Longer than any move takes, so that each step ends the move in hand.
            session.advance(by: 10)
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
        #expect(session.stages.isEmpty)
    }

    @Test func markersFollowTheRule() {
        let session = PuzzleSession()
        let markers = session.markers
        #expect(markers.map(\.ring) == Array(1...9))
        #expect(markers.allSatisfy { $0.isOn })
        #expect(markers.filter { $0.canMove }.map(\.ring) == [1, 2])
        #expect(markers[2].block == .earlierRingOn(1))
        #expect(markers[8].block == .earlierRingOn(7))
    }

    // MARK: Tapping

    @Test func ringOnePlaysAndTheStateChangesWhenItEnds() {
        var session = PuzzleSession()
        session.tap(1)
        #expect(session.isPlaying)
        #expect(session.current == Move(ring: 1, from: .allOn))
        #expect(session.markers[0].isMoving)
        session.advance(by: 0.5 * aMove)
        #expect(session.progress == 0.5)
        #expect(session.state == .allOn, "the state changes only when the move ends")
        #expect(session.moveCount == 0)
        if case .playing(let move, let stage, let undoing) = session.status {
            #expect(move.ring == 1 && move.takesOff && !undoing)
            #expect(stage == MoveMotion(move).stage(at: 0.5))
        } else {
            Issue.record("expected a playing status, got \(session.status)")
        }
        session.advance(by: 0.6 * aMove)
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

    // MARK: Taps while a move plays

    @Test func aTapWhileAMovePlaysWaitsItsTurn() {
        var session = PuzzleSession()
        session.tap(1)
        session.advance(by: 0.3 * aMove)
        session.tap(1)
        #expect(session.queue == [1])
        #expect(session.current == Move(ring: 1, from: .allOn), "the move in hand goes on")
        session.advance(by: aMove)
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
        session.advance(by: 0.4 * aMove)
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
        session.advance(by: 0.25 * aMove)
        session.togglePlay()
        session.advance(by: 0.5 * aMove)
        #expect(session.progress == 0.25, "nothing moves while paused")
        #expect(session.canPlay)
        session.togglePlay()
        session.advance(by: 0.5 * aMove)
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
        session.advance(by: 0.5 * aMove)
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
        session.advance(by: 0.3 * aMove)
        #expect(abs(session.progress - 0.7) < 1e-12)
        #expect(session.state == ringOneOff, "the state changes back only when the move has run back")
        if case .playing(let move, let stage, let undoing) = session.status {
            #expect(undoing)
            #expect(move == Move(ring: 1, from: ringOneOff), "the ring is going back on")
            #expect(stage == MoveMotion(move).stage(at: 0.3))
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
        session.advance(by: 0.4 * aMove)
        session.undo()
        session.advance(by: 0.1 * aMove)
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

    @Test func solvePlaysTheShortestWay() {
        var session = PuzzleSession()
        session.solve()
        #expect(session.isSolving)
        playOut(&session)

        #expect(session.state == .allOff)
        #expect(session.moveCount == PuzzleState.allOn.moves(to: .allOff).count)
        #expect(!session.isSolving)
        #expect(session.queue.isEmpty)
        #expect(session.note == nil)
    }

    /// Solve played the whole way, as the app plays it, 60 ms a frame, from every ring on to every ring off, and then
    /// every move undone back to every ring on: every one of the 341 moves of the shortest way, and the toy never
    /// jumps. Where one move hands over to the next, the last pose of the one is the first of the other, the rest of
    /// the state between them; and from one frame to the next no part moves further than 60 ms can carry it.
    @Test func solvingToTheEndAndUndoingEveryMovePlaysWithoutAJump() throws {
        func isClose(_ a: ToyPose, _ b: ToyPose) -> Bool {
            zip(a.rings + a.rods + [a.bar], b.rings + b.rods + [b.bar]).allSatisfy {
                simd_distance($0.position, $1.position) < 1e-9 && simd_distance($0.orientation.vector, $1.orientation.vector) < 1e-9
            } && simd_distance(a.swordOffset, b.swordOffset) < 1e-9
        }
        func travel(_ a: ToyPose, _ b: ToyPose) -> Double {
            zip(a.rings + a.rods, b.rings + b.rods).map { simd_distance($0.position, $1.position) }.max()! + simd_distance(a.swordOffset, b.swordOffset)
        }
        var session = PuzzleSession()
        var handOvers = 0, largest = 0.0
        /// Plays until nothing plays, checking every frame and every hand-over.
        func playChecking(_ session: inout PuzzleSession) throws {
            var previous = session.pose
            var playing = session.current
            while session.isPlaying {
                let before = session
                session.advance(by: 0.06)
                let pose = session.pose
                if session.current != playing, let old = before.motion, let new = session.motion {
                    // The frame that ends one move and begins the next shows the next at its start.
                    let end = before.direction == .forward ? 1.0 : 0.0
                    #expect(isClose(old.pose(at: end), new.pose(at: session.progress)), "from \(String(describing: playing)) to \(String(describing: session.current))")
                    #expect(isClose(new.pose(at: session.progress), RestPoses.pose(for: session.state)))
                    handOvers += 1
                    playing = session.current
                } else {
                    largest = max(largest, travel(previous, pose))
                }
                previous = pose
            }
        }
        session.solve()
        try playChecking(&session)
        #expect(session.state == .allOff && session.moveCount == 341 && handOvers == 340)
        #expect(isClose(session.pose, RestPoses.pose(for: .allOff)))
        while session.canUndo {
            session.undo()
            try playChecking(&session)
        }
        #expect(session.state == .allOn && session.moveCount == 0)
        #expect(isClose(session.pose, RestPoses.pose(for: .allOn)))
        print("solve to the end and back: \(handOvers) hand-overs between moves; at most \(String(format: "%.2f", largest)) mm from one frame to the next")
        #expect(largest < 20)
    }

    /// The session plays by time: ring 9's move, played a frame at a time, takes its own length, and ring 2's three
    /// seconds.
    @Test(arguments: [1, 8])
    func theSessionPlaysAMoveInItsOwnTime(_ index: Int) {
        let move = MoveMotion.written[index]
        var session = PuzzleSession(at: move, progress: 0)
        session.togglePlay()
        var elapsed = 0.0
        let frame = 1.0 / 120
        while session.isPlaying && session.current == move {
            session.advance(by: frame)
            elapsed += frame
        }
        #expect(session.state == move.to)
        #expect(abs(elapsed - MoveMotion(move).duration) <= frame + 1e-9, "ring \(move.ring): played in \(elapsed) s")
    }

    @Test func solveStartsAfterTheMoveInHand() {
        var session = PuzzleSession()
        session.tap(2)
        session.advance(by: 0.5 * aMove)
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
            #expect(session.stages == MoveMotion(move).stages)
            #expect(session.pose == MoveMotion(move).pose(at: 0.5))
        }
        let atEnd = PuzzleSession(at: try #require(MoveMotion.written.first), progress: 1)
        #expect(atEnd.moveCount == 1)
    }
}
