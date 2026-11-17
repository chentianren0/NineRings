import Motion

/// What the toy's commands can do now, for the menus and the keyboard: each command that cannot act is disabled,
/// never hidden.
///
/// It reads what the screen already shows, so that a menu and a button never disagree:
/// - A ring can be asked to move when the rule lets it move now. A ring the rule forbids is disabled, rather than
///   asked and refused: in a menu, the reason cannot be shown.
/// - While the lesson holds the toy, every command that would change the toy is disabled: moving a ring, undo,
///   solve, reset and the stage steps. Play and pause stay, because they play the lesson's own move.
/// - The stage steps move the slider to the next boundary between the move's stages, or the one before, as far as
///   the move's ends.
public struct ToyCommands: Sendable, Equatable {
    /// The rings, as the strip of markers shows them.
    public var markers: [PuzzleSession.Marker]
    public var canUndo: Bool
    public var canPlay: Bool
    public var isPlaying: Bool
    public var canSolve: Bool
    /// Whether the slider may be dragged.
    public var canScrub: Bool
    /// How far through the move on the slider the toy is.
    public var progress: Double
    /// The stages of the move on the slider; empty before the first move.
    public var stages: [Stage]
    public var lessonHoldsToy: Bool

    public init(
        markers: [PuzzleSession.Marker],
        canUndo: Bool,
        canPlay: Bool,
        isPlaying: Bool,
        canSolve: Bool,
        canScrub: Bool,
        progress: Double,
        stages: [Stage],
        lessonHoldsToy: Bool
    ) {
        self.markers = markers
        self.canUndo = canUndo
        self.canPlay = canPlay
        self.isPlaying = isPlaying
        self.canSolve = canSolve
        self.canScrub = canScrub
        self.progress = progress
        self.stages = stages
        self.lessonHoldsToy = lessonHoldsToy
    }

    /// Whether ring `ring` can be asked to move now.
    public func canMove(_ ring: Int) -> Bool {
        guard !lessonHoldsToy, let marker = markers.first(where: { $0.ring == ring }) else { return false }
        return marker.canMove
    }

    public var canUndoMove: Bool { canUndo && !lessonHoldsToy }

    /// Whether Play or Pause would do something.
    public var canPlayOrPause: Bool { isPlaying || canPlay }

    public var canSolvePuzzle: Bool { canSolve && !lessonHoldsToy }

    public var canReset: Bool { !lessonHoldsToy }

    /// Where Next Stage takes the slider, or nil when it cannot go on.
    public var nextStage: Double? {
        guard canScrub, !lessonHoldsToy else { return nil }
        return Self.boundary(after: progress, in: stages)
    }

    /// Where Previous Stage takes the slider, or nil when it cannot go back.
    public var previousStage: Double? {
        guard canScrub, !lessonHoldsToy else { return nil }
        return Self.boundary(before: progress, in: stages)
    }

    /// Two progresses closer than this are the same place: a boundary reached by a step is left by the next one.
    static let tolerance = 1e-6

    /// The places between stages, from the move's start to its end, in order.
    static func boundaries(of stages: [Stage]) -> [Double] {
        guard !stages.isEmpty else { return [] }
        let all = [0] + stages.map(\.start) + stages.map(\.end) + [1]
        return all.sorted().reduce(into: [Double]()) { result, value in
            if let last = result.last, value - last < tolerance { return }
            result.append(value)
        }
    }

    /// The first boundary past `progress`.
    public static func boundary(after progress: Double, in stages: [Stage]) -> Double? {
        boundaries(of: stages).first { $0 > progress + tolerance }
    }

    /// The last boundary short of `progress`.
    public static func boundary(before progress: Double, in stages: [Stage]) -> Double? {
        boundaries(of: stages).last { $0 < progress - tolerance }
    }
}
