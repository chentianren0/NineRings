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
    var speed: PlaybackSpeed = .full
    private(set) var isPlaying = false
    /// Whether playing runs toward progress 1, taking the ring off; otherwise toward 0, putting it on.
    private(set) var playsForward = true

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
    }

    /// Plays toward one end.
    func play(forward: Bool) {
        playsForward = forward
        isPlaying = forward ? progress < 1 : progress > 0
    }

    func pause() {
        isPlaying = false
    }

    /// Moves the progress on by one frame of playing. A long gap between frames, as when the window was hidden,
    /// is not made up for.
    func advance(by seconds: Double) {
        guard isPlaying else { return }
        let step = min(seconds, 1.0 / 20) * speed.factor / MoveMotion.duration
        progress = min(max(progress + (playsForward ? step : -step), 0), 1)
        if progress <= 0 || progress >= 1 {
            isPlaying = false
        }
    }
}
