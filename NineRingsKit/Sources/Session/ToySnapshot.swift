import Foundation
import Motion
import Puzzle

/// The person's toy as it is kept between launches: what brings it back, and the play in progress.
///
/// It is written as JSON inside one stored field, so that it can change with the app without touching the stored
/// schema; a change to what it holds raises ``format``. The rules it keeps:
/// - It holds the arrangement the moves start from, the rings moved since then in order, the move on the slider when
///   it is anywhere but at the end of the last move made, the rings waiting their turn and whether Solve is under way,
///   the play in progress with its id and counts, and the journeys toward achievements under way.
/// - The toy comes back as it was, only paused: a move playing is kept as stopped where it is, and play carries on
///   from there, with the rings waiting and the rest of a Solve. What the record counts of the move on the slider is
///   kept with it: whether Solve began it, and whether it is being taken back.
/// - At most ``movesKept`` moves are kept: the oldest are folded into the start, so that undo goes back that far and
///   no further. The play's counts are kept whole.
/// - Brought back, the moves are checked one by one against the rule; a snapshot that breaks it brings nothing back.
public struct ToySnapshot: Sendable, Equatable, Codable {
    /// The format of the snapshot. A build skips a format it does not know.
    public static let format = 1
    /// The most moves kept; the oldest beyond it are folded into the start.
    public static let movesKept = 2000

    /// The move on the slider, when it is not at the end of the last move made.
    struct Slider: Sendable, Equatable, Codable {
        /// The ring that moves.
        var ring: Int
        /// How far through the move the toy is, from 0 to 1.
        var progress: Double
        /// Whether the move is among the moves made, the last of them: true while it is being taken back.
        var isMade: Bool
        /// Whether it was going back, toward its start, when it stopped.
        var isUndoing: Bool
        /// Whether Solve began it, and nothing the person did has carried it on since.
        var isSolves: Bool
        /// Whether it is being taken back, and counted as an undo already.
        var isTakenBack: Bool
    }

    /// The arrangement the moves start from.
    var start: Rings
    /// The rings moved since `start`, in order.
    var moves: [Int]
    var slider: Slider?
    /// The rings waiting their turn, in order.
    var queue: [Int]
    /// Whether the rings waiting are Solve's way to every ring off.
    var isSolving: Bool
    /// The play in progress, or nil when none is: after a play is finished, until every ring is on again.
    public var play: Play?
    /// The journeys toward achievements under way, by the achievement each earns (``AchievementRule/underWay``), in the
    /// order of their identifiers.
    private var underWay: [Achievement]

    /// The person's `toy` as it is now, with the play in progress and the journeys under way.
    public init(toy: PuzzleSession, play: Play?, journeys: Set<Achievement> = []) {
        var start = toy.start
        var made = toy.made
        var play = play
        if made.count > Self.movesKept {
            let folded = made.count - Self.movesKept
            start = made[folded - 1].to
            made.removeFirst(folded)
            if let earlier = play?.earlierMoves { play?.earlierMoves = max(0, earlier - folded) }
        }
        self.start = Rings(start)
        moves = made.map(\.ring)
        queue = toy.queue
        isSolving = toy.isSolving
        self.play = play
        underWay = journeys.sorted { $0.rawValue < $1.rawValue }
        if let current = toy.current, !(toy.isCurrentMade && toy.progress >= 1) {
            // A move taken back all the way, or never begun, rests where it starts: the slider keeps it there.
            slider = Slider(
                ring: current.ring, progress: toy.progress, isMade: toy.isCurrentMade, isUndoing: toy.direction == .backward,
                isSolves: toy.currentIsSolves, isTakenBack: toy.currentIsTakenBack
            )
        }
    }

    /// The journeys toward achievements under way.
    public var journeys: Set<Achievement> { Set(underWay) }

    /// Whether `other` keeps the same toy, play and journeys, whatever time each says was spent on the play: the time
    /// spent looking at a toy does not change it.
    public func isSameToy(as other: ToySnapshot) -> Bool {
        var mine = self
        var theirs = other
        mine.play?.secondsSpent = 0
        theirs.play?.secondsSpent = 0
        return mine == theirs
    }

    enum CodingKeys: String, CodingKey {
        case start, moves, slider, queue, isSolving, play
        case underWay = "journeys"
    }

    /// The toy it keeps, at rest or stopped part way, or nil when its moves break the rule.
    public var toy: PuzzleSession? {
        guard queue.allSatisfy(PuzzleState.rings.contains) else { return nil }
        var state = start.state
        var made: [Move] = []
        for ring in moves {
            guard PuzzleState.rings.contains(ring), let move = Move(ring: ring, from: state) else { return nil }
            made.append(move)
            state = move.to
        }
        guard let slider else {
            return PuzzleSession(
                start: start.state, made: made, current: made.last, progress: made.isEmpty ? 0 : 1, currentIsMade: !made.isEmpty,
                direction: .forward, queue: queue, isSolving: isSolving
            )
        }
        guard (0...1).contains(slider.progress), PuzzleState.rings.contains(slider.ring) else { return nil }
        let current: Move
        if slider.isMade {
            guard let last = made.last, last.ring == slider.ring, slider.progress > 0 else { return nil }
            current = last
        } else {
            guard let move = Move(ring: slider.ring, from: state), slider.progress < 1 else { return nil }
            current = move
        }
        return PuzzleSession(
            start: start.state, made: made, current: current, progress: slider.progress, currentIsMade: slider.isMade,
            direction: slider.isUndoing ? .backward : .forward, currentIsSolves: slider.isSolves,
            currentIsTakenBack: slider.isTakenBack, queue: queue, isSolving: isSolving
        )
    }

    /// The snapshot as JSON.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        // Dates as seconds since Foundation's reference date, its own form, so that they come back exactly.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// The snapshot written as JSON in `format`, or nil when the format is not this one or the data is not a snapshot.
    public init?(data: Data, format: Int) {
        guard format == Self.format else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        guard let snapshot = try? decoder.decode(Self.self, from: data) else { return nil }
        self = snapshot
    }
}
