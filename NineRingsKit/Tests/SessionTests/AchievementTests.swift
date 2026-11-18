import Foundation
import Motion
import Puzzle
import Testing
@testable import Session

@Suite struct AchievementTests {
    /// A driver like the app's player: every request goes to the play state, and what each change earns is counted.
    private struct Driver {
        var play: PlayState
        /// How many times each achievement was earned.
        var counts: [Achievement: Int] = [:]

        init(_ toy: PuzzleSession = PuzzleSession()) {
            play = PlayState(toy)
        }

        var state: PuzzleState { play.toy.state }

        func count(_ achievement: Achievement) -> Int { counts[achievement, default: 0] }

        mutating func change(_ body: (inout PlayState) -> Void) {
            body(&play)
            for achievement in play.earned { counts[achievement, default: 0] += 1 }
        }

        /// Plays until nothing is playing, as the app's clock does, in large steps.
        mutating func playOut() {
            var steps = 0
            while play.toy.isPlaying {
                change { $0.advance(by: 0.5) }
                steps += 1
                precondition(steps < 100_000, "playing never stopped")
            }
        }

        /// One ring tapped and its move played out.
        mutating func move(_ ring: Int) {
            change { $0.tap(ring) }
            playOut()
        }

        /// The moves along the one path to `target`, one at a time, each played out.
        mutating func walk(to target: PuzzleState) {
            for ring in state.moves(to: target) { move(ring) }
            precondition(state == target)
        }

        /// The rings set by hand to `state`.
        mutating func setRings(to state: PuzzleState) {
            change { $0.startSettingRings() }
            change { $0.setRings(to: state) }
            change { $0.finishSettingRings() }
        }
    }

    private func atStart(of state: PuzzleState, ring: Int) -> PuzzleSession {
        PuzzleSession(at: Move(ring: ring, from: state)!)
    }

    // MARK: All Nine Off

    @Test func takingEveryRingOffEarnsAllNineOffWhenTheCongratulationIsDue() {
        var driver = Driver()
        driver.walk(to: .allOff)
        #expect(driver.play.isCongratulating)
        #expect(driver.count(.allNineOff) == 1)
        // The walk is the shortest way, by hand: the record of the play earns The Shortest Way at the same moment.
        #expect(driver.counts.keys.sorted { $0.rawValue < $1.rawValue } == [.allNineOff, .shortestWay])
    }

    @Test func solveEarnsNothing() {
        var driver = Driver()
        driver.change { $0.solve() }
        driver.playOut()
        #expect(driver.state == .allOff)
        #expect(driver.counts.isEmpty)
    }

    // MARK: All Nine Back On

    @Test func fromEveryRingOffEveryRingBackOnEarnsAllNineBackOn() {
        var driver = Driver()
        driver.walk(to: .allOff)
        driver.walk(to: .allOn)
        #expect(driver.count(.allNineBackOn) == 1)
    }

    @Test func ringsSetToEveryRingOffStartTheWayBackOn() {
        var driver = Driver()
        driver.setRings(to: .allOff)
        driver.walk(to: .allOn)
        #expect(driver.count(.allNineBackOn) == 1)
        #expect(driver.count(.allNineOff) == 0)
    }

    @Test func everyRingOnWithoutComingFromEveryRingOffEarnsNothing() {
        // One move before every ring on, never having been at every ring off.
        let before = PuzzleState(rank: PuzzleState.allOn.rank - 1)
        var driver = Driver(PuzzleSession(resting: before))
        driver.walk(to: .allOn)
        #expect(driver.counts.isEmpty)
    }

    @Test func resetToEveryRingOnStartsTheWayBackOnAgain() {
        var driver = Driver()
        driver.setRings(to: .allOff)
        driver.move(1)
        driver.change { $0.reset() }
        #expect(driver.count(.allNineBackOn) == 0, "Reset is not a move")
        // From every ring on, one ring off and back on: not the way from every ring off.
        let ring = PuzzleState.allOn.nextRing(toward: .allOff)!
        driver.move(ring)
        driver.move(ring)
        #expect(driver.state == .allOn)
        #expect(driver.count(.allNineBackOn) == 0)
    }

    @Test func passingThroughEveryRingOnWithARingWaitingNeitherEarnsNorEndsTheWay() {
        var driver = Driver()
        driver.setRings(to: .allOff)
        driver.walk(to: PuzzleState(rank: PuzzleState.allOn.rank - 1))
        // The move that puts the last ring on, and, asked while it plays, the next move up the path.
        let last = driver.state.nextRing(toward: .allOn)!
        let beyond = PuzzleState.allOn.nextRing(toward: .farEnd)!
        driver.change { $0.tap(last) }
        driver.change { $0.tap(beyond) }
        driver.playOut()
        #expect(driver.state.rank == PuzzleState.allOn.rank + 1)
        #expect(driver.count(.allNineBackOn) == 0, "the toy only passed through every ring on")
        // Back down by a move made forward: the toy rests at every ring on, on the way from every ring off.
        driver.move(beyond)
        #expect(driver.state == .allOn)
        #expect(driver.count(.allNineBackOn) == 1)
    }

    // MARK: The Far End

    @Test func fromEveryRingOnToOnlyRingNineOnEarnsTheFarEnd() {
        var driver = Driver()
        driver.walk(to: .farEnd)
        #expect(PuzzleState.farEnd.description == "000000001")
        #expect(driver.count(.farEnd) == 1)
        #expect(driver.counts.count == 1)
    }

    @Test func fromEveryRingOffToOnlyRingNineOnEarnsTheFarEndAndAllNineBackOnOnTheWay() {
        var driver = Driver()
        driver.setRings(to: .allOff)
        driver.walk(to: .farEnd)
        #expect(driver.count(.allNineBackOn) == 1)
        #expect(driver.count(.farEnd) == 1)
    }

    @Test func ringsSetNextToTheFarEndAndOneMoveEarnNothing() {
        var driver = Driver()
        driver.setRings(to: PuzzleState(rank: PuzzleState.farEnd.rank - 1))
        driver.walk(to: .farEnd)
        #expect(driver.counts.isEmpty)
    }

    @Test func theFarEndIsEarnedOnceForEachWayThere() {
        var driver = Driver()
        driver.walk(to: .farEnd)
        driver.move(PuzzleState.farEnd.nextRing(toward: .allOn)!)
        driver.change { $0.undo() }
        driver.playOut()
        #expect(driver.state == .farEnd, "back at the far end by Undo")
        driver.move(PuzzleState.farEnd.nextRing(toward: .allOn)!)
        driver.move(driver.state.nextRing(toward: .farEnd)!)
        #expect(driver.state == .farEnd, "and by a move")
        #expect(driver.count(.farEnd) == 1)
    }

    // MARK: Not the person's moves

    @Test func theLessonsMovesEarnNothing() {
        var driver = Driver()
        driver.change { $0.openLesson() }
        for step in 0..<Lesson.steps.count {
            driver.change { $0.goToLessonStep(step) }
            driver.playOut()
        }
        driver.change { $0.closeLesson() }
        #expect(driver.counts.isEmpty)
    }

    @Test func aRequestThatChangesNothingEarnsNothing() {
        var driver = Driver(atStart(of: PuzzleState("100000000")!, ring: 1))
        driver.change { $0.scrub(to: 1) }
        #expect(driver.play.earned == [.allNineOff])
        driver.change { $0.goToLessonStep(3) }   // the lesson is closed: nothing changes
        #expect(driver.play.earned.isEmpty)
    }

    // MARK: The ledger

    @Test func theLedgerKeepsWhatWasEarnedUntilGameCenterTakesIt() {
        var ledger = AchievementLedger()
        #expect(ledger.earn([.allNineOff]) == [.allNineOff])
        #expect(ledger.earn([.allNineOff, .farEnd]) == [.farEnd], "earned once")
        #expect(ledger.pending == [.allNineOff, .farEnd])
        ledger.markReported([.allNineOff])
        #expect(ledger.pending == [.farEnd])
        ledger.markReported([.allNineBackOn])
        #expect(ledger.reported == [.allNineOff], "only what was earned can have been reported")
        #expect(ledger.earn([.allNineOff]).isEmpty, "taken already: not reported again")
    }

    @Test func theLedgerIsKeptAndReadBack() throws {
        var ledger = AchievementLedger()
        ledger.earn([.allNineOff, .farEnd])
        ledger.markReported([.farEnd])
        let read = try JSONDecoder().decode(AchievementLedger.self, from: JSONEncoder().encode(ledger))
        #expect(read == ledger)
    }

    @Test func identifiersAreGameCentersAndNeverChange() {
        #expect(Achievement.allCases.map(\.rawValue) == ["all_nine_off", "shortest_way", "all_nine_back_on", "far_end"])
    }
}
