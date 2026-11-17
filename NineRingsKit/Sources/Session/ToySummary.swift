import Puzzle

/// What the toy is, for someone who cannot see it: which rings are on, and which can move now.
///
/// It holds no text, like ``PuzzleSession``: the app says it in words. The rules it keeps:
/// - The rings that are on are told as runs of neighbours, ring 1's end first: rings 1, 2, 3 and 5 on are the runs
///   1 to 3 and 5. Every ring on is the one run 1 to 9; no ring on is no run.
/// - The rings that can move are the ones the rule lets move now, from ``PuzzleState/block(for:)``: ring 1 always, and
///   the ring after the first ring that is on, when there is one. So there are never more than two.
public struct ToySummary: Sendable, Equatable {
    public let state: PuzzleState
    /// The rings that are on, as runs of neighbours, in order.
    public let on: [ClosedRange<Int>]
    /// The rings that can move now, in order.
    public let movable: [Int]

    public init(_ state: PuzzleState) {
        self.state = state
        on = Self.runs(PuzzleState.rings.filter(state.isOn))
        movable = state.movableRings
    }

    /// How many rings are on.
    public var onCount: Int { on.reduce(0) { $0 + $1.count } }

    /// Rings in increasing order, gathered into runs of neighbours.
    static func runs(_ rings: [Int]) -> [ClosedRange<Int>] {
        rings.reduce(into: []) { runs, ring in
            if let last = runs.last, last.upperBound == ring - 1 {
                runs[runs.count - 1] = last.lowerBound...ring
            } else {
                runs.append(ring...ring)
            }
        }
    }
}
