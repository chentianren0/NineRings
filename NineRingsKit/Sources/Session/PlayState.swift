import Motion
import Puzzle

/// The puzzle as the screen plays it: the person's own toy, the lesson when it is open, the congratulation, and what
/// is heard at each change.
///
/// Only here is it known which changes are jumps: Reset, opening and closing the lesson, going to a step, or starting
/// at a chosen move set the toy somewhere at once, under a cover, while a ring tap, play, undo, Solve, a drag or the
/// clock move it on. From the toy alone the two can look the same (a step played again looks like the slider dragged
/// back), so the rules that depend on it live here, where they can be tested, and the app's player only passes its
/// requests on.
///
/// The rules it keeps:
/// - A jump is silent: nothing is heard and the sword's slide hears no travel across it, whatever the toy before and
///   after. Every other change is heard as ``Hearing`` says.
/// - The congratulation follows the person's own toy: their toy when the lesson is closed, and, on the lesson's last
///   step, the toy it gives back. Arriving there, opening and closing the lesson, and going to another step are not
///   moves: they never congratulate, and hide the card. Solve never congratulates (see ``Congratulation``).
public struct PlayState: Sendable, Equatable {
    /// The person's own toy. While the lesson is open it waits, and the lesson's toy is shown instead.
    public private(set) var own: PuzzleSession
    /// The lesson, while it is open.
    public private(set) var lesson: LessonRun?
    public private(set) var congratulation = Congratulation()
    /// What the last change made heard.
    public private(set) var hearing = Hearing()
    /// Whether the last change was the moment to congratulate: the card has just appeared.
    public private(set) var congratulates = false

    /// The person's toy as the congratulation last saw it.
    private var judged: PuzzleSession
    /// The toy shown, as last heard, and as at the last frame.
    private var heard: PuzzleSession
    private var framed: PuzzleSession

    public init(_ toy: PuzzleSession = PuzzleSession()) {
        own = toy
        judged = toy
        heard = toy
        framed = toy
    }

    /// The toy as it is shown: the lesson's while the lesson is open.
    public var toy: PuzzleSession { lesson?.toy ?? own }

    public var isCongratulating: Bool { congratulation.isShowing }

    /// The person's toy, where it is shown: their own, or on the lesson's last step the toy it gives back; nil on the
    /// lesson's other steps.
    private var persons: PuzzleSession? {
        guard let lesson else { return own }
        return lesson.givesToyBack ? lesson.toy : nil
    }

    // MARK: - Changes that move the toy on

    /// A ring asked to move.
    public mutating func tap(_ ring: Int) {
        useToy { $0.tap(ring) }
        settle(tapped: ring)
    }

    public mutating func undo() {
        useToy { $0.undo() }
        settle()
    }

    public mutating func solve() {
        useToy { $0.solve() }
        settle()
    }

    /// A drag of the slider.
    public mutating func scrub(to progress: Double) {
        useToy { $0.scrub(to: progress) }
        settle()
    }

    public mutating func togglePlay() {
        if lesson != nil { lesson?.togglePlay() } else { own.togglePlay() }
        settle()
    }

    public mutating func pause() {
        if lesson != nil { lesson?.pause() } else { own.pause() }
        settle()
    }

    /// The clock: `seconds` of the move's own time, at the playing speed.
    public mutating func advance(by seconds: Double) {
        if lesson != nil { lesson?.advance(by: seconds) } else { own.advance(by: seconds) }
        settle()
    }

    public mutating func dismissCongratulation() {
        congratulation.dismiss()
        congratulates = false
    }

    // MARK: - Jumps

    /// Every ring on, at once: the toy's Reset, or on the lesson's steps but the last, back to its first step.
    public mutating func reset() {
        if lesson != nil { lesson?.reset() } else { own.reset() }
        settle(jump: true)
    }

    /// The toy set where `move` begins, playing it, with the lesson closed.
    public mutating func begin(at move: Move) {
        lesson = nil
        own = PuzzleSession(at: move)
        own.togglePlay()
        settle(jump: true, rebase: true)
    }

    /// Opens the lesson at step `index`, counted from 0, keeping the toy as it is to give back on closing.
    public mutating func openLesson(at index: Int = 0) {
        guard lesson == nil else { return }
        lesson = LessonRun(opening: own, at: index)
        settle(jump: true, rebase: true)
    }

    /// Closes the lesson: the toy is as it was before, or, on the step that gave it back, as the person has it there.
    public mutating func closeLesson() {
        guard let lesson else { return }
        own = lesson.closingToy
        self.lesson = nil
        settle(jump: true, rebase: true)
    }

    /// Goes to step `index` of the lesson and plays it from its start.
    public mutating func goToLessonStep(_ index: Int) {
        guard lesson != nil else { return }
        lesson?.go(to: index)
        settle(jump: true, rebase: true)
    }

    // MARK: - The slide

    /// How far the sword has travelled since the last frame, in millimetres; nothing across a jump.
    public mutating func frame() -> Double {
        let travel = Hearing(from: framed, to: toy).swordTravel
        framed = toy
        return travel
    }

    // MARK: - Inside

    /// A change to the toy shown, as a ring tap, undo, Solve or a drag makes it: on the lesson's steps but the last,
    /// nothing happens.
    private mutating func useToy(_ change: (inout PuzzleSession) -> Void) {
        if lesson != nil { lesson?.useToy(change) } else { change(&own) }
    }

    /// After a change: what is heard, and what the congratulation makes of it. A jump is heard as nothing. A change
    /// that `rebase`s is not a move of the person's toy: the congratulation hides and takes the toy as it now is.
    private mutating func settle(tapped: Int? = nil, jump: Bool = false, rebase: Bool = false) {
        let toy = toy
        hearing = jump ? Hearing() : Hearing(from: heard, to: toy, tapped: tapped)
        heard = toy
        if jump { framed = toy }
        let wasShowing = congratulation.isShowing
        if let persons {
            if rebase {
                congratulation.dismiss()
            } else {
                congratulation.update(from: judged, to: persons)
            }
            judged = persons
        } else {
            congratulation.dismiss()
        }
        congratulates = congratulation.isShowing && !wasShowing
    }
}
