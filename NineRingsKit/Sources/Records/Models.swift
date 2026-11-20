import Foundation
import Puzzle
import Session
import SwiftData

// The two stored models. They will sync through CloudKit, whose schema, once promoted for a release, can only grow: a
// record type or field is never renamed, given another type or removed. So the class names and property names here
// are fixed. They follow CloudKit's rules: no unique values, no relationships, and a default for every stored
// property, each a plain number, text, date or `Data`. A later change adds a property whose default means "as
// before", or a new model.

/// One finished play. Written once and never changed.
@Model
public final class FinishedPlay {
    /// The play's own id. The same play recorded twice is told by it.
    public var playID: UUID = UUID()
    /// When it was finished.
    public var finishedAt: Date = Date.distantPast
    /// When it began.
    public var startedAt: Date = Date.distantPast
    /// The arrangement it began from, ring 1 first, `1` for on: `111111111`.
    public var startRings: String = ""
    /// The arrangement it ended in: `000000000`.
    public var endRings: String = ""
    /// The moves that stand at the end.
    public var moves: Int = 0
    /// The moves taken back on the way, by Undo or by dragging the slider back.
    public var undos: Int = 0
    /// The moves that Solve or the lesson made.
    public var movesPlayedForThePerson: Int = 0
    /// The time with the app in front, from the play's beginning to its end.
    public var secondsSpent: Double = 0
    /// `iPhone`, `iPad` or `Mac`.
    public var madeOn: String = ""
    /// The version of the app that wrote it.
    public var appVersion: String = ""
    /// What the numbers mean (``PlayRecord/rules``), so that an older build can tell a record it does not understand.
    public var rules: Int = 1

    /// The record of `play`, made on `madeOn` by version `appVersion` of the app.
    public init(_ play: PlayRecord, madeOn: MadeOn, appVersion: String) {
        playID = play.playID
        finishedAt = play.finishedAt
        startedAt = play.startedAt
        startRings = play.startRings.description
        endRings = play.endRings.description
        moves = play.moves
        undos = play.undos
        movesPlayedForThePerson = play.movesPlayedForThePerson
        secondsSpent = play.secondsSpent
        self.madeOn = madeOn.rawValue
        self.appVersion = appVersion
        rules = PlayRecord.rules
    }

    /// Whether this build understands the record's numbers.
    public var isUnderstood: Bool { rules <= PlayRecord.rules }

    /// The play as a plain value, or nil when its arrangements are not nine rings or its numbers mean something this
    /// build does not know.
    public var record: PlayRecord? {
        guard isUnderstood, let start = PuzzleState(startRings), let end = PuzzleState(endRings) else { return nil }
        return PlayRecord(
            playID: playID, startedAt: startedAt, finishedAt: finishedAt, startRings: start, endRings: end, moves: moves,
            undos: undos, movesPlayedForThePerson: movesPlayedForThePerson, secondsSpent: secondsSpent
        )
    }

    /// Whether the play went the shortest way (``PlayRecord/isShortestWay``).
    public var isShortestWay: Bool { record?.isShortestWay ?? false }
}

/// The toy as one installation of the app left it. There is one for each installation, changed in place.
@Model
public final class SavedToy {
    /// A random id for one installation of the app on one device (see ``InstallationID``). It is not a device's name or
    /// serial number.
    public var installation: String = ""
    /// When the toy last changed.
    public var changedAt: Date = Date.distantPast
    /// The format of `snapshot` (``ToySnapshot/format``). A build skips a format it does not know.
    public var format: Int = 1
    /// The toy, a ``ToySnapshot`` encoded as JSON.
    public var snapshot: Data = Data()
    /// The version of the app that wrote it.
    public var appVersion: String = ""
    /// Which toys of the installations it was made knowing, a ``Lineage`` encoded as JSON: what tells two installations'
    /// toys apart without a clock. Empty for a toy nobody has changed.
    public var lineage: Data = Data()

    public init(installation: String) {
        self.installation = installation
    }

    /// The toy it keeps, or nil when its format is not this build's or its data is not a snapshot.
    public var toy: ToySnapshot? {
        ToySnapshot(data: snapshot, format: format)
    }
}

/// The kind of device a record was made on, as `FinishedPlay.madeOn` writes it.
public enum MadeOn: String, Sendable, CaseIterable {
    case iPhone, iPad, Mac
}
