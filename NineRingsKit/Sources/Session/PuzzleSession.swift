import Motion
import Puzzle
import Toy

/// A puzzle being played: the state, the moves made, the move on the slider and how far through it the toy is,
/// and the rings asked to move next.
///
/// It holds no clock and no text. Whoever drives it calls `advance(by:)` with how many seconds of the move's own time
/// have passed, at the speed it plays, and turns `status` and `markers` into words and pictures. Dragging the slider
/// goes by the move's progress, which the poses are a function of.
///
/// The rules it keeps:
/// - Tapping a ring asks to move it. A legal move plays; the state changes when it ends. A move the rule forbids
///   does not play, and `note` says why.
/// - While a move is in hand (playing, or stopped part way), a tap joins the queue and play goes on. Each ring in the
///   queue is judged when its turn comes, against the state then; the first that cannot play stops the queue, with its
///   note.
/// - A tap on the ring that would move just before it, the last ring waiting or else the ring moving, is not queued:
///   moving one ring twice in a row always cancels out, and the shortest way never does it. While solving, a tap on
///   another ring takes over and drops the rest of the way; a tap on the ring moving changes nothing, and Solve goes on.
/// - The markers show the toy as it is about to be, once the move in hand and the rings waiting have played, so that
///   a ring marked as able to move is one a tap would move.
/// - Play runs the move on the slider forward, toward the move being made. Undo runs it backward.
/// - Dragging the slider stops playing. At progress 1 the move is made, at 0 it is not.
public struct PuzzleSession: Sendable, Equatable {
    /// Which way the move on the slider plays.
    public enum Direction: Sendable, Equatable {
        /// Toward progress 1: the move is being made.
        case forward
        /// Toward progress 0: the move is being undone.
        case backward
    }

    /// Why the last request did not play.
    public enum Note: Sendable, Equatable {
        /// The rule does not let `ring` move: `block` names the ring in the way.
        case blocked(ring: Int, block: PuzzleState.Block)
    }

    /// What is happening, for the one line that says so.
    public enum Status: Sendable, Equatable {
        /// A move is playing. `move` is the move as the ring is going now: when undoing, the move back.
        case playing(Move, stage: Stage, undoing: Bool)
        /// A move is stopped part way.
        case paused(Move, stage: Stage, undoing: Bool)
        /// The last request did not play.
        case note(Note)
        /// Nothing is happening; the toy rests in this state.
        case resting(PuzzleState)
    }

    /// One ring as the strip of markers shows it.
    public struct Marker: Sendable, Equatable, Identifiable {
        public let ring: Int
        public let isOn: Bool
        /// What stops the ring from moving, in the state the toy is about to rest in, or nil when the rule lets it.
        public let block: PuzzleState.Block?
        /// Whether a tap now would move the ring: the rule lets it, it is not the ring that would move just before it,
        /// and no ring asked before it will be refused.
        public let canMove: Bool
        /// Whether this ring is the one moving, or stopped part way, now.
        public let isMoving: Bool
        /// Whether this ring was just asked to move and the rule refused.
        public let isRefused: Bool
        /// Whether this ring is the one in the way of the ring just refused.
        public let isBlocking: Bool

        public var id: Int { ring }
    }

    /// The state the moves were made from: all rings on, unless the session began at a chosen move.
    public private(set) var start: PuzzleState
    /// The moves made since the start, in order. The move on the slider is among them only when it is made.
    public private(set) var made: [Move] = []
    /// The move on the slider: the one playing, or the one played last. Nil before the first move.
    public private(set) var current: Move?
    /// How far through the move on the slider the toy is, from 0 to 1.
    public private(set) var progress: Double = 0
    public private(set) var isPlaying = false
    public private(set) var direction: Direction = .forward
    /// The rings asked to move after the move in hand, in order.
    public private(set) var queue: [Int] = []
    /// Whether the queue holds the shortest way to all rings off.
    public private(set) var isSolving = false
    /// Why the last request did not play; cleared by the next thing that happens.
    public private(set) var note: Note?
    /// How many times a move has been taken back: a count that only grows, for whoever keeps a record of the play. A move
    /// stands once it ends; taking it back, by Undo or by dragging the slider back to its start, counts once, when it
    /// arrives there. A move stopped before it ended and sent back to its start never stood, and is not counted.
    public private(set) var unmadeCount = 0
    /// How many moves Solve has made: a count that only grows. A move belongs to whoever began it: one Solve began is
    /// Solve's however it is carried on, by Play, by the slider or by a tap that takes over, since Solve chose its ring.
    public private(set) var madeBySolveCount = 0
    /// Whether the move on the slider is made, that is, is the last of `made`.
    private var currentIsMade = false
    /// Whether Solve began the move on the slider.
    private(set) var currentIsSolves = false

    /// A session with every ring on and no move made.
    public init() {
        start = .allOn
    }

    /// A session resting in `state`, with no move made and none on the slider.
    public init(resting state: PuzzleState) {
        start = state
    }

    /// A session with `made` made from `start`, the move on the slider as given, and the rings in `queue` waiting, not
    /// playing: what a saved toy brings back (see ``ToySnapshot``). The moves must be legal one after another; `current`
    /// is the last of them when `currentIsMade`, and otherwise a move from where they end.
    init(
        start: PuzzleState, made: [Move], current: Move?, progress: Double, currentIsMade: Bool, direction: Direction,
        currentIsSolves: Bool = false, queue: [Int] = [], isSolving: Bool = false
    ) {
        self.start = start
        self.made = made
        self.current = current
        self.progress = progress
        self.currentIsMade = currentIsMade
        self.direction = direction
        self.currentIsSolves = currentIsSolves
        self.queue = queue
        self.isSolving = isSolving
    }

    /// A session at the start of `move`, with that move on the slider at `progress`, not playing.
    public init(at move: Move, progress: Double = 0) {
        start = move.from
        current = move
        self.progress = 0
        scrub(to: progress)
    }

    // MARK: - What it shows

    /// The state the toy is in, or was in when the move in hand began: it changes only when a move ends.
    public var state: PuzzleState { made.last?.to ?? start }

    /// How many moves have been made since the start.
    public var moveCount: Int { made.count }

    /// Whether a move is in hand: playing, stopped part way, or waiting in the queue.
    public var isBusy: Bool {
        isPlaying || isPartWay || !queue.isEmpty
    }

    /// Whether the toy is between the two ends of the move on the slider, so that it does not rest in `state`.
    public var isPartWay: Bool {
        current != nil && progress > 0 && progress < 1
    }

    /// Whether the move on the slider is among the moves made.
    var isCurrentMade: Bool { currentIsMade }

    /// The motion of the move on the slider.
    public var motion: MoveMotion? { current.map(MoveMotion.init) }

    /// The stages of the move on the slider, as written for making it. Empty before the first move.
    public var stages: [Stage] { motion?.stages ?? [] }

    /// The toy as it is now.
    public var pose: ToyPose {
        motion?.pose(at: progress) ?? RestPoses.pose(for: state)
    }

    public var status: Status {
        if let current, let motion, isPlaying || isPartWay {
            let undoing = direction == .backward
            let shown = undoing ? current.reversed : current
            let stage = undoing ? MoveMotion(shown).stage(at: 1 - progress) : motion.stage(at: progress)
            return isPlaying ? .playing(shown, stage: stage, undoing: undoing) : .paused(shown, stage: stage, undoing: undoing)
        }
        if let note { return .note(note) }
        return .resting(state)
    }

    /// The nine rings, ring 1 first, as they will be once the move in hand and the rings waiting have played: what a tap
    /// now would do.
    public var markers: [Marker] { markers(asPlanned: true) }

    /// The nine rings, ring 1 first: `asPlanned`, as ``markers`` has them; otherwise as they are in `state`, following
    /// the toy move by move, each ring able to move when the rule lets it, as a toy that cannot be asked shows them.
    public func markers(asPlanned: Bool) -> [Marker] {
        let (state, isOpen) = asPlanned ? plannedState : (state, true)
        let previous = asPlanned ? previousRequest : nil
        let moving = movingRing
        let refused: (ring: Int, blocking: Int)? = {
            guard case .blocked(let ring, let block) = note else { return nil }
            return (ring, block.blockingRing)
        }()
        return PuzzleState.rings.map { ring in
            let block = state.block(for: ring)
            return Marker(
                ring: ring,
                isOn: state.isOn(ring),
                block: block,
                canMove: isOpen && block == nil && ring != previous,
                isMoving: ring == moving,
                isRefused: ring == refused?.ring,
                isBlocking: ring == refused?.blocking
            )
        }
    }

    /// Whether play would do something: carry on a move stopped part way, start the move on the slider from its
    /// beginning, or go on to the queue.
    public var canPlay: Bool {
        guard !isPlaying, current != nil else { return false }
        return progress < 1 || !queue.isEmpty
    }

    /// Whether undo would do something: run the move on the slider back, or the made move before it.
    public var canUndo: Bool {
        guard current != nil else { return false }
        if isPlaying && direction == .backward { return false }
        // Back at 0, the move on the slider is unmade, and the made move before it, if any, led to where it begins.
        return progress > 0 || isPlaying || !made.isEmpty
    }

    /// Whether solve would do something: the toy is not already on its way to all rings off.
    public var canSolve: Bool {
        settledState != .allOff && !isSolving
    }

    /// The state the toy will be in once the move in hand has ended, before the queue.
    private var settledState: PuzzleState {
        guard let current, isPlaying || isPartWay else { return state }
        return direction == .forward ? current.to : current.from
    }

    /// The ring of the move in hand, playing or stopped part way.
    private var movingRing: Int? {
        isPlaying || isPartWay ? current?.ring : nil
    }

    /// The ring that would move just before a ring tapped now: the last ring waiting, or the ring moving. While solving
    /// a tap drops the rest of the way, so it is the ring moving.
    private var previousRequest: Int? {
        isSolving ? movingRing : queue.last ?? movingRing
    }

    /// The state a ring tapped now is judged in when its turn comes: once the move in hand has ended and the rings
    /// waiting have played. While solving a tap drops the rest of the way, so the solve's rings are left out. `isOpen` is
    /// false when a ring waiting will be refused, which drops every ring after it.
    private var plannedState: (state: PuzzleState, isOpen: Bool) {
        var state = settledState
        guard !isSolving else { return (state, true) }
        for ring in queue {
            guard state.block(for: ring) == nil else { return (state, false) }
            state = state.moving(ring)
        }
        return (state, true)
    }

    // MARK: - What it does

    /// Asks to move `ring`. With a move in hand the ring waits in the queue, unless it is the ring that would move just
    /// before it, and play goes on; otherwise it plays now if it can, or `note` says why not.
    public mutating func tap(_ ring: Int) {
        precondition(PuzzleState.rings.contains(ring), "rings are numbered 1 to 9")
        if isBusy {
            // The same ring twice in a row would cancel out: the tap only plays on what is in hand.
            if ring != previousRequest {
                if isSolving {
                    // Asking for a ring takes over from solving: the rest of the way is dropped.
                    queue.removeAll()
                    isSolving = false
                }
                queue.append(ring)
            }
            resume()
            return
        }
        note = nil
        _ = begin(ring)
    }

    /// Plays forward from where the slider is, or pauses.
    public mutating func togglePlay() {
        if isPlaying {
            isPlaying = false
            return
        }
        guard canPlay else { return }
        note = nil
        if progress >= 1 {
            playNext()
        } else {
            // Forward even when an undo was paused part way: play makes the move, undo unmakes it.
            direction = .forward
            isPlaying = true
        }
    }

    public mutating func pause() {
        isPlaying = false
    }

    /// Runs the move on the slider back, or, when it is already back, the made move before it. The queue is dropped.
    public mutating func undo() {
        guard canUndo else { return }
        queue.removeAll()
        isSolving = false
        note = nil
        if progress <= 0 && isPlaying {
            // The move has only just begun: it stops where it began.
            isPlaying = false
            return
        }
        if progress <= 0, let previous = made.last {
            self.current = previous
            currentIsMade = true
            // It was counted when it was made; made again after an undo, it is the person's.
            currentIsSolves = false
            progress = 1
        }
        direction = .backward
        isPlaying = true
    }

    /// Makes `moves` at once, one after another from the state now, as if each had played to its end: each is among
    /// the moves made, so undo takes them back, and the last is on the slider at its end. The toy rests, and each move
    /// starts where the one before ends.
    mutating func make(_ moves: [Move]) {
        precondition(!isBusy, "moves are made at once only on a toy at rest")
        for move in moves {
            precondition(move.from == state, "ring \(move.ring)'s move starts where the toy rests")
            made.append(move)
            current = move
            currentIsMade = true
            currentIsSolves = false
            progress = 1
            direction = .forward
            note = nil
        }
    }

    /// Back to every ring on, with no move made.
    public mutating func reset() {
        self = PuzzleSession()
    }

    /// Plays the shortest way from here to all rings off, move after move, after the move in hand.
    public mutating func solve() {
        guard canSolve else { return }
        note = nil
        queue = settledState.moves(to: .allOff)
        isSolving = true
        if isPlaying || isPartWay {
            resume()
        } else {
            playNext()
        }
    }

    /// Sets the progress of the move on the slider, as a drag does. Playing stops. At either end the move is
    /// made or unmade; the queue waits for play.
    public mutating func scrub(to newProgress: Double) {
        guard current != nil else { return }
        isPlaying = false
        direction = .forward
        note = nil
        progress = min(max(newProgress, 0), 1)
        if progress >= 1 { settle(made: true) }
        if progress <= 0 { settle(made: false) }
        // During a solve's last move the queue is already empty. Dragged away from playing, that move is all that
        // is left of the solve, and play or a tap now decides what comes next: solving is over, so Solve is
        // offered again.
        if queue.isEmpty { isSolving = false }
    }

    /// Moves playing on by `seconds` of the move's own time at full speed (see ``MoveTiming``); whoever drives the
    /// session applies the playing speed. When the move ends, the state changes and the next ring in the queue begins;
    /// what is left of `seconds` is not carried into it.
    public mutating func advance(by seconds: Double) {
        guard isPlaying, let motion, seconds > 0 else { return }
        let timing = motion.timing
        let now = timing.time(atProgress: progress)
        switch direction {
        case .forward:
            if now + seconds >= timing.duration {
                progress = 1
                end(made: true)
            } else {
                progress = timing.progress(atTime: now + seconds)
            }
        case .backward:
            if now - seconds <= 0 {
                progress = 0
                end(made: false)
            } else {
                progress = timing.progress(atTime: now - seconds)
            }
        }
    }

    // MARK: - Inside

    /// Plays on from where it is in hand: a move stopped part way goes on the way it was going; at either end
    /// of the move, the queue begins.
    private mutating func resume() {
        guard !isPlaying else { return }
        if isPartWay {
            isPlaying = true
        } else {
            playNext()
        }
    }

    private mutating func end(made: Bool) {
        isPlaying = false
        settle(made: made)
        playNext()
    }

    /// Records whether the move on the slider is made, now that it is at one end.
    private mutating func settle(made isMade: Bool) {
        guard let current, isMade != currentIsMade else { return }
        if isMade {
            made.append(current)
            if currentIsSolves { madeBySolveCount += 1 }
        } else {
            made.removeLast()
            unmadeCount += 1
            // Taken back, it was undone; made again, it is the person's.
            currentIsSolves = false
        }
        currentIsMade = isMade
    }

    /// Begins the next ring in the queue that can play, or stops the queue at the first that cannot.
    private mutating func playNext() {
        guard !queue.isEmpty else {
            isSolving = false
            return
        }
        let ring = queue.removeFirst()
        if !begin(ring) {
            queue.removeAll()
            isSolving = false
        }
    }

    /// Starts `ring`'s move from the state now, or sets `note` and returns false when it cannot play.
    private mutating func begin(_ ring: Int) -> Bool {
        let state = state
        if let block = state.block(for: ring) {
            note = .blocked(ring: ring, block: block)
            return false
        }
        guard let move = Move(ring: ring, from: state) else { preconditionFailure("ring \(ring) is not blocked, so it can move") }
        note = nil
        current = move
        currentIsMade = false
        currentIsSolves = isSolving
        progress = 0
        direction = .forward
        isPlaying = true
        return true
    }
}

extension PuzzleState.Block {
    /// The ring whose rod is where it should not be.
    public var blockingRing: Int {
        switch self {
        case .earlierRingOn(let ring), .previousRingOff(let ring): ring
        }
    }
}
