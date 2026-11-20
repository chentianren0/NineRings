import Foundation
import Puzzle
import Session
import SwiftData

// The two stored models of the earlier way of keeping and syncing. Both live in the device's store, and the store that
// syncs through SwiftData mirrors them to CloudKit, with SwiftData's rules for that: no unique values, no
// relationships, and a default for every stored property, each a plain number, text, date or `Data`. A property added
// later has a default that means "as before", so that a store kept before it opens by itself. The iCloud rules
// (`ICloudSync`) send `FinishedPlay` as a record of its own design, with a payload (docs/icloud.md, section 5), and keep
// the toy in `KeptToy`.

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
    /// What the numbers mean (``PlayRecord/rules``), so that an older build can tell a record it does not understand. A
    /// play that came from iCloud in a payload this build cannot read has one more than this build knows.
    public var rules: Int = 1
    /// Where the play stands with iCloud, a ``PlaySyncState`` (docs/icloud.md, section 7). A play recorded before this
    /// field has never left the device through the sync engine: *unsent*.
    public var syncState: Int = 0
    /// The format of ``payload``.
    public var format: Int = 1
    /// The play's record payload, as it went to iCloud or came from there. It is kept as it is, so that a play in a format
    /// this build cannot read goes back unchanged should the device offer it again. Empty for a play recorded before
    /// this field: its payload is written from the fields above.
    public var payload: Data = Data()

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
