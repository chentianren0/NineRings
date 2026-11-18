import Motion
import Puzzle
import Testing
@testable import Session
import Toy
import simd

@Suite struct LessonRunTests {
    private let steps = Lesson.steps
    /// A frame at 60 frames a second.
    private let frame = 1.0 / 60

    /// A toy played to somewhere with a history and a move on the slider: ring 1 off, then ring 2 off part way.
    private var someToy: PuzzleSession {
        var toy = PuzzleSession()
        toy.tap(1)
        toy.advance(by: 100)
        toy.tap(3)
        toy.advance(by: 0.5)
        toy.pause()
        return toy
    }

    /// Plays the step's showing frame by frame until it is over, checking that the toy never jumps on the way, and
    /// returns how many frames it took.
    @discardableResult
    private func playOut(_ run: inout LessonRun, sourceLocation: SourceLocation = #_sourceLocation) -> Int {
        var frames = 0
        while run.toy.isPlaying {
            let before = run.toy.pose
            run.advance(by: frame)
            frames += 1
            #expect(largestMove(from: before, to: run.toy.pose) < 6, "a frame moves no part far", sourceLocation: sourceLocation)
            if frames > 100_000 { Issue.record("playing never stopped", sourceLocation: sourceLocation); break }
        }
        return frames
    }

    /// The farthest any part's origin moves, in millimetres, from one pose to another.
    private func largestMove(from a: ToyPose, to b: ToyPose) -> Double {
        let parts = zip(a.rings + a.rods + [a.bar], b.rings + b.rods + [b.bar])
        let partMoves = parts.map { simd_distance($0.position, $1.position) }
        return max(partMoves.max() ?? 0, abs(a.swordSlide - b.swordSlide), abs(a.swordHeight - b.swordHeight))
    }

    // MARK: Opening and closing

    @Test func openingShowsTheFirstStepWithEveryRingOnAndRemembersTheToyPaused() {
        var toy = someToy
        toy.togglePlay()
        #expect(toy.isPlaying)
        let run = LessonRun(opening: toy)
        #expect(run.index == 0)
        #expect(run.page.key == "lesson.toy")
        #expect(run.toy.state == .allOn)
        #expect(run.toy.current == nil)
        #expect(!run.toy.isBusy)
        var paused = toy
        paused.pause()
        #expect(run.before == paused)
        #expect(!run.before.isPlaying)
    }

    @Test func openingAtAStepShowsThatStepFromItsStart() {
        for index in steps.indices.dropLast() {
            let run = LessonRun(opening: someToy, at: index)
            #expect(run.index == index)
            #expect(run.toy.state == steps[index].start, "\(steps[index].key) starts in its start")
        }
        let last = LessonRun(opening: someToy, at: steps.count - 1)
        #expect(last.toy == last.before, "the last step shows the person's own toy")
        #expect(LessonRun(opening: PuzzleSession(), at: 99).index == steps.count - 1)
        #expect(LessonRun(opening: PuzzleSession(), at: -3).index == 0)
    }

    @Test func closingFromAnyStepButTheLastGivesBackTheToyAsItWas() {
        let toy = someToy
        for index in steps.indices.dropLast() {
            var run = LessonRun(opening: toy, at: index)
            playOut(&run)
            #expect(run.closingToy == toy, "closing from \(steps[index].key)")
            #expect(run.closingToy.made == toy.made, "the undo history is kept")
        }
    }

    @Test func theLastStepGivesThePersonsOwnToyBack() {
        let toy = someToy
        var run = LessonRun(opening: toy, at: 10)
        playOut(&run)
        #expect(run.jumps(to: 11), "the person's toy is not where the lesson left off")
        run.goForward()
        #expect(run.givesToyBack && run.page.givesToyBack)
        #expect(run.toy == toy, "with its state, its history and the move on its slider")
        #expect(run.closingToy == run.toy)
        #expect(!run.closingJumps, "closing from the last step changes nothing")
    }

    @Test func playOnTheLastStepIsThePersonsOwnAndClosingKeepsIt() {
        var own = PuzzleSession()
        own.tap(1)
        own.advance(by: 100)
        var run = LessonRun(opening: own, at: steps.count - 1)
        #expect(run.canUndo && run.canSolve && run.canScrub, "every control reaches the person's toy")
        run.useToy { $0.tap(2) }
        #expect(run.toy.note != nil, "a ring that can't move says why, as in play")
        run.useToy { $0.tap(3) }
        #expect(run.toy.isPlaying)
        run.advance(by: 100)
        #expect(run.toy.state == PuzzleState("010111111"))
        #expect(run.toy.made.map(\.ring) == [1, 3])
        run.useToy { $0.undo() }
        #expect(run.toy.isPlaying, "undo plays ring 3's move back")
        run.advance(by: 100)
        #expect(run.toy.state == PuzzleState("011111111"))
        run.reset()
        #expect(run.index == steps.count - 1, "reset there is the toy's own")
        #expect(run.toy.state == .allOn)
        #expect(run.closingToy == run.toy)
    }

    @Test func backFromTheLastStepTakesTheToyAgainAsItIsThen() {
        var run = LessonRun(opening: PuzzleSession(), at: steps.count - 1)
        run.useToy { $0.tap(1) }
        run.advance(by: 0.3)
        let own = run.toy
        #expect(run.jumps(to: 10))
        run.goBack()
        var paused = own
        paused.pause()
        #expect(run.before == paused, "the lesson remembers the toy as it was when taken")
        #expect(run.toy.state == PuzzleState("000101111"))
        #expect(run.toy.made.isEmpty, "the lesson's toy keeps nothing of the person's")
        #expect(run.closingToy == paused, "closing from step 11 gives the toy back as it was")
        run.goForward()
        #expect(run.toy == paused, "and the last step gives it back again")
    }

    @Test func goingToTheLastStepWhileOnItKeepsThePersonsPlay() {
        var run = LessonRun(opening: PuzzleSession(), at: steps.count - 1)
        run.useToy { $0.tap(1) }
        run.advance(by: 100)
        let played = run.toy
        run.go(to: steps.count - 1)
        #expect(run.toy == played)
        #expect(!run.page.canReplay)
    }

    // MARK: Going through

    /// Going forward from each step once its showing is over: the next step goes on from where the toy is, with no
    /// jump, each step starts in its start and ends in its end, and a held move stops exactly at its held progress.
    @Test func goingForwardAfterEachShowingNeverJumps() throws {
        var run = LessonRun(opening: someToy)
        for index in steps.indices.dropLast() {
            let step = steps[index]
            #expect(run.index == index)
            #expect(run.toy.state == step.start, "\(step.key) starts in its start")
            #expect(run.toy.pose.isClose(to: startPose(of: step)), "\(step.key) shows its start")
            #expect(run.page.canReplay == step.plays)
            #expect(run.isShowing == step.plays)
            playOut(&run)
            #expect(!run.isShowing, "\(step.key) has shown all it shows")
            #expect(!run.canPlay)
            switch step.show {
            case .hold(let move, _):
                #expect(run.toy.current == move)
                #expect(run.toy.progress == step.heldProgress, "\(step.key) holds exactly at its stage's end")
                guard case .paused(_, let stage, _) = run.toy.status else { Issue.record("\(step.key) is paused"); continue }
                guard case .hold(_, let key) = step.show else { continue }
                #expect(stage.key == key, "the status line names the stage the move is held after")
            default:
                #expect(run.toy.state == step.end, "\(step.key) ends in its end")
                #expect(!run.toy.isBusy)
            }
            if index + 1 < steps.count - 1 {
                #expect(!run.jumps(to: index + 1), "\(steps[index + 1].key) goes on from where \(step.key) ended")
                let before = run.toy.pose
                run.goForward()
                #expect(largestMove(from: before, to: run.toy.pose) < 0.01)
            }
        }
        run.goForward()
        #expect(!run.page.canGoForward)
    }

    /// Going back puts the toy in the step's start and plays the step again.
    @Test func goingBackPutsTheToyInTheStepsStart() {
        var run = LessonRun(opening: someToy, at: steps.count - 1)
        for index in steps.indices.reversed().dropFirst() {
            run.goBack()
            let step = steps[index]
            #expect(run.index == index)
            #expect(run.toy.state == step.start)
            #expect(run.toy.pose.isClose(to: startPose(of: step)), "\(step.key) shows its start")
            #expect(run.toy.isPlaying == step.plays)
        }
        #expect(!run.page.canGoBack)
        run.goBack()
        #expect(run.index == 0)
    }

    @Test func goingBackFromAStepThatHasPlayedJumpsAndSaysSo() {
        var run = LessonRun(opening: PuzzleSession(), at: 4)
        #expect(run.jumps(to: 3), "step 4 starts with ring 1 on, step 5 rests with it off")
        run.goBack()
        #expect(run.toy.state == .allOn)
        #expect(run.toy.isPlaying)
    }

    @Test func nextWhileAStepPlaysGoesOnAtOnceToTheNextStepsStart() throws {
        // Ring 3's move, playing toward its hold.
        var run = LessonRun(opening: PuzzleSession(), at: 5)
        run.advance(by: 0.3)
        #expect(run.toy.isPlaying)
        #expect(run.jumps(to: 6))
        run.goForward()
        let held = try #require(steps[6].heldProgress)
        #expect(run.index == 6)
        #expect(run.toy.progress == held, "step 7 starts where step 6 holds the move")
        #expect(run.toy.isPlaying)

        // Ring 1 coming off, part way: the next step rests where it ends.
        run = LessonRun(opening: PuzzleSession(), at: 3)
        run.advance(by: 0.2)
        run.goForward()
        #expect(run.index == 4)
        #expect(run.toy.state == steps[4].start)
        #expect(!run.toy.isBusy)
    }

    @Test func playAgainPlaysTheStepFromItsStart() throws {
        var run = LessonRun(opening: PuzzleSession(), at: 7)
        playOut(&run)
        #expect(run.toy.state == steps[7].end)
        #expect(run.replayJumps)
        run.replay()
        #expect(run.index == 7)
        #expect(run.toy.state == steps[7].start)
        #expect(run.toy.isPlaying)
        playOut(&run)
        #expect(run.toy.state == steps[7].end, "both moves play again")

        // The finish plays again from the hold.
        run = LessonRun(opening: PuzzleSession(), at: 6)
        playOut(&run)
        run.replay()
        #expect(run.toy.progress == steps[6].heldProgress)
        #expect(run.toy.isPlaying)
    }

    @Test func aStepWithTwoMovesPlaysBothInTurn() {
        var run = LessonRun(opening: PuzzleSession(), at: 7)
        guard case .play(let moves) = steps[7].show else { Issue.record("step 8 plays moves"); return }
        #expect(run.toy.current == moves[0])
        while run.toy.current == moves[0] && run.toy.isPlaying { run.advance(by: frame) }
        #expect(run.toy.current == moves[1])
        #expect(run.toy.isPlaying, "the second move begins as the first ends")
        playOut(&run)
        #expect(run.toy.state == moves[1].to)
    }

    /// While the lesson holds the toy no ring can be asked for, so the ring buttons follow the toy move by move, not the
    /// end of the step. Given back, they show what a tap would do.
    @Test func whileTheLessonHoldsTheToyTheRingButtonsFollowIt() {
        var play = PlayState()
        play.openLesson(at: 7)
        guard case .play(let moves) = steps[7].show else { Issue.record("step 8 plays moves"); return }
        play.advance(by: frame)
        #expect(play.markers == play.toy.markers(asPlanned: false))
        #expect(play.markers.map(\.isOn) == PuzzleState.rings.map(moves[0].from.isOn))
        play.goToLessonStep(steps.count - 1)
        play.tap(1)
        #expect(play.markers == play.toy.markers)
        #expect(play.markers != play.toy.markers(asPlanned: false))
    }

    @Test func pageSaysWhereYouAre() {
        let run = LessonRun(opening: PuzzleSession(), at: 2)
        #expect(run.page == LessonRun.Page(index: 2, count: 12, key: "lesson.sword", view: .top, canGoBack: true, canGoForward: true, canReplay: false, givesToyBack: false))
        #expect(LessonRun(opening: PuzzleSession(), at: 3).page.view == .side)
        #expect(LessonRun(opening: PuzzleSession(), at: 11).page.isLast)
    }

    // MARK: The toy's own controls

    @Test func onTheLessonsStepsTheToyCannotBeTakenOver() {
        for index in steps.indices.dropLast() {
            var run = LessonRun(opening: PuzzleSession(), at: index)
            run.advance(by: 0.2)
            let shown = run
            #expect(!run.canUndo && !run.canSolve && !run.canScrub, "\(steps[index].key)")
            run.useToy { $0.tap(1) }
            run.useToy { $0.undo() }
            run.useToy { $0.solve() }
            run.useToy { $0.scrub(to: 0.9) }
            run.useToy { $0.reset() }
            #expect(run == shown, "nothing reaches the toy on \(steps[index].key)")
        }
    }

    @Test func playPausesAndResumesTheShowing() {
        var run = LessonRun(opening: PuzzleSession(), at: 3)
        run.advance(by: 0.2)
        #expect(!run.canPlay)
        run.togglePlay()
        #expect(!run.toy.isPlaying)
        #expect(run.canPlay)
        let progress = run.toy.progress
        run.advance(by: 1)
        #expect(run.toy.progress == progress, "paused, it stays")
        run.togglePlay()
        #expect(run.toy.isPlaying)
        playOut(&run)
        #expect(run.toy.state == steps[3].end)
        run.togglePlay()
        #expect(!run.toy.isPlaying, "once shown, play does not move the toy on")
    }

    @Test func playDoesNotCarryAHeldMovePastItsHold() {
        var run = LessonRun(opening: PuzzleSession(), at: 5)
        playOut(&run)
        #expect(!run.canPlay)
        run.togglePlay()
        #expect(!run.toy.isPlaying)
        #expect(run.toy.progress == steps[5].heldProgress)
    }

    @Test func aHeldMoveStopsExactlyAtItsHoldWhateverTheFrames() throws {
        let held = try #require(steps[5].heldProgress)
        for seconds in [1.0 / 120, 1.0 / 60, 1.0 / 30, 0.1, 0.37, 5] {
            var run = LessonRun(opening: PuzzleSession(), at: 5)
            while run.toy.isPlaying { run.advance(by: seconds) }
            #expect(run.toy.progress == held, "with steps of \(seconds) s")
        }
    }

    @Test func resetGoesBackToTheFirstStep() {
        var run = LessonRun(opening: PuzzleSession(), at: 6)
        run.reset()
        #expect(run.index == 0)
        #expect(run.toy.state == .allOn)
    }

    // MARK: Helpers

    private func startPose(of step: LessonStep) -> ToyPose {
        switch step.show {
        case .finish(let move, _):
            MoveMotion(move).pose(at: step.heldProgress ?? 0)
        default:
            RestPoses.pose(for: step.start ?? .allOn)
        }
    }
}
