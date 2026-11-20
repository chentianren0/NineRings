import Foundation
import Puzzle
import Session

// The JSON in the `payload` field of the two record types in iCloud, and its `format` (docs/icloud.md, sections 5 and
// 14).
//
// Each payload's format starts at 1. The JSON is read leniently: a value this version does not know is ignored, and a
// value added after format 1 that it does not find takes a default, so adding a value needs no new format. A new format
// is for a change that an older version would misread. A version that meets a format it does not know never interprets
// the payload: reading gives nil. So does a payload that is not valid in its own format, which no version writes. A
// finished play that cannot be read is kept as it is either way; a toy is held when its format is higher, and replaced
// when it is broken (`ToyPayload.Reading`).
//
// Dates are written as seconds since Foundation's reference date, the form `ToySnapshot` uses, so that they come back
// exactly. Keys are sorted, so that the same payload is always the same bytes.

/// The toy as the `Toy` record carries it: the toy, when and on which kind of device it last changed, the version of the
/// app that sent it, and its stamps.
public struct ToyPayload: Sendable, Equatable, Codable {
    /// The format this version writes and reads.
    ///
    /// It covers the toy inside it too: a change to ``ToySnapshot`` that an older version would misread raises it.
    public static let format = 1
    /// The most stamps a payload carries: its own, and before it those of the versions before it.
    public static let stampsKept = 20

    /// The toy.
    public var toy: ToySnapshot
    /// When the toy last changed, by the clock of the device that changed it. Only the offer line shows it; no rule
    /// compares it.
    public var changedAt: Date
    /// The kind of device of the toy's last change, as ``MadeOn`` writes it. A kind this build does not know is kept as
    /// it is.
    public var changedOn: String
    /// The version of the app that sent it.
    public var appVersion: String
    /// The stamps of the versions of the record, the oldest first, ending with this version's own. A stamp is a random id
    /// for one version: it names no device and holds no time.
    public var stamps: [UUID]

    public init(toy: ToySnapshot, changedAt: Date, changedOn: String, appVersion: String, stamps: [UUID]) {
        self.toy = toy
        self.changedAt = changedAt
        self.changedOn = changedOn
        self.appVersion = appVersion
        self.stamps = stamps
    }

    /// This version's own stamp.
    public var stamp: UUID? { stamps.last }

    /// The stamps of the versions before this one.
    public var earlierStamps: ArraySlice<UUID> { stamps.dropLast() }

    /// The payload as JSON, in ``format``.
    public func encoded() throws -> Data {
        try PayloadCoding.encoder.encode(self)
    }

    /// The payload written as `payload` in `format`, or nil when this version cannot read it: another format, data
    /// that is not this format's JSON, or a toy whose moves break the puzzle's rule.
    public init?(format: Int, payload: Data) {
        guard format == Self.format, let read = try? PayloadCoding.decoder.decode(Self.self, from: payload),
              read.toy.toy != nil else { return nil }
        self = read
    }

    /// How this version reads a toy's record (docs/icloud.md, sections 6 and 14).
    enum Reading: Equatable {
        /// It reads.
        case readable(ToyPayload)
        /// Its format is higher than this version knows: it is never interpreted, and its stamps are not read.
        case higherFormat
        /// It is in no format higher than this version knows, and still cannot be read: its JSON is broken, or its moves
        /// break the puzzle's rule. No later version could read it either.
        case broken
    }

    /// How this version reads a record whose `format` and `payload` fields are these.
    static func reading(format: Int?, payload: Data?) -> Reading {
        if let format, format > Self.format { return .higherFormat }
        guard let format, let payload, let read = ToyPayload(format: format, payload: payload) else { return .broken }
        return .readable(read)
    }

    enum CodingKeys: String, CodingKey {
        case toy, changedAt, changedOn, appVersion, stamps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toy = try container.decode(ToySnapshot.self, forKey: .toy)
        changedAt = try container.decodeIfPresent(Date.self, forKey: .changedAt) ?? .distantPast
        changedOn = try container.decodeIfPresent(String.self, forKey: .changedOn) ?? ""
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        stamps = try container.decodeIfPresent([UUID].self, forKey: .stamps) ?? []
    }
}

/// A finished play as its `FinishedPlay` record carries it.
///
/// It holds the values docs/icloud.md lists in section 2, and also the arrangements the play began and ended in and the
/// version of the app that recorded it, which the store keeps for every play: the Shortest Way mark is worked out from
/// the arrangements, so that the same entry reads the same on every device.
public struct FinishedPlayPayload: Sendable, Equatable {
    /// The format this version writes and reads.
    public static let format = 1

    public var play: PlayRecord
    /// `iPhone`, `iPad` or `Mac`, as ``MadeOn`` writes it. A kind this build does not know is kept as it is.
    public var madeOn: String
    public var appVersion: String

    public init(play: PlayRecord, madeOn: String, appVersion: String) {
        self.play = play
        self.madeOn = madeOn
        self.appVersion = appVersion
    }

    /// The name of the play's record: its id.
    public var recordName: String { play.playID.uuidString }

    /// The payload as JSON, in ``format``.
    public func encoded() throws -> Data {
        try PayloadCoding.encoder.encode(Coded(self))
    }

    /// The payload of the record named `recordName`, written as `payload` in `format`, or nil when this version cannot
    /// read it: another format, data that is not this format's JSON, or a play whose id is not the record's name.
    public init?(format: Int, payload: Data, recordName: String) {
        guard format == Self.format, let id = UUID(uuidString: recordName),
              let coded = try? PayloadCoding.decoder.decode(Coded.self, from: payload), coded.id == id,
              let start = PuzzleState(coded.startRings), let end = PuzzleState(coded.endRings) else { return nil }
        play = PlayRecord(
            playID: id, startedAt: coded.startedAt, finishedAt: coded.finishedAt, startRings: start, endRings: end,
            moves: coded.moves, undos: coded.undos, movesPlayedForThePerson: coded.movesPlayedForThePerson,
            secondsSpent: coded.secondsSpent
        )
        madeOn = coded.madeOn
        appVersion = coded.appVersion
    }

    /// The JSON's shape.
    private struct Coded: Codable {
        var id: UUID
        var startedAt: Date
        var finishedAt: Date
        var startRings: String
        var endRings: String
        var moves: Int
        var undos: Int
        var movesPlayedForThePerson: Int
        var secondsSpent: Double
        var madeOn: String
        var appVersion: String

        init(_ payload: FinishedPlayPayload) {
            let play = payload.play
            id = play.playID
            startedAt = play.startedAt
            finishedAt = play.finishedAt
            startRings = play.startRings.description
            endRings = play.endRings.description
            moves = play.moves
            undos = play.undos
            movesPlayedForThePerson = play.movesPlayedForThePerson
            secondsSpent = play.secondsSpent
            madeOn = payload.madeOn
            appVersion = payload.appVersion
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            startedAt = try container.decode(Date.self, forKey: .startedAt)
            finishedAt = try container.decode(Date.self, forKey: .finishedAt)
            // A play begins at every ring on and is finished at every ring off, but by a debug launch option.
            startRings = try container.decodeIfPresent(String.self, forKey: .startRings) ?? PuzzleState.allOn.description
            endRings = try container.decodeIfPresent(String.self, forKey: .endRings) ?? PuzzleState.allOff.description
            moves = try container.decode(Int.self, forKey: .moves)
            undos = try container.decode(Int.self, forKey: .undos)
            movesPlayedForThePerson = try container.decode(Int.self, forKey: .movesPlayedForThePerson)
            secondsSpent = try container.decode(Double.self, forKey: .secondsSpent)
            madeOn = try container.decodeIfPresent(String.self, forKey: .madeOn) ?? ""
            appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        }
    }
}

/// The one way payloads are written and read.
enum PayloadCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
