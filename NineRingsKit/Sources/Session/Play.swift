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
/// - `moves` are the steps the play has taken: one more for each move made, one fewer for each of the play's own moves
///   taken back. A move taken back that was made before the play began is a step of this play too, one more, so that a
///   finished play never has fewer moves than the distance it went. `undos` are the moves taken back, by Undo or by
///   dragging the slider back (see ``PuzzleSession/unmadeCount``). `movesPlayedForThePerson` are the moves Solve made
///   and the moves the lesson made on the person's toy. `secondsSpent` is the time with the app in front.
public struct Play: Sendable, Equatable, Codable {
    public var id: UUID
    public var startedAt: Date
    public var startRings: PuzzleState
    public var moves = 0
    public var undos = 0
    public var movesPlayedForThePerson = 0
    public var secondsSpent = 0.0
    /// Of the moves made on the toy, how many were made before the play began and still stand: taking one of them back
    /// is a step of this play.
    public var earlierMoves: Int

    public init(id: UUID = UUID(), startedAt: Date, startRings: PuzzleState, earlierMoves: Int = 0) {
        self.id = id
        self.startedAt = startedAt
        self.startRings = startRings
        self.earlierMoves = earlierMoves
    }

    /// Counts the toy going from `before` moves made to `after`: the play's own moves made and taken back, and the moves
    /// made before it taken back.
    mutating func countMoves(from before: Int, to after: Int) {
        let earlier = min(earlierMoves, before)
        moves += max(after, earlier) - before + max(earlier - after, 0)
        earlierMoves = min(earlier, after)
    }

    /// The play, finished in `endRings` at `finishedAt`.
    public func finished(in endRings: PuzzleState, at finishedAt: Date) -> PlayRecord {
        PlayRecord(
            playID: id, startedAt: startedAt, finishedAt: finishedAt, startRings: startRings, endRings: endRings,
            moves: moves, undos: undos, movesPlayedForThePerson: movesPlayedForThePerson, secondsSpent: secondsSpent
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, startRings, moves, undos, movesPlayedForThePerson, secondsSpent, earlierMoves
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
        earlierMoves = try container.decode(Int.self, forKey: .earlierMoves)
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
        try container.encode(earlierMoves, forKey: .earlierMoves)
    }
}

/// A finished play, as its record keeps it: the numbers ``Play`` counts, with when it ended and where.
///
/// It is written as JSON with its ``rules``, and its rings as ``Play`` writes them. A record written with rules this
/// build does not know cannot be read.
public struct PlayRecord: Sendable, Equatable, Codable {
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

    enum CodingKeys: String, CodingKey {
        case rules, playID, startedAt, finishedAt, startRings, endRings, moves, undos, movesPlayedForThePerson, secondsSpent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rules = try container.decode(Int.self, forKey: .rules)
        guard rules <= Self.rules else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "rules \(rules) not known"))
        }
        playID = try container.decode(UUID.self, forKey: .playID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        startRings = try container.decode(Rings.self, forKey: .startRings).state
        endRings = try container.decode(Rings.self, forKey: .endRings).state
        moves = try container.decode(Int.self, forKey: .moves)
        undos = try container.decode(Int.self, forKey: .undos)
        movesPlayedForThePerson = try container.decode(Int.self, forKey: .movesPlayedForThePerson)
        secondsSpent = try container.decode(Double.self, forKey: .secondsSpent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.rules, forKey: .rules)
        try container.encode(playID, forKey: .playID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(finishedAt, forKey: .finishedAt)
        try container.encode(Rings(startRings), forKey: .startRings)
        try container.encode(Rings(endRings), forKey: .endRings)
        try container.encode(moves, forKey: .moves)
        try container.encode(undos, forKey: .undos)
        try container.encode(movesPlayedForThePerson, forKey: .movesPlayedForThePerson)
        try container.encode(secondsSpent, forKey: .secondsSpent)
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
