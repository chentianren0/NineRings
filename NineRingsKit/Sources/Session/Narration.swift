import Motion
import Puzzle

/// What is said aloud, by itself, as a session goes from one moment to the next: the one rule for what someone who
/// cannot see the toy hears without asking. (What they hear when they ask, by moving to an element, is the element's
/// own label and value.)
///
/// It holds no text, like ``PuzzleSession``: each line is turned into words by the app, which says the same things the
/// screen shows. The rules it keeps:
/// - A request that starts a move playing (a ring asked, Play, Undo, Solve) says what the status line says as it
///   begins: the ring, which way it goes, and the stage.
/// - A move that ends by playing says where its ring is now, on or off, when the toy then comes to rest. In a chain
///   (Solve, or rings asked during a move) the moves between say nothing: a Solve of every ring is 341 moves, and an
///   announcement interrupts whatever is being said, so one for each would drown out the person looking for Pause. A
///   chain says its first start and its last end ("Ring 1 is off. All rings are off."), and a refusal if one stops it.
/// - A move stopped part way by a request says the status line, with the stage it stopped in.
/// - A ring the rule refuses says why, every time it is asked (see ``Hearing/refused``).
/// - Lines come in that order: a move's end, a start, a pause, a refusal.
///
/// Stages are not said one by one while a move plays: at full speed they last from a sixth of a second to two and a
/// half seconds, too short to be said. The slider goes through a move stage by stage instead.
///
/// What a jump says, what a drag of the slider says, and when the lesson keeps quiet, ``PlayState`` decides.
public struct Narration: Sendable, Equatable {
    public enum Line: Sendable, Equatable {
        /// A request started a move playing: the status as it begins, `.playing`.
        case began(PuzzleSession.Status)
        /// A move ended by playing: `ring` is now on or off, as `state` has it.
        case ended(ring: Int, state: PuzzleState)
        /// A request stopped a move part way: the status there, `.paused`.
        case paused(PuzzleSession.Status)
        /// The rule refused `ring`: `block` names the ring in the way.
        case refused(ring: Int, block: PuzzleState.Block)
        /// The toy was set somewhere at once, as Reset does: what it is now.
        case rested(ToySummary)
    }

    /// What is said, in order.
    public var lines: [Line] = []

    public init(_ lines: [Line] = []) {
        self.lines = lines
    }

    /// What is said going from `before` to `after` by playing or by a request. `refused` is the ring the rule just
    /// refused, as ``Hearing`` finds it.
    public init(from before: PuzzleSession, to after: PuzzleSession, refused: Int? = nil) {
        if before.isPlaying, !after.isBusy {
            if after.made.count == before.made.count + 1, let move = after.made.last {
                lines.append(.ended(ring: move.ring, state: after.state))
            } else if after.made.count == before.made.count - 1, let move = before.made.last {
                lines.append(.ended(ring: move.ring, state: after.state))
            }
        }
        if after.isPlaying, !before.isPlaying || before.direction != after.direction {
            lines.append(.began(after.status))
        }
        if before.isPlaying, !after.isPlaying, case .paused = after.status {
            lines.append(.paused(after.status))
        }
        if let refused, case .blocked(refused, let block)? = after.note {
            lines.append(.refused(ring: refused, block: block))
        }
    }

    public var isEmpty: Bool { lines.isEmpty }
}
