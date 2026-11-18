import Motion
import Puzzle
import Testing
@testable import Session

@Suite struct ToyCommandsTests {
    /// The commands for `session` as the screen would show them, with or without the lesson holding the toy.
    private func commands(_ session: PuzzleSession, lessonHoldsToy: Bool = false) -> ToyCommands {
        ToyCommands(
            markers: session.markers,
            canUndo: session.canUndo,
            canPlay: session.canPlay,
            isPlaying: session.isPlaying,
            canSolve: session.canSolve,
            canScrub: session.current != nil,
            progress: session.progress,
            stages: session.stages,
            lessonHoldsToy: lessonHoldsToy
        )
    }

    /// Ring 3 coming off from 011111111: a move of several stages.
    private let ringThreeOff = Move(ring: 3, from: PuzzleState("011111111")!)!

    @Test func ringsFollowTheRule() {
        let commands = commands(PuzzleSession())
        #expect(PuzzleState.rings.filter(commands.canMove) == [1, 2])
    }

    /// While ring 1 comes off, Move Ring offers what a tap would do: ring 3 next, not ring 1 again, nor ring 2, which
    /// cannot move once ring 1 is off.
    @Test func whileAMovePlaysTheRingsFollowWhatATapWouldDo() {
        var session = PuzzleSession()
        session.tap(1)
        #expect(PuzzleState.rings.filter(commands(session).canMove) == [3])
        session.tap(3)
        #expect(PuzzleState.rings.filter(commands(session).canMove) == [1])
    }

    @Test func nothingToUndoAndNoMoveToStepAtTheStart() {
        let commands = commands(PuzzleSession())
        #expect(!commands.canUndoMove)
        #expect(!commands.canPlayOrPause)
        #expect(commands.nextStage == nil)
        #expect(commands.previousStage == nil)
        #expect(commands.canSolvePuzzle)
        #expect(commands.canReset)
    }

    @Test func theLessonHoldingTheToyDisablesEveryChangeButPlay() {
        var session = PuzzleSession(at: ringThreeOff, progress: 0.5)
        session.togglePlay()
        let commands = commands(session, lessonHoldsToy: true)
        #expect(PuzzleState.rings.filter(commands.canMove).isEmpty)
        #expect(!commands.canUndoMove)
        #expect(!commands.canSolvePuzzle)
        #expect(!commands.canReset)
        #expect(commands.nextStage == nil)
        #expect(commands.previousStage == nil)
        #expect(commands.canPlayOrPause, "pause still stops the lesson's move")
    }

    @Test func pauseIsOfferedWhilePlaying() {
        var session = PuzzleSession()
        session.tap(1)
        #expect(commands(session).canPlayOrPause)
        #expect(commands(session).isPlaying)
    }

    @Test func nextStageGoesToTheEndOfTheStageItIsIn() {
        let stages = MoveMotion(ringThreeOff).stages
        #expect(stages.count > 1)
        let session = PuzzleSession(at: ringThreeOff, progress: 0)
        #expect(commands(session).nextStage == stages[0].end)
        #expect(commands(session).previousStage == nil)
        let midFirst = PuzzleSession(at: ringThreeOff, progress: stages[0].end / 2)
        #expect(commands(midFirst).nextStage == stages[0].end)
        #expect(commands(midFirst).previousStage == 0)
    }

    @Test func previousStageGoesToTheStartOfTheStageItIsIn() {
        let stages = MoveMotion(ringThreeOff).stages
        let last = stages[stages.count - 1]
        let atEnd = PuzzleSession(at: ringThreeOff, progress: 1)
        #expect(commands(atEnd).nextStage == nil)
        #expect(commands(atEnd).previousStage == last.start)
    }

    @Test func steppingForwardVisitsEveryBoundaryOnceAndEndsAtTheMovesEnd() {
        let stages = MoveMotion(ringThreeOff).stages
        var progress = 0.0
        var visited: [Double] = []
        while let next = ToyCommands.boundary(after: progress, in: stages) {
            #expect(next > progress)
            visited.append(next)
            progress = next
        }
        #expect(visited.last == 1)
        #expect(visited.count == stages.count)
        #expect(visited.dropLast() == stages.dropLast().map(\.end)[...])
    }

    @Test func steppingBackFromTheEndReturnsToTheStart() {
        let stages = MoveMotion(ringThreeOff).stages
        var progress = 1.0
        var steps = 0
        while let previous = ToyCommands.boundary(before: progress, in: stages) {
            #expect(previous < progress)
            progress = previous
            steps += 1
        }
        #expect(progress == 0)
        #expect(steps == stages.count)
    }

    @Test func aBoundaryReachedIsLeftByTheNextStep() {
        let stages = MoveMotion(ringThreeOff).stages
        let boundary = stages[0].end
        #expect(ToyCommands.boundary(after: boundary, in: stages) == stages[1].end)
        #expect(ToyCommands.boundary(before: boundary, in: stages) == 0)
    }

    @Test func everyWrittenMoveSteps() {
        for move in MoveMotion.written {
            let stages = MoveMotion(move).stages
            let boundaries = ToyCommands.boundaries(of: stages)
            #expect(boundaries.first == 0)
            #expect(boundaries.last == 1)
            #expect(boundaries == boundaries.sorted())
        }
    }
}
