import Motion
import Puzzle
import Testing
@testable import Session

@Suite struct CongratulationTests {
    /// Ring 1 on and every other ring off: one move, ring 1 off, before the end.
    private let oneBeforeTheEnd = PuzzleState("100000000")!
    /// Rings 1 and 2 on: Solve takes two moves from here, ring 2 off and then ring 1 off.
    private let twoOn = PuzzleState("110000000")!

    /// A driver like the app's player: every change to the session goes through the congratulation.
    private struct Driver {
        var session: PuzzleSession
        var congratulation = Congratulation()
        /// How many times the moment came.
        var moments = 0

        init(_ session: PuzzleSession = PuzzleSession()) {
            self.session = session
        }

        mutating func change(_ body: (inout PuzzleSession) -> Void) {
            let before = session
            body(&session)
            if congratulation.update(from: before, to: session) { moments += 1 }
        }

        /// Plays until nothing is playing, a frame at a time, as the app does.
        mutating func playOut() {
            var steps = 0
            while session.isPlaying {
                change { $0.advance(by: 0.05) }
                steps += 1
                precondition(steps < 100_000, "playing never stopped")
            }
        }
    }

    private func atStart(of state: PuzzleState, ring: Int) -> PuzzleSession {
        PuzzleSession(at: Move(ring: ring, from: state)!)
    }

    @Test func theLastMoveCongratulatesOnceWhenItEnds() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.tap(1) }
        #expect(!driver.congratulation.isShowing, "not while the move plays")
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 1)
        #expect(driver.congratulation.isShowing)
    }

    @Test func draggingTheLastMoveToItsEndCongratulates() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        #expect(driver.moments == 1)
        #expect(driver.congratulation.isShowing)
    }

    @Test func theNextChangeHidesIt() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        #expect(driver.congratulation.isShowing)
        // A ring that cannot move: nothing plays, but the person did something with the toy.
        driver.change { $0.tap(5) }
        #expect(!driver.congratulation.isShowing)
    }

    @Test func aChangeThatChangesNothingKeepsIt() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        driver.change { $0.pause() }
        #expect(driver.congratulation.isShowing)
    }

    @Test func dismissHidesIt() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        driver.congratulation.dismiss()
        #expect(!driver.congratulation.isShowing)
    }

    @Test func solveDoesNotCongratulate() {
        var driver = Driver(atStart(of: twoOn, ring: 1))
        driver.change { $0.solve() }
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 0)
    }

    @Test func solvePressedForTheLastMoveDoesNotCongratulate() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.solve() }
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 0)
    }

    @Test func aTapOnTheRingSolveIsMovingLeavesTheMoveToSolve() {
        // Solve begins its only move, ring 1 off. A tap on ring 1 while it plays would only move it back, so it changes
        // nothing: the move stays Solve's, and Solve's last move does not congratulate.
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.solve() }
        driver.change { $0.tap(1) }
        #expect(driver.session.isSolving)
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 0)
        #expect(!driver.congratulation.isArmed)
    }

    @Test func aTapDuringSolveTakesOverAndTheMovesAfterAreThePersons() {
        // Solve begins ring 2 off from rings 1 and 2 on. A tap on ring 1 takes over: Solve's move ends, then ring 1
        // comes off as the person's own move, the last one.
        var driver = Driver(atStart(of: twoOn, ring: 2))
        driver.change { $0.solve() }
        driver.change { $0.tap(1) }
        #expect(!driver.session.isSolving)
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 1)
    }

    @Test func undoingBackToEveryRingOffDoesNotCongratulateAgain() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        #expect(driver.moments == 1)
        driver.change { $0.tap(1) }   // ring 1 goes back on
        driver.playOut()
        driver.change { $0.undo() }   // and comes back off, by undo
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 1)
    }

    @Test func takingTheLastRingOffAgainByHandDoesNotCongratulateAgain() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        driver.change { $0.tap(1) }
        driver.playOut()
        driver.change { $0.tap(1) }
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 1)
    }

    @Test func everyRingOnAgainArmsItAgain() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.scrub(to: 1) }
        #expect(!driver.congratulation.isArmed)
        driver.change { $0.reset() }
        #expect(driver.congratulation.isArmed)
        #expect(!driver.congratulation.isShowing)
    }

    @Test func afterSolveAndResetTheWholeWayByHandCongratulates() {
        // Solve from every ring on, then Reset, then the shortest way by hand, one tap at a time.
        var driver = Driver()
        driver.change { $0.solve() }
        driver.playOut()
        #expect(driver.moments == 0)
        driver.change { $0.reset() }
        for ring in PuzzleState.allOn.moves(to: .allOff) {
            driver.change { $0.tap(ring) }
            driver.playOut()
        }
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 1)
    }

    /// From every ring off only ring 1 can move, and asking for it again during the last move changes nothing: the
    /// last move rests with every ring off and congratulates.
    @Test func ringOneAskedAgainDuringTheLastMoveStillCongratulates() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.tap(1) }
        driver.change { $0.tap(1) }
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.moments == 1)
    }

    /// A ring waiting after the last move is refused when its turn comes, so the toy rests with every ring off.
    @Test func aRefusedRingAfterTheLastMoveStillCongratulates() {
        var driver = Driver(atStart(of: oneBeforeTheEnd, ring: 1))
        driver.change { $0.tap(1) }
        driver.change { $0.tap(2) }
        driver.playOut()
        #expect(driver.session.state == .allOff)
        #expect(driver.session.note == .blocked(ring: 2, block: .previousRingOff(1)))
        #expect(driver.moments == 1)
    }
}
