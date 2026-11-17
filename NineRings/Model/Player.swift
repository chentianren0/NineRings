import Foundation
import Motion
import Observation
import Puzzle
import Session
import Toy

/// How fast moves play: slower, to follow a move, or faster, to watch many.
enum PlaybackSpeed: String, CaseIterable, Identifiable {
    case quarter, half, normal, double, quadruple

    var id: Self { self }

    /// How many times the normal pace.
    var factor: Double {
        switch self {
        case .quarter: 0.25
        case .half: 0.5
        case .normal: 1
        case .double: 2
        case .quadruple: 4
        }
    }
}

/// The puzzle being played, as the screen sees it: a `PuzzleSession` with a clock to play it and a speed.
///
/// The session holds every rule; this only moves it on in time and keeps what the views read as separate
/// properties, each changed only when its value does, so that a view redraws only when what it shows changes.
/// The pose is a pure function of the session, so nothing here depends on time except playing.
@MainActor
@Observable
final class Player {
    /// Each ring's move from where it first comes off on the way from every ring on to every ring off: where `-move N`
    /// and the capture mode start. Every move plays when its ring is tapped.
    static let moves = MoveMotion.written

    /// The toy as the person plays it. While the lesson is open, it waits, and the lesson's toy is shown instead.
    @ObservationIgnored private var ownSession: PuzzleSession
    /// The lesson, while it is open.
    @ObservationIgnored private var lesson: LessonRun?

    /// The toy as it is shown: the lesson's while the lesson is open. A change made to it while the lesson is open
    /// reaches the toy only on the step that gives the person's toy back, the last; on the others it does nothing.
    private var session: PuzzleSession {
        get { lesson?.toy ?? ownSession }
        set {
            if lesson != nil {
                lesson?.useToy { $0 = newValue }
            } else {
                ownSession = newValue
            }
        }
    }
    /// The person's toy as it was last published, so that each change to it can be seen whole.
    @ObservationIgnored private var published: PuzzleSession
    @ObservationIgnored private var congratulation = Congratulation()
    /// Where the toy's sound and touch go (see `SoundListener`); silent while capturing frames.
    @ObservationIgnored private let sound = SoundListener()

    /// How far through the move on the slider the toy is. Setting it is what dragging the slider does.
    var progress: Double {
        get { shownProgress }
        set {
            session.scrub(to: newValue)
            publish()
        }
    }
    private var shownProgress: Double = 0
    private(set) var isPlaying = false
    private(set) var markers: [PuzzleSession.Marker] = []
    private(set) var status: PuzzleSession.Status = .resting(.allOn)
    /// The stages of the move on the slider; empty before the first move.
    private(set) var stages: [Stage] = []
    private(set) var canPlay = false
    private(set) var canUndo = false
    private(set) var canSolve = false
    /// Whether the slider may be dragged: there is a move on it, and the lesson, if open, leaves the toy free.
    private(set) var hasMove = false
    var speed: PlaybackSpeed = .normal
    /// Whether the congratulation shows: the person's own move has just taken the last ring off, and nothing has
    /// been done with the toy since.
    private(set) var isCongratulating = false

    /// When playing was last moved on, so that the next step covers exactly the time since.
    @ObservationIgnored private var lastStep: ContinuousClock.Instant?

    /// A session with every ring on.
    init() {
        ownSession = PuzzleSession()
        published = ownSession
        publish()
    }

    /// A session at the start of `move`, with that move on the slider at `progress`.
    init(move: Move, progress: Double = 0) {
        ownSession = PuzzleSession(at: move, progress: progress)
        published = ownSession
        publish()
    }

    /// What decides the pose: when none of it changes, the toy need not be drawn again.
    struct PoseKey: Equatable {
        var move: Move?
        var progress: Double
        var state: PuzzleState
    }

    var poseKey: PoseKey {
        PoseKey(move: session.current, progress: session.progress, state: session.state)
    }

    /// The toy as it is now.
    var pose: ToyPose { session.pose }

    /// The name of the stage the slider is in, as written for making the move; empty before the first move.
    var stageName: String {
        session.motion?.stage(at: session.progress).name ?? ""
    }

    // MARK: Requests

    func tap(_ ring: Int) {
        sound.tap(ring)
        session.tap(ring)
        publish()
    }

    func togglePlay() {
        if lesson != nil { lesson?.togglePlay() } else { session.togglePlay() }
        publish()
    }

    func pause() {
        if lesson != nil { lesson?.pause() } else { session.pause() }
        publish()
    }

    func undo() {
        session.undo()
        publish()
    }

    func solve() {
        session.solve()
        publish()
    }

    /// Back to every ring on, at once. The screen covers the toy while this happens.
    func reset() {
        if lesson != nil { lesson?.reset() } else { session.reset() }
        publish()
    }

    /// Sets the toy where `move` begins and plays it. The screen covers the toy while it jumps there.
    func begin(at move: Move) {
        lesson = nil
        session = PuzzleSession(at: move)
        session.togglePlay()
        publish()
    }

    /// Hides the congratulation, as its Done button does.
    func dismissCongratulation() {
        congratulation.dismiss()
        isCongratulating = false
    }

    /// Moves playing on to where the clock has reached. Called once a frame.
    func update() {
        let now = ContinuousClock.now
        defer { lastStep = session.isPlaying ? now : nil }
        defer { sound.frame(session) }
        guard session.isPlaying, let lastStep else { return }
        let elapsed = now - lastStep
        // One frame's step is capped, so that after a pause in the frames, such as time in the background, the move
        // carries on from where it was rather than jumping to its end.
        let seconds = min(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, 0.1)
        if lesson != nil { lesson?.advance(by: seconds * speed.factor) } else { session.advance(by: seconds * speed.factor) }
        publish()
    }

    /// Copies what the views read out of the session. Each property is Equatable, so setting it to the value it
    /// already has notifies nobody.
    private func publish() {
        shownProgress = session.progress
        isPlaying = session.isPlaying
        markers = session.markers
        status = session.status
        stages = session.stages
        canPlay = lesson?.canPlay ?? session.canPlay
        canUndo = lesson?.canUndo ?? session.canUndo
        canSolve = lesson?.canSolve ?? session.canSolve
        hasMove = lesson?.canScrub ?? !stages.isEmpty
        lessonPage = lesson?.page
        // The congratulation follows the person's own toy, and is hidden while the lesson shows its own.
        if lesson != nil {
            congratulation.dismiss()
        } else {
            congratulation.update(from: published, to: ownSession)
        }
        published = ownSession
        isCongratulating = congratulation.isShowing
        sound.publish(session, isCongratulating: isCongratulating)
    }

    // MARK: Lesson

    /// The lesson's step and what can be done on it, while the lesson is open.
    private(set) var lessonPage: LessonRun.Page?

    var isInLesson: Bool { lesson != nil }

    /// Whether the lesson holds the toy, so that ring taps, undo, solve and the slider do nothing: open, on a step
    /// that shows something of its own rather than give the toy back.
    var lessonHoldsToy: Bool { lessonPage.map { !$0.givesToyBack } ?? false }

    /// Opens the lesson at step `index`, counted from 0, keeping the toy as it is to give back on closing. The screen
    /// covers the toy while every ring goes on.
    func openLesson(at index: Int = 0) {
        guard lesson == nil else { return }
        lesson = LessonRun(opening: ownSession, at: index)
        publish()
    }

    /// Closes the lesson: the toy is as it was before, or, on the step that gave it back, as the person has it there.
    func closeLesson() {
        guard let lesson else { return }
        ownSession = lesson.closingToy
        self.lesson = nil
        publish()
    }

    /// Goes to step `index` of the lesson and plays it from its start.
    func goToLessonStep(_ index: Int) {
        lesson?.go(to: index)
        publish()
    }

    /// Whether going to step `index` moves the toy to another pose at once, so that the screen should cover it.
    func lessonJumps(to index: Int) -> Bool {
        lesson?.jumps(to: index) ?? false
    }

    /// Whether closing the lesson moves the toy to another pose at once.
    var lessonClosingJumps: Bool { lesson?.closingJumps ?? false }

    #if DEBUG
    // MARK: Store pictures

    /// A player over `session`, for the store-capture mode, which sets up states the other initializers do not.
    init(session: PuzzleSession) {
        ownSession = session
        published = session
        publish()
    }

    /// For the store-capture mode: plays lesson step `index` from its start at once, as far as `progress` through its
    /// move, and holds it there, so that every launch gives the same picture.
    func holdLessonStep(_ index: Int, at progress: Double) {
        guard lesson != nil else { return }
        lesson?.go(to: index)
        // Going to a step that finishes a move toggles play: if the toy was already playing from that point, it stops.
        if lesson?.toy.isPlaying == false { lesson?.togglePlay() }
        var steps = 0
        while let run = lesson, run.isShowing, run.toy.progress < progress, steps < 100_000 {
            lesson?.advance(by: 1.0 / 600)
            steps += 1
        }
        lesson?.pause()
        publish()
    }
    #endif
}
