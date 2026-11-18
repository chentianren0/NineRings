import Foundation
import Puzzle

/// A play: the way from every ring on toward every ring off, as far as it has gone, with what an honest record of it
/// needs.
///
/// It holds no clock: ``PlayState`` begins it, counts into it, and is told the time spent. The rules it keeps:
/// - A play begins whenever the person's toy comes to every ring on: a fresh toy, Reset, setting the rings to every
///   ring on, or moves or undos that bring every ring back on. That is the moment the congratulation is armed, and a
///   play is in progress exactly while it is armed. It gets a new id then, and its counts start from zero.
/// - It is finished at the moment the congratulation is due, and becomes a ``PlayRecord``. A play the congratulation
///   gives up, as when Solve takes the last ring off or the rings are set to another arrangement, ends unrecorded.
/// - `moves` are the moves that stand: one more for each move made, one fewer for each move taken back, never below
///   zero (a move taken back past the play's beginning was made before it). `undos` are the moves taken back, by undo
///   or by dragging the slider back. `movesPlayedForThePerson` are the moves Solve made and the moves the lesson made
///   on the person's toy. `secondsSpent` is the time with the app in front.
public struct Play: Sendable, Equatable, Codable {
    public var id: UUID
    public var startedAt: Date
    public var startRings: PuzzleState
    public var moves = 0
    public var undos = 0
    public var movesPlayedForThePerson = 0
    public var secondsSpent = 0.0

    public init(id: UUID = UUID(), startedAt: Date, startRings: PuzzleState) {
        self.id = id
        self.startedAt = startedAt
        self.startRings = startRings
    }

    /// The play, finished in `endRings` at `finishedAt`.
    public func finished(in endRings: PuzzleState, at finishedAt: Date) -> PlayRecord {
        PlayRecord(
            playID: id, startedAt: startedAt, finishedAt: finishedAt, startRings: startRings, endRings: endRings,
            moves: moves, undos: undos, movesPlayedForThePerson: movesPlayedForThePerson, secondsSpent: secondsSpent
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, startRings, moves, undos, movesPlayedForThePerson, secondsSpent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        startRings = try container.decode(Rings.self, forKey: .startRings).state
        moves = try container.decode(Int.self, forKey: .moves)
        undos = try container.decode(Int.self, forKey: .undos)
        movesPlayedForThePerson = try container.decode(Int.self, forKey: .movesPlayedForThePerson)
        secondsSpent = try container.decode(Double.self, forKey: .secondsSpent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(Rings(startRings), forKey: .startRings)
        try container.encode(moves, forKey: .moves)
        try container.encode(undos, forKey: .undos)
        try container.encode(movesPlayedForThePerson, forKey: .movesPlayedForThePerson)
        try container.encode(secondsSpent, forKey: .secondsSpent)
    }
}

/// A finished play, as its record keeps it: the numbers ``Play`` counts, with when it ended and where.
public struct PlayRecord: Sendable, Equatable {
    /// What the numbers mean. It goes up if that ever changes, so that an older build can tell a record it does not
    /// understand.
    public static let rules = 1

    public var playID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var startRings: PuzzleState
    public var endRings: PuzzleState
    public var moves: Int
    public var undos: Int
    public var movesPlayedForThePerson: Int
    public var secondsSpent: Double

    public init(
        playID: UUID, startedAt: Date, finishedAt: Date, startRings: PuzzleState, endRings: PuzzleState, moves: Int,
        undos: Int, movesPlayedForThePerson: Int, secondsSpent: Double
    ) {
        self.playID = playID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.startRings = startRings
        self.endRings = endRings
        self.moves = moves
        self.undos = undos
        self.movesPlayedForThePerson = movesPlayedForThePerson
        self.secondsSpent = secondsSpent
    }

    /// Whether the play went the shortest way.
    public var isShortestWay: Bool {
        Self.isShortestWay(from: startRings, to: endRings, moves: moves, undos: undos, movesPlayedForThePerson: movesPlayedForThePerson)
    }

    /// The shortest way: the moves equal the distance between the start and the end, with no undo and no move played
    /// for the person. From every ring on to every ring off that is 341 moves.
    public static func isShortestWay(from start: PuzzleState, to end: PuzzleState, moves: Int, undos: Int, movesPlayedForThePerson: Int) -> Bool {
        undos == 0 && movesPlayedForThePerson == 0 && moves == abs(start.rank - end.rank)
    }
}

/// The rings as nine characters, ring 1 first, `1` for on: how a state is written in a snapshot.
struct Rings: Codable, Equatable {
    let state: PuzzleState

    init(_ state: PuzzleState) {
        self.state = state
    }

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let state = PuzzleState(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not nine rings: \(text)"))
        }
        self.state = state
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(state.description)
    }
}
