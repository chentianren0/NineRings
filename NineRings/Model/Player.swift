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

    @ObservationIgnored private var session: PuzzleSession
    /// Where the toy's sound and touch go (none while capturing frames), the session as last heard, and the ring just
    /// tapped, if that is what changed it.
    @ObservationIgnored private let sound = ToySound.shared
    @ObservationIgnored private var heard: PuzzleSession
    @ObservationIgnored private var tapped: Int?

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
    var speed: PlaybackSpeed = .normal

    /// When playing was last moved on, so that the next step covers exactly the time since.
    @ObservationIgnored private var lastStep: ContinuousClock.Instant?

    /// A session with every ring on.
    init() {
        session = PuzzleSession()
        heard = session
        publish()
    }

    /// A session at the start of `move`, with that move on the slider at `progress`.
    init(move: Move, progress: Double = 0) {
        session = PuzzleSession(at: move, progress: progress)
        heard = session
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

    var hasMove: Bool { !stages.isEmpty }

    // MARK: Requests

    func tap(_ ring: Int) {
        tapped = ring
        session.tap(ring)
        publish()
    }

    func togglePlay() {
        session.togglePlay()
        publish()
    }

    func pause() {
        session.pause()
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
        session.reset()
        publish()
    }

    /// Sets the toy where `move` begins and plays it. The screen covers the toy while it jumps there.
    func begin(at move: Move) {
        session = PuzzleSession(at: move)
        session.togglePlay()
        publish()
    }

    /// Moves playing on to where the clock has reached. Called once a frame.
    func update() {
        let now = ContinuousClock.now
        defer { lastStep = session.isPlaying ? now : nil }
        defer { sound?.frame(session) }
        guard session.isPlaying, let lastStep else { return }
        let elapsed = now - lastStep
        // One frame's step is capped, so that after a pause in the frames, such as time in the background, the move
        // carries on from where it was rather than jumping to its end.
        let seconds = min(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, 0.1)
        session.advance(by: seconds * speed.factor)
        publish()
    }

    /// Copies what the views read out of the session. Each property is Equatable, so setting it to the value it
    /// already has notifies nobody.
    private func publish() {
        sound?.hear(Hearing(from: heard, to: session, tapped: tapped))
        heard = session
        tapped = nil
        shownProgress = session.progress
        isPlaying = session.isPlaying
        markers = session.markers
        status = session.status
        stages = session.stages
        canPlay = session.canPlay
        canUndo = session.canUndo
        canSolve = session.canSolve
    }
}
