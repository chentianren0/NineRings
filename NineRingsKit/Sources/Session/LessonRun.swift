import Motion
import Puzzle
import simd
import Toy

/// The lesson while it is open: which step is up, and the toy as the lesson shows it.
///
/// It holds no clock and no text, like ``PuzzleSession``: whoever drives it calls `advance(by:)` and turns `page` and
/// `toy` into words and pictures.
///
/// The rules it keeps:
/// - Opening it remembers the toy as it was, paused, and shows the first step (or the one asked for) from its start.
/// - Going to a step, by next, back or play again, always puts the toy in that step's start and plays the step's
///   showing from there: a step at rest rests, a step's moves play one after another, a hold plays its move and
///   stops exactly at ``LessonStep/heldProgress``, and a finish plays the rest of that move from there. Inside a step
///   the toy never jumps. When the toy is already where the next step starts, as it is when the step before has
///   played to its end, it goes on from there without a jump; otherwise it is set there at once, and `jumps(to:)` says
///   so beforehand, so that the screen can cover the toy while it does.
/// - Next while a step is still playing goes on at once: the toy is set to the next step's start, which is where the
///   step playing was heading.
/// - On a step that shows something, the toy belongs to the lesson: ring taps, undo, solve and the slider do nothing,
///   and play only pauses and resumes the step's showing. Reset goes back to the first step.
/// - A step that gives the toy back (``LessonStep/Show/givenBack``, the last step, "your turn") shows the person's own
///   toy, with its history, and every request reaches it: whatever they do there is theirs. When their toy rests where
///   the lesson begins, every ring on, the lesson's moves are made on it, so that it goes on from where the lesson
///   ended, with no jump, and undo takes them back; they are played for the person, not by them
///   (``movesPlayedForThePerson``). Otherwise it is as it was before the lesson. Going from that step to another takes
///   the toy again, remembering it as it is then, the lesson's moves included, so that they are made once.
/// - Closing gives back the toy as it was before the lesson; on a step that has given it back already, closing
///   changes nothing.
/// - The person's own toy can be replaced while the lesson is open, as when it arrives from another device
///   (``replaceOwnToy(with:)``): the lesson stays at its step and gives back the new toy on closing. On a step that
///   gives the toy back, the toy shown is the new one, with no moves played for the person.
public struct LessonRun: Sendable, Equatable {
    /// What the lesson's panel shows, apart from the toy: it changes only when the step or what can be done does.
    public struct Page: Sendable, Equatable {
        /// The step up, counted from 0.
        public let index: Int
        public let count: Int
        /// The key of the step's text in the app's `Lesson` String Catalog.
        public let key: String
        public let view: LessonStep.View
        public let canGoBack: Bool
        public let canGoForward: Bool
        /// Whether the step plays something, so that it can be played again.
        public let canReplay: Bool
        /// Whether the step gives the person's own toy back to play with: the last step, "your turn".
        public let givesToyBack: Bool

        public var isLast: Bool { index == count - 1 }
    }

    public let steps: [LessonStep]
    /// The step up, counted from 0.
    public private(set) var index: Int
    /// The toy as the lesson shows it.
    public private(set) var toy: PuzzleSession
    /// The person's own toy, as it was when the lesson opened, or when it last took the toy again, paused. On a step
    /// that gives the toy back, `toy` is the person's toy, and this is where it was when given back.
    public private(set) var before: PuzzleSession
    /// On the step that gives the toy back, the moves the lesson made on it as it gave it: the lesson's moves, when the
    /// toy rested where the lesson begins, or none. Empty on the other steps. They are the person's moves now, played
    /// for them rather than by them.
    public private(set) var movesPlayedForThePerson: [Move] = []

    /// Opens the lesson over `toy` at step `index`, counted from 0, with every ring on.
    public init(opening toy: PuzzleSession, steps: [LessonStep] = Lesson.steps, at index: Int = 0) {
        precondition(!steps.isEmpty, "a lesson has steps")
        var before = toy
        before.pause()
        self.before = before
        self.steps = steps
        self.index = min(max(index, 0), steps.count - 1)
        self.toy = PuzzleSession()
        enter(givenBackAlready: false)
    }

    // MARK: - What it shows

    public var step: LessonStep { steps[index] }

    public var page: Page {
        Page(
            index: index,
            count: steps.count,
            key: step.key,
            view: step.view,
            canGoBack: index > 0,
            canGoForward: index < steps.count - 1,
            canReplay: step.plays,
            givesToyBack: givesToyBack
        )
    }

    /// Whether the step gives the person's own toy back to play with.
    public var givesToyBack: Bool { step.show == .givenBack }

    /// Whether the step's showing is still under way: playing, or paused before its end.
    public var isShowing: Bool {
        !givesToyBack && toy.isBusy && !isAtHold
    }

    /// Whether play would do something: resume the step's showing, or, where the toy is given back, what play does on it.
    public var canPlay: Bool {
        givesToyBack ? toy.canPlay : isShowing && !toy.isPlaying
    }

    public var canUndo: Bool { givesToyBack && toy.canUndo }
    public var canSolve: Bool { givesToyBack && toy.canSolve }
    /// Whether the slider may be dragged.
    public var canScrub: Bool { givesToyBack && toy.current != nil }

    /// The toy once the lesson is closed: the person's own, as it was before, or as it is where it has been given back.
    public var closingToy: PuzzleSession {
        givesToyBack ? toy : before
    }

    /// Makes `toy`, paused, the person's own toy: the toy given back on closing, and on a step that gives the toy back,
    /// the toy shown, with no moves played for the person. The lesson stays at its step.
    public mutating func replaceOwnToy(with toy: PuzzleSession) {
        var own = toy
        own.pause()
        before = own
        if givesToyBack {
            self.toy = own
            movesPlayedForThePerson = []
        }
    }

    /// Whether going to step `index` would move the toy to another pose at once, rather than go on from where it is.
    public func jumps(to index: Int) -> Bool {
        var next = self
        next.go(to: index)
        return !next.toy.pose.isClose(to: toy.pose)
    }

    /// Whether playing the step again would move the toy at once.
    public var replayJumps: Bool { jumps(to: index) }

    /// Whether closing would move the toy at once.
    public var closingJumps: Bool { !closingToy.pose.isClose(to: toy.pose) }

    /// Where the move on the toy stops, when the step holds it.
    private var stop: Double? {
        guard case .hold = step.show else { return nil }
        return step.heldProgress
    }

    private var isAtHold: Bool {
        guard let stop, case .hold(let move, _) = step.show else { return false }
        return toy.current == move && toy.progress >= stop
    }

    // MARK: - What it does

    public mutating func goForward() {
        go(to: index + 1)
    }

    public mutating func goBack() {
        go(to: index - 1)
    }

    /// Plays the step again from its start.
    public mutating func replay() {
        go(to: index)
    }

    /// Goes to step `index`, counted from 0, and plays its showing from its start.
    public mutating func go(to newIndex: Int) {
        let newIndex = min(max(newIndex, 0), steps.count - 1)
        let givenBackAlready = givesToyBack
        if givenBackAlready && steps[newIndex].show != .givenBack {
            // The lesson takes the toy again: it remembers it as it is now, and starts afresh.
            var own = toy
            own.pause()
            before = own
            toy = PuzzleSession()
            movesPlayedForThePerson = []
        }
        index = newIndex
        enter(givenBackAlready: givenBackAlready)
    }

    /// Moves playing on by `seconds` of the move's own time, as ``PuzzleSession/advance(by:)`` does, stopping a held
    /// move exactly where the step holds it.
    public mutating func advance(by seconds: Double) {
        guard toy.isPlaying, seconds > 0 else { return }
        if let stop, case .hold(let move, _) = step.show, toy.current == move, toy.direction == .forward {
            let timing = MoveMotion(move).timing
            if timing.time(atProgress: toy.progress) + seconds >= timing.time(atProgress: stop) {
                toy.scrub(to: stop)
                return
            }
        }
        toy.advance(by: seconds)
    }

    /// Pauses the step's showing, or resumes it; where the toy is given back, what play does on it.
    public mutating func togglePlay() {
        if givesToyBack {
            toy.togglePlay()
        } else if toy.isPlaying {
            toy.pause()
        } else if canPlay {
            toy.togglePlay()
        }
    }

    public mutating func pause() {
        toy.pause()
    }

    /// Where the toy is given back, every ring on, as the toy's Reset does; on the other steps, back to the first step,
    /// which shows every ring on.
    public mutating func reset() {
        if givesToyBack {
            toy.reset()
        } else {
            go(to: 0)
        }
    }

    /// Makes `change` to the toy, as a ring tap, undo, solve or a drag of the slider does, where the toy is given back.
    /// On the other steps it does nothing.
    public mutating func useToy(_ change: (inout PuzzleSession) -> Void) {
        guard givesToyBack else { return }
        change(&toy)
    }

    // MARK: - Inside

    /// Puts the toy in the step's start, going on from where it is when it is there already, and begins the step's
    /// showing; or gives the person's toy back, unless it is theirs already, with the lesson's moves made on it when
    /// it rests where they begin.
    private mutating func enter(givenBackAlready: Bool) {
        let step = step
        switch step.show {
        case .givenBack:
            guard !givenBackAlready else { return }
            toy = before
            let moves = lessonMoves
            if let first = moves.first, !toy.isBusy, toy.state == first.from {
                toy.make(moves)
                movesPlayedForThePerson = moves
            }
        case .rest(let state):
            if !isResting(in: state) {
                toy = PuzzleSession(resting: state)
            }
        case .play(let moves):
            playFromRest(moves)
        case .hold(let move, _):
            playFromRest([move])
        case .finish(let move, _):
            guard let held = step.heldProgress else { preconditionFailure("\(step.key) finishes at a stage its move has") }
            if toy.current != move || toy.progress != held {
                toy = PuzzleSession(at: move, progress: held)
            }
            toy.togglePlay()
        }
    }

    /// Plays `moves` one after another from the first one's start: from where the toy is, when it rests there.
    private mutating func playFromRest(_ moves: [Move]) {
        if !isResting(in: moves[0].from) {
            toy = PuzzleSession(resting: moves[0].from)
        }
        // With the first move playing, each ring after it waits in the toy's queue and begins when the one before ends.
        for move in moves {
            toy.tap(move.ring)
        }
    }

    private func isResting(in state: PuzzleState) -> Bool {
        !toy.isBusy && toy.state == state
    }

    /// The moves the lesson makes before the step that gives the toy back, in order: each move its steps play to the
    /// end, once. A held move is made by the step that finishes it.
    private var lessonMoves: [Move] {
        steps.prefix { $0.show != .givenBack }.flatMap { step -> [Move] in
            switch step.show {
            case .play(let moves): moves
            case .finish(let move, _): [move]
            case .rest, .hold, .givenBack: []
            }
        }
    }
}

extension LessonStep {
    /// Whether the step plays something, rather than rest or give the toy back.
    public var plays: Bool {
        switch show {
        case .play, .hold, .finish: true
        case .rest, .givenBack: false
        }
    }
}
