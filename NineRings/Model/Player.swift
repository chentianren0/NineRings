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

    /// The person's toy, the lesson when it is open, and the congratulation, with the rules for which changes are
    /// jumps and whose toy the congratulation follows (see `PlayState`). Each request is passed on to it.
    @ObservationIgnored private var play: PlayState
    /// Where the toy's sound and touch go (see `SoundListener`); silent while capturing frames.
    @ObservationIgnored private let sound = SoundListener()

    /// The toy as it is shown: the lesson's while the lesson is open.
    private var session: PuzzleSession { play.toy }
    private var lesson: LessonRun? { play.lesson }

    /// How far through the move on the slider the toy is. Setting it is what dragging the slider does.
    var progress: Double {
        get { shownProgress }
        set {
            change { $0.scrub(to: newValue) }
        }
    }
    /// Whether the slider is being dragged: the toy is kept once the drag ends, not at every value on the way.
    @ObservationIgnored private var isDragging = false
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
    /// Whether the person is setting the rings by hand: a ring asked for goes on or comes off at once, and nothing else
    /// moves the toy.
    private(set) var isSettingRings = false

    /// When playing was last moved on, so that the next step covers exactly the time since.
    @ObservationIgnored private var lastStep: ContinuousClock.Instant?
    /// Where the toy is kept between launches and finished plays are recorded; nil when nothing is kept.
    @ObservationIgnored private let keeper: Keeper?
    /// Since when the app has been in front with its time not yet given to the play; nil while it is not in front.
    @ObservationIgnored private var frontSince: ContinuousClock.Instant?

    /// A session with every ring on, keeping nothing.
    init() {
        play = PlayState()
        keeper = nil
        publish()
    }

    /// The toy as `keeper` kept it, or every ring on when it kept none; kept there from now on. A toy read later, as
    /// GameSave's folder loads, comes through `take(_:)`.
    init(keeper: Keeper) {
        play = keeper.keptPlay() ?? PlayState()
        self.keeper = keeper
        publish()
    }

    /// A session at the start of `move`, with that move on the slider at `progress`, kept in `keeper` from now on when
    /// one is given.
    init(move: Move, progress: Double = 0, keeper: Keeper? = nil) {
        play = PlayState(PuzzleSession(at: move, progress: progress))
        self.keeper = keeper
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

    /// How many times the toy has jumped: been set at once where some of its parts are somewhere else (see `PlayState`).
    /// The 3D view shows a jump as those parts fading across, and reads this once a frame, unobserved.
    var jumps: Int { play.jumps }

    /// The state the ring buttons show: while a move is in hand, the one the toy is about to be in (see
    /// `PlayState.markers`). Read through the markers, so that a view reading it follows it.
    var shownState: PuzzleState {
        PuzzleState(bits: markers.reduce(0) { $1.isOn ? $0 | 1 << ($1.ring - 1) : $0 })
    }

    /// The name of the stage the slider is in, as written for making the move; empty before the first move.
    var stageName: String {
        session.motion?.stage(at: session.progress).name ?? ""
    }

    // MARK: Requests

    func tap(_ ring: Int) {
        change { $0.tap(ring) }
    }

    func togglePlay() {
        change { $0.togglePlay() }
    }

    /// Stops the move part way.
    func pause() {
        change { $0.pause() }
    }

    func undo() {
        change { $0.undo() }
    }

    func solve() {
        change { $0.solve() }
    }

    /// Back to every ring on, at once.
    func reset() {
        change { $0.reset() }
    }

    /// Sets the toy where `move` begins and plays it, with the lesson closed.
    func begin(at move: Move) {
        change { $0.begin(at: move) }
    }

    /// Makes `snapshot`'s toy the person's own, as a toy read from where it is kept arrives (see `PlayState.take`).
    /// Returns whether it did: not when it is the toy in play.
    @discardableResult
    func take(_ snapshot: ToySnapshot) -> Bool {
        var took = false
        change { took = $0.take(snapshot) }
        return took
    }

    // MARK: Setting the rings

    /// Starts setting the rings by hand, from the rings the toy has now. When a move is in hand the toy goes to rest at
    /// once.
    func startSettingRings() {
        change { $0.startSettingRings() }
    }

    /// Sets the rings to `state` at once, while they are being set.
    func setRings(to state: PuzzleState) {
        change { $0.setRings(to: state) }
    }

    /// Makes the rings as set the toy, resting there with no move made.
    func finishSettingRings() {
        change { $0.finishSettingRings() }
    }

    /// Gives the toy back as it was before the rings were set.
    func cancelSettingRings() {
        change { $0.cancelSettingRings() }
    }


    /// Hides the congratulation, as its Done button does.
    func dismissCongratulation() {
        play.dismissCongratulation()
        isCongratulating = false
    }

    /// Moves playing on to where the clock has reached. Called once a frame.
    func update() {
        let now = ContinuousClock.now
        defer { lastStep = session.isPlaying ? now : nil }
        defer { sound.frame(travel: play.frame()) }
        guard session.isPlaying, let lastStep else { return }
        let elapsed = now - lastStep
        // One frame's step is capped, so that after a pause in the frames, such as time in the background, the move
        // carries on from where it was rather than jumping to its end.
        let seconds = min(Self.seconds(elapsed), 0.1)
        change { $0.advance(by: seconds * speed.factor) }
    }

    // MARK: Keeping the play

    /// Makes `request` to the play: the time in front so far goes to the play first, so that a play finished by it has
    /// all of its time; then a finished play is recorded, the toy is kept when nothing is playing and the slider is not
    /// being dragged, and the views follow.
    private func change(_ request: (inout PlayState) -> Void) {
        giveTimeToPlay()
        request(&play)
        if let finished = play.finished { keeper?.record(finished) }
        if !play.toy.isPlaying && !isDragging { keeper?.keep(play.snapshot) }
        publish()
    }

    /// The slider is being dragged, or has been let go: playing stops as the drag begins, and the toy is kept as it ends.
    func dragging(_ isDragging: Bool) {
        self.isDragging = isDragging
        if isDragging {
            pause()
        } else if !play.toy.isPlaying {
            keeper?.keep(play.snapshot)
        }
    }

    /// The app has come to the front: its time counts toward the play from now.
    func cameToFront() {
        guard frontSince == nil else { return }
        frontSince = .now
    }

    /// The app has left the front, or is quitting: its time stops counting, and the toy is kept as it is, a move
    /// playing as stopped where it is.
    func leftFront() {
        giveTimeToPlay()
        frontSince = nil
        keeper?.keep(play.snapshot)
    }

    private func giveTimeToPlay() {
        guard let since = frontSince else { return }
        let now = ContinuousClock.now
        play.spend(Self.seconds(now - since))
        frontSince = now
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Copies what the views read out of the session. Each property is Equatable, so setting it to the value it
    /// already has notifies nobody.
    private func publish() {
        shownProgress = session.progress
        isPlaying = session.isPlaying
        markers = play.markers
        status = session.status
        stages = session.stages
        canPlay = lesson?.canPlay ?? session.canPlay
        canUndo = lesson?.canUndo ?? session.canUndo
        canSolve = !play.isSettingRings && (lesson?.canSolve ?? session.canSolve)
        hasMove = lesson?.canScrub ?? !stages.isEmpty
        lessonPage = lesson?.page
        isCongratulating = play.isCongratulating
        isSettingRings = play.isSettingRings
        sound.publish(play.hearing, congratulates: play.congratulates)
        GameCenter.shared.earn(play.earned)
        Announcer.say(play.narration)
    }

    // MARK: Lesson

    /// The lesson's step and what can be done on it, while the lesson is open.
    private(set) var lessonPage: LessonRun.Page?

    var isInLesson: Bool { lesson != nil }

    /// Whether the lesson holds the toy, so that ring taps, undo, solve and the slider do nothing: open, on a step
    /// that shows something of its own rather than give the toy back.
    var lessonHoldsToy: Bool { lessonPage.map { !$0.givesToyBack } ?? false }

    /// Opens the lesson at step `index`, counted from 0, keeping the toy as it is to give back on closing.
    func openLesson(at index: Int = 0) {
        guard lesson == nil else { return }
        change { $0.openLesson(at: index) }
    }

    /// Closes the lesson: the toy is as it was before, or, on the step that gave it back, as the person has it there.
    func closeLesson() {
        guard lesson != nil else { return }
        change { $0.closeLesson() }
    }

    /// Goes to step `index` of the lesson and plays it from its start.
    func goToLessonStep(_ index: Int) {
        guard isInLesson else { return }
        change { $0.goToLessonStep(index) }
    }

    #if DEBUG
    // MARK: Store pictures

    /// A player over `session`, kept in `keeper`, for the store-capture mode, which sets up states the other
    /// initializers do not.
    init(session: PuzzleSession, keeper: Keeper) {
        play = PlayState(session)
        self.keeper = keeper
        publish()
    }

    /// For the store-capture mode: plays lesson step `index` from its start at once, as far as `progress` through its
    /// move, and holds it there, so that every launch gives the same picture.
    func holdLessonStep(_ index: Int, at progress: Double) {
        guard lesson != nil else { return }
        play.goToLessonStep(index)
        // Going to a step that finishes a move toggles play: if the toy was already playing from that point, it stops.
        if !play.toy.isPlaying { play.togglePlay() }
        var steps = 0
        while let run = lesson, run.isShowing, run.toy.progress < progress, steps < 100_000 {
            play.advance(by: 1.0 / 600)
            steps += 1
        }
        play.pause()
        publish()
    }
    #endif
}
