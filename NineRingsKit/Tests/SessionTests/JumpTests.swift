import Puzzle
import Testing
import Toy
@testable import Session

/// Which changes make the toy shown jump, so that the screen fades the parts that change place instead of moving them:
/// a change that sets the toy somewhere else at once, and only where some part is somewhere else.
@Suite struct JumpTests {
    static let frame = 1.0 / 60

    /// The person's toy with ring 1 part way off, paused.
    private func ringOnePartWay() -> PlayState {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<30 { state.advance(by: Self.frame) }
        state.pause()
        return state
    }

    // MARK: - The parts that change place

    @Test func aPoseHasNoPartMovedFromItself() {
        let pose = PuzzleSession().pose
        #expect(pose.parts(movedFrom: pose).isEmpty)
        #expect(pose.isClose(to: pose))
    }

    /// Ring 4 put on beside ring 3: ring 4 and its rod change place, and nothing else does.
    @Test func settingOneRingMovesThatRingAndItsRodAlone() throws {
        let before = PuzzleSession(resting: try #require(PuzzleState("001000000"))).pose
        let after = PuzzleSession(resting: try #require(PuzzleState("001100000"))).pose
        let moved = after.parts(movedFrom: before)
        #expect(moved.rings.isSubset(of: [4]))
        #expect(moved.rods.isSubset(of: [4]))
        #expect(!moved.isEmpty)
        #expect(!moved.bar)
        #expect(!moved.sword)
    }

    /// A move part way has the sword slid: Reset brings the sword back, as well as the ring.
    @Test func partWayToRestMovesTheSword() {
        let partWay = ringOnePartWay()
        let moved = PuzzleSession().pose.parts(movedFrom: partWay.toy.pose)
        #expect(moved.sword || moved.rings.contains(1))
        #expect(!moved.rings.contains(9))
    }

    // MARK: - Which changes jump

    @Test func movesNeverJump() {
        var state = PlayState()
        state.tap(1)
        for _ in 0..<600 { state.advance(by: Self.frame) }
        state.undo()
        state.scrub(to: 0.5)
        state.solve()
        #expect(state.jumps == 0)
    }

    @Test func resetWithEveryRingOnDoesNotJump() {
        var state = PlayState()
        state.reset()
        #expect(state.jumps == 0)
    }

    @Test func resetFromAMovePartWayJumps() {
        var state = ringOnePartWay()
        state.reset()
        #expect(state.jumps == 1)
    }

    /// The lesson starts with every ring on: opening it over a toy with every ring on shows the toy throughout.
    @Test func openingTheLessonWithEveryRingOnDoesNotJump() {
        var state = PlayState()
        state.openLesson()
        #expect(state.jumps == 0)
        state.closeLesson()
        #expect(state.jumps == 0)
    }

    @Test func openingAndClosingTheLessonOverAMovePartWayJumpEachWay() {
        var state = ringOnePartWay()
        state.openLesson()
        #expect(state.jumps == 1)
        state.closeLesson()
        #expect(state.jumps == 2)
    }

    /// Going on to the next step from where the last one ended moves on; going back sets the toy at once.
    @Test func lessonStepsJumpExactlyWhereTheLessonSaysTheyDo() {
        var state = PlayState()
        state.openLesson(at: 3)
        while state.toy.isPlaying { state.advance(by: Self.frame) }
        for index in [4, 3, 3, 0, 11] {
            let expected = state.lesson!.jumps(to: index)
            let before = state.jumps
            state.goToLessonStep(index)
            #expect((state.jumps - before == 1) == expected, "step \(index + 1)")
            while state.toy.isPlaying { state.advance(by: Self.frame) }
        }
    }

    @Test func settingTheRingsJumpsAtEachChangeOfTheArrangement() throws {
        var state = PlayState()
        state.startSettingRings()
        #expect(state.jumps == 0)
        state.tap(9)
        #expect(state.jumps == 1)
        state.setRings(to: try #require(PuzzleState("110000000")))
        #expect(state.jumps == 2)
        state.finishSettingRings()
        #expect(state.jumps == 2)
    }

    @Test func settingTheRingsFromAMovePartWayJumpsAtTheStartAndOnCancel() {
        var state = ringOnePartWay()
        #expect(state.settingRingsStartJumps)
        state.startSettingRings()
        #expect(state.jumps == 1)
        #expect(state.settingRingsCancelJumps)
        state.cancelSettingRings()
        #expect(state.jumps == 2)
    }
}
