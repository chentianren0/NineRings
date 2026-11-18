import Puzzle

/// When the screen congratulates: the moment the person's own move takes the last ring off.
///
/// Whoever drives a ``PuzzleSession`` shows it the session before and after each change, with ``update(from:to:)``.
/// The rules it keeps:
/// - It is shown when a move made forward ends with every ring off and nothing else in hand, so that the toy rests
///   there. A move undone does not count, and neither does a move that Solve began, however it was carried on: the
///   text says the person took the rings off.
/// - Once every ring has come off, it is not shown again until every ring is on again, by Reset or by moves. Putting
///   ring 1 back on and taking it off again is exploring, not solving the puzzle again. Rings set by hand count
///   the same way: they arm it only when every ring is on (see ``set(_:)``).
/// - It goes away at the next change to the session, so that the toy stays free: a tap, Reset, a drag of the slider.
///   The screen may also hide it itself, with ``dismiss()``.
public struct Congratulation: Sendable, Equatable {
    /// Whether the congratulation is showing now.
    public private(set) var isShowing = false
    /// Whether arriving at every ring off would congratulate: true until every ring has come off, and again once
    /// every ring is on.
    public private(set) var isArmed = true

    public init() {}

    /// Not showing, and armed or not, as a kept toy brings it back.
    public init(isArmed: Bool) {
        self.isArmed = isArmed
    }

    /// Takes in one change to the session. Returns true when this change is the moment to congratulate.
    @discardableResult
    public mutating func update(from before: PuzzleSession, to after: PuzzleSession) -> Bool {
        guard before != after else { return false }
        isShowing = false
        if after.state == .allOn {
            isArmed = true
            return false
        }
        // A move made forward that leaves every ring off, with the toy at rest. From every ring off only ring 1 can
        // move, which a tap during the last move does not queue (see `PuzzleSession.tap`), so a ring waiting then is
        // refused and the toy rests; a session played otherwise could still pass through.
        let arrived = after.state == .allOff && !after.isBusy && after.moveCount > before.moveCount
        guard arrived, isArmed else { return false }
        isArmed = false
        // During Solve's last move its queue is empty but the session is still solving; the move ending clears it. A move
        // Solve began stays Solve's however it is carried on, by Play or by the slider (``PuzzleSession/madeBySolveCount``).
        guard !before.isSolving, after.madeBySolveCount == before.madeBySolveCount else { return false }
        isShowing = true
        return true
    }

    /// Hides the congratulation, as its Done button does.
    public mutating func dismiss() {
        isShowing = false
    }

    /// Takes in the toy set to an arrangement the person chose, as setting the rings does. It is hidden, and armed only
    /// when every ring is on, as after Reset: from any other arrangement, taking the last ring off is not taking all
    /// nine off the sword, which is what the congratulation says.
    public mutating func set(_ state: PuzzleState) {
        isShowing = false
        isArmed = state == .allOn
    }
}
