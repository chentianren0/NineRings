import Motion
import Observation
import Puzzle
import Toy

/// How fast the move plays.
enum PlaybackSpeed: String, CaseIterable, Identifiable {
    case full, half, quarter

    var id: Self { self }

    var title: String {
        switch self {
        case .full: "Full"
        case .half: "Half"
        case .quarter: "Quarter"
        }
    }

    var factor: Double {
        switch self {
        case .full: 1
        case .half: 0.5
        case .quarter: 0.25
        }
    }
}

/// The move being shown and how far along it is: the slider and the play button drive it, and the 3D view
/// draws the pose it gives.
///
/// The pose is a pure function of the move and the progress, so nothing here depends on time except playing,
/// which only moves the progress on.
@MainActor
@Observable
final class Player {
    /// Ring 1 coming off every ring on. Progress 0 is every ring on, progress 1 is ring 1 off.
    let motion: MoveMotion
    /// The same move going the other way, for naming its stages when it plays backwards.
    let reverse: MoveMotion

    /// How far through the move, from 0 to 1. Whoever sets it keeps it in that range.
    var progress: Double
    var speed: PlaybackSpeed = .full {
        // Playing goes on from where it is, at the new speed.
        didSet { if isPlaying { anchorPlay() } }
    }
    private(set) var isPlaying = false
    /// Whether playing runs toward progress 1, taking the ring off; otherwise toward 0, putting it on.
    private(set) var playsForward = true
    /// Where and when playing last began or changed speed: the progress while playing is measured from here by
    /// the clock, so it keeps pace however often the window is drawn.
    @ObservationIgnored private var playAnchor: (progress: Double, time: ContinuousClock.Instant)?
    #if DEBUG
    /// When playing last began, to report how long a play-through took.
    @ObservationIgnored private var playStarted: ContinuousClock.Instant?
    #endif

    init(progress: Double = 0) {
        guard let off = Move(ring: 1, from: .allOn), let motion = MoveMotion(off), let reverse = MoveMotion(off.reversed) else {
            preconditionFailure("ring 1's move is written")
        }
        self.motion = motion
        self.reverse = reverse
        self.progress = min(max(progress, 0), 1)
    }

    /// The toy as it is now.
    var pose: ToyPose { motion.pose(at: progress) }

    /// The stage the move is in, named for the way it is going.
    var stageName: String {
        playsForward ? motion.stage(at: progress).name : reverse.stage(at: 1 - progress).name
    }

    /// What pressing play will do from here.
    var nextAction: String {
        if isPlaying { return "Pause" }
        return willPlayForward ? "Take ring 1 off" : "Put ring 1 on"
    }

    private var willPlayForward: Bool {
        if progress >= 1 { return false }
        if progress <= 0 { return true }
        return playsForward
    }

    /// Plays from here toward the end it is not at, or pauses.
    func togglePlay() {
        if isPlaying {
            isPlaying = false
            return
        }
        playsForward = willPlayForward
        isPlaying = true
        anchorPlay()
        #if DEBUG
        playStarted = .now
        #endif
    }

    /// Plays toward one end.
    func play(forward: Bool) {
        playsForward = forward
        isPlaying = forward ? progress < 1 : progress > 0
        anchorPlay()
    }

    private func anchorPlay() {
        playAnchor = (progress, .now)
    }

    func pause() {
        isPlaying = false
    }

    /// Moves the progress on to where playing has reached by now. Called once a frame.
    func update() {
        guard isPlaying, let playAnchor else { return }
        let elapsed = ContinuousClock.now - playAnchor.time
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let distance = seconds * speed.factor / MoveMotion.duration
        progress = min(max(playAnchor.progress + (playsForward ? distance : -distance), 0), 1)
        if progress <= 0 || progress >= 1 {
            isPlaying = false
            #if DEBUG
            if let playStarted {
                print("player: played to progress \(progress) at \(speed.title.lowercased()) speed in \(ContinuousClock.now - playStarted)")
            }
            #endif
        }
    }
}
