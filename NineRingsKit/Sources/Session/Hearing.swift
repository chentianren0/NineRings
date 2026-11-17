import Motion
import Puzzle

/// What is heard and felt as a session goes from one moment to the next: the one rule for when the toy sounds.
///
/// An event of a move's score sounds when the progress crosses it (see ``Score/events(of:from:to:)``): playing at any
/// speed, paused part way, or dragged with the slider either way. Between two moments of a session the move on the
/// slider may also have ended and the next one begun, so the crossing is followed across the change: the move that
/// ended is heard to its end, and the next from its start. A jump, such as Reset or starting at a chosen move, is not
/// a crossing and is silent.
public struct Hearing: Sendable, Equatable {
    /// An event heard, with the move it belongs to.
    public struct Heard: Sendable, Equatable {
        public let event: Score.Event
        public let move: Move
        /// The event's place in its score: in the reversed move's when the move is going back.
        public let index: Int
        /// The move's place in the session: 0 for the first move made, and so on. The voices vary repeats by it.
        public let moveNumber: Int
    }

    /// The events crossed, in order.
    public var events: [Heard] = []
    /// Whether a move ended with every ring off.
    public var isSolved = false
    /// The ring whose move the rule just refused, if any.
    public var refused: Int?
    /// How far the sword travelled, in millimetres.
    public var swordTravel = 0.0

    public init() {}

    /// What is heard going from `before` to `after`. `tapped` is the ring just asked to move, if that is what made the
    /// change: asking twice in a row for a ring the rule refuses changes nothing else, but is refused twice.
    public init(from before: PuzzleSession, to after: PuzzleSession, tapped: Int? = nil) {
        if case .blocked(let ring, _)? = after.note, after.note != before.note || (tapped == ring && !before.isBusy) {
            refused = ring
        }
        // A different start is a jump to a chosen move; no move is a jump back to every ring on.
        guard after.start == before.start, let move = after.current else { return }
        isSolved = after.state == .allOff && before.state != .allOff
        if move == before.current {
            add(move, from: before.progress, to: after.progress, in: after)
            return
        }
        // The move before ended, made, and so led to this one.
        if let previous = before.current, after.made.count == before.made.count + 1, after.made.last == previous {
            add(previous, from: before.progress, to: 1, in: after)
        }
        // This move is entered at its start, unless undo went back into it from its end.
        let entry = after.made.last == move ? 1.0 : 0.0
        add(move, from: entry, to: after.progress, in: after)
    }

    private mutating func add(_ move: Move, from start: Double, to end: Double, in session: PuzzleSession) {
        let isMade = session.made.last == move
        let number = isMade ? session.made.count - 1 : session.made.count
        let score = Score(move)
        let heard = end >= start ? score : Score(move.reversed)
        events += Score.events(of: move, from: start, to: end).map { event in
            Heard(event: event, move: move, index: heard.events.firstIndex(of: event) ?? 0, moveNumber: number)
        }
        swordTravel += abs(score.swordTravel(at: end) - score.swordTravel(at: start))
    }
}
