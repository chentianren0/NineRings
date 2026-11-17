import Puzzle
import Testing
@testable import Session

/// What the toy is, told to someone who cannot see it: the rings on as runs, and the rings that can move.
@Suite struct ToySummaryTests {
    @Test func everyRingOnIsOneRun() {
        let summary = ToySummary(.allOn)
        #expect(summary.on == [1...9])
        #expect(summary.onCount == 9)
        #expect(summary.movable == [1, 2])
    }

    @Test func noRingOnIsNoRun() {
        let summary = ToySummary(.allOff)
        #expect(summary.on.isEmpty)
        #expect(summary.onCount == 0)
        #expect(summary.movable == [1])
    }

    @Test func neighboursGatherIntoRuns() {
        let summary = ToySummary(PuzzleState("111010011")!)
        #expect(summary.on == [1...3, 5...5, 8...9])
        #expect(summary.onCount == 6)
    }

    /// Ring 1 can always move, and the ring after the first ring on, when there is one: never more than two.
    @Test func theMovableRingsAreRingOneAndTheOneAfterTheFirstRingOn() {
        #expect(ToySummary(PuzzleState("001100000")!).movable == [1, 4])
        #expect(ToySummary(PuzzleState("000000001")!).movable == [1])
        #expect(ToySummary(PuzzleState("100000000")!).movable == [1, 2])
        for bits in 0..<UInt16(1 << PuzzleState.ringCount) {
            let state = PuzzleState(bits: bits)
            let summary = ToySummary(state)
            #expect(summary.movable == PuzzleState.rings.filter { state.block(for: $0) == nil })
            #expect(summary.movable.count <= 2)
            #expect(summary.on.flatMap { Array($0) } == PuzzleState.rings.filter(state.isOn))
        }
    }
}
