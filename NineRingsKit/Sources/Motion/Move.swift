import Puzzle

/// One ring going on or coming off, from a given state.
public struct Move: Hashable, Sendable {
    public let ring: Int
    /// The state before the move.
    public let from: PuzzleState

    /// A legal move, or nil when the rule does not let `ring` move in `from`.
    public init?(ring: Int, from: PuzzleState) {
        guard PuzzleState.rings.contains(ring), from.canMove(ring) else { return nil }
        self.ring = ring
        self.from = from
    }

    /// The state after the move.
    public var to: PuzzleState { from.moving(ring) }

    /// Whether the ring comes off; otherwise it goes on.
    public var takesOff: Bool { from.isOn(ring) }

    /// The same ring moved back again.
    public var reversed: Move {
        guard let back = Move(ring: ring, from: to) else {
            preconditionFailure("a legal move can always be undone")
        }
        return back
    }
}

/// A named part of a move, as a span of its progress.
public struct Stage: Sendable, Equatable {
    /// The stage's name in English, as the stage names' String Catalog keys it: `%lld` stands where a ring's number
    /// goes, as in "Ring %lld hangs".
    public let key: String
    /// The ring whose number the name holds, or nil when it holds none.
    public let ring: Int?
    public let start: Double
    public let end: Double

    public init(key: String, ring: Int? = nil, start: Double, end: Double) {
        self.key = key
        self.ring = ring
        self.start = start
        self.end = end
    }

    /// The name in English, with the ring's number filled in.
    public var name: String {
        ring.map { key.replacingOccurrences(of: "%lld", with: String($0)) } ?? key
    }

    /// The same stage over another span.
    public func spanning(from start: Double, to end: Double) -> Stage {
        Stage(key: key, ring: ring, start: start, end: end)
    }

    public func contains(_ progress: Double) -> Bool {
        progress >= start && progress <= end
    }
}
