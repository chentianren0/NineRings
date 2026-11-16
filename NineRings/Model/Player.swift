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

/// The move being shown and how far along it is: the picker chooses the move, the slider and the play button
/// drive it, and the 3D view draws the pose it gives.
///
/// The pose is a pure function of the move and the progress, so nothing here depends on time except playing,
/// which only moves the progress on.
@MainActor
@Observable
final class Player {
    /// The moves that can be shown: each written move, coming off every ring on.
    static let moves = MoveMotion.written

    /// The move shown, coming off every ring on. Progress 0 is every ring on, progress 1 is its ring off.
    private(set) var motion: MoveMotion
    /// The same move going the other way, for naming its stages when it plays backwards.
    private(set) var reverse: MoveMotion

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

    init(move: Move? = nil, progress: Double = 0) {
        (motion, reverse) = Self.motions(of: move ?? Self.moves[0])
        self.progress = min(max(progress, 0), 1)
    }

    private static func motions(of move: Move) -> (MoveMotion, MoveMotion) {
        guard let motion = MoveMotion(move), let reverse = MoveMotion(move.reversed) else {
            preconditionFailure("only written moves are shown")
        }
        return (motion, reverse)
    }

    /// The move shown. Choosing another one stops playing and starts it from the beginning.
    var move: Move {
        get { motion.move }
        set {
            guard newValue != motion.move else { return }
            isPlaying = false
            (motion, reverse) = Self.motions(of: newValue)
            progress = 0
            playsForward = true
        }
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
        return willPlayForward ? "Take ring \(move.ring) off" : "Put ring \(move.ring) on"
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
