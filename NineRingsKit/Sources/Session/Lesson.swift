import Motion
import Puzzle

/// The lesson that explains the puzzle: steps, each with a text and what the toy shows while that text is up.
///
/// The lesson plays the first six moves of the shortest way from every ring on to every ring off, so each step
/// starts where the last one ended and the toy never jumps: ring 1 off, ring 3 off, ring 1 on, ring 2 off, ring 1 off,
/// ring 5 off. Ring 3's move is held after the sword has moved away, where the reason for the rule can be seen. The last
/// step, "your turn", gives the person's own toy back, as it was before the lesson, to play with while its text is up.
///
/// The words are not here. Each step names its text by a key in the app's `Lesson` String Catalog, where the English
/// and its translations live.
public enum Lesson {
    public static let steps: [LessonStep] = [
        LessonStep(key: "lesson.toy", show: .rest(.allOn)),
        LessonStep(key: "lesson.rodsAndBar", show: .rest(.allOn)),
        LessonStep(key: "lesson.sword", show: .rest(.allOn), view: .top),
        LessonStep(key: "lesson.ringOneOff", show: .play([move(1, from: "111111111")])),
        LessonStep(key: "lesson.rule", show: .rest(state("011111111"))),
        LessonStep(key: "lesson.swordMovesAway", show: .hold(move(3, from: "011111111"), afterStage: "Sword moves away")),
        LessonStep(key: "lesson.downThroughTheSlot", show: .finish(move(3, from: "011111111"), afterStage: "Sword moves away")),
        LessonStep(key: "lesson.goingBackOn", show: .play([move(1, from: "010111111"), move(2, from: "110111111")])),
        LessonStep(key: "lesson.ringOneOffAgain", show: .play([move(1, from: "100111111")])),
        LessonStep(key: "lesson.sameMoveFurtherAlong", show: .play([move(5, from: "000111111")])),
        LessonStep(key: "lesson.twoMoves", show: .rest(state("000101111"))),
        LessonStep(key: "lesson.yourTurn", show: .givenBack),
    ]

    private static func state(_ text: String) -> PuzzleState {
        guard let state = PuzzleState(text) else { preconditionFailure("not a state: \(text)") }
        return state
    }

    private static func move(_ ring: Int, from text: String) -> Move {
        guard let move = Move(ring: ring, from: state(text)) else { preconditionFailure("ring \(ring) cannot move in \(text)") }
        return move
    }
}

/// One step of the lesson.
public struct LessonStep: Sendable, Equatable {
    /// What the toy shows while the step's text is up.
    public enum Show: Sendable, Equatable {
        /// The toy at rest in a state.
        case rest(PuzzleState)
        /// Moves played one after another, each from where the last one ended.
        case play([Move])
        /// A move played from its start through the stage named by `afterStage`, the stage's key, and held there.
        case hold(Move, afterStage: String)
        /// The rest of a move held at the end of the stage named by `afterStage`, played from there to its end.
        case finish(Move, afterStage: String)
        /// The person's own toy, given back as it was before the lesson, with its history, theirs to play with: the
        /// lesson shows nothing of its own.
        case givenBack
    }

    /// Where the toy is seen from. The app's camera has a preset for each.
    public enum View: Sendable, Equatable {
        case side
        case top
    }

    /// The key of the step's text in the app's `Lesson` String Catalog.
    public let key: String
    public let show: Show
    public let view: View

    public init(key: String, show: Show, view: View = .side) {
        self.key = key
        self.show = show
        self.view = view
    }

    /// The state the toy is in when the step begins. A held move has not been made yet. Nil when the step gives the
    /// person's own toy back, which may be in any state.
    public var start: PuzzleState? {
        switch show {
        case .rest(let state): state
        case .play(let moves): moves[0].from
        case .hold(let move, _), .finish(let move, _): move.from
        case .givenBack: nil
        }
    }

    /// The state the toy is in when the step's showing is over. A held move is not made, so it is still its start.
    /// Nil when the step gives the person's own toy back.
    public var end: PuzzleState? {
        switch show {
        case .rest(let state): state
        case .play(let moves): moves[moves.count - 1].to
        case .hold(let move, _): move.from
        case .finish(let move, _): move.to
        case .givenBack: nil
        }
    }

    /// Where a hold or a finish meets its move: the progress at the end of the named stage, or nil when the step holds
    /// nothing or the move has no stage of that name.
    ///
    /// It is the last progress value inside the stage rather than the stage's end itself, because at a boundary
    /// ``MoveMotion/stage(at:)`` gives the stage that begins there, and the status line should name the stage the move
    /// is held after.
    public var heldProgress: Double? {
        switch show {
        case .rest, .play, .givenBack:
            return nil
        case .hold(let move, let key), .finish(let move, let key):
            guard let stage = MoveMotion(move).stages.first(where: { $0.key == key }) else { return nil }
            return stage.end.nextDown
        }
    }
}
