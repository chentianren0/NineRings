import Foundation
import Session

// The plain values that pass between the app's `CKSyncEngine` delegate and the rules (`ICloudSync`). The rules know
// nothing of CloudKit: the delegate turns what CloudKit hands over into these values, and turns `EngineRequests` back
// into calls on the engine. The names of the record types, the toy's record and the fields are the schema's, from
// docs/icloud.md section 5.

/// A record of the app's zone, as CloudKit hands it over: fetched, attached to a refused save, or returned by a save it
/// accepted.
///
/// The delegate fills it from a `CKRecord`: `type` from `recordType`, `name` from `recordID.recordName`, `changeTag` from
/// `recordChangeTag`, `systemFields` from `encodeSystemFields(with:)`, and `format` and `payload` from the record's
/// encrypted values. A field the record lacks is nil. The rules keep `systemFields` as opaque data and hand them back
/// for a later save of the same record.
public struct CloudRecord: Sendable, Equatable, Codable {
    /// The record type of the toy.
    public static let toyType = "Toy"
    /// The record type of a finished play.
    public static let finishedPlayType = "FinishedPlay"
    /// The name of the toy's record: one for the person.
    public static let toyName = "toy"
    /// The encrypted integer field that says which version of the JSON `payload` holds.
    public static let formatField = "format"
    /// The encrypted bytes field that holds the JSON.
    public static let payloadField = "payload"

    public var type: String
    public var name: String
    public var changeTag: String?
    public var systemFields: Data?
    public var format: Int?
    public var payload: Data?

    public init(type: String, name: String, changeTag: String?, systemFields: Data?, format: Int?, payload: Data?) {
        self.type = type
        self.name = name
        self.changeTag = changeTag
        self.systemFields = systemFields
        self.format = format
        self.payload = payload
    }

    /// Whether it is the toy's record.
    var isToy: Bool { type == Self.toyType && name == Self.toyName }

    /// The play it records, when it is a finished play's record: its name is the play's id.
    var playID: UUID? { type == Self.finishedPlayType ? UUID(uuidString: name) : nil }
}

/// A record for the engine to send, built when the engine asks for it.
///
/// The delegate makes a `CKRecord` from `systemFields` when there are some, so that the save carries the change tag this
/// device last saw, and otherwise a new record of type `type` named `name`; a developer reports that CloudKit refuses
/// such a record when one of that name exists (docs/icloud.md, open point 1). Then it sets the encrypted values `format`
/// and `payload`.
public struct RecordToSend: Sendable, Equatable {
    public var type: String
    public var name: String
    public var systemFields: Data?
    public var format: Int
    public var payload: Data

    public init(type: String, name: String, systemFields: Data?, format: Int, payload: Data) {
        self.type = type
        self.name = name
        self.systemFields = systemFields
        self.format = format
        self.payload = payload
    }
}

/// A record that iCloud reports as deleted: its type and its name.
public struct DeletedRecord: Sendable, Hashable {
    public var type: String
    public var name: String

    public init(type: String, name: String) {
        self.type = type
        self.name = name
    }
}

/// What one fetch of the zone's changes brought: the engine's `fetchedRecordZoneChanges` event, for the app's zone.
public struct FetchedChanges: Sendable, Equatable {
    /// The records changed or added, each as it now is in iCloud.
    public var records: [CloudRecord]
    /// The records deleted.
    public var deletions: [DeletedRecord]

    public init(records: [CloudRecord] = [], deletions: [DeletedRecord] = []) {
        self.records = records
        self.deletions = deletions
    }
}

/// What one send of changes to the zone brought back: the engine's `sentRecordZoneChanges` event.
public struct SentChanges: Sendable, Equatable {
    /// The records iCloud saved, as it returned them: the system fields with the new change tag, and the fields that were
    /// sent.
    public var saved: [CloudRecord]
    /// The saves that failed.
    public var failedSaves: [FailedSave]
    /// The names of the records iCloud deleted.
    public var deleted: [String]
    /// The deletions that failed.
    public var failedDeletions: [FailedDeletion]

    public init(saved: [CloudRecord] = [], failedSaves: [FailedSave] = [], deleted: [String] = [], failedDeletions: [FailedDeletion] = []) {
        self.saved = saved
        self.failedSaves = failedSaves
        self.deleted = deleted
        self.failedDeletions = failedDeletions
    }
}

/// A save that failed: the record's type and name, and why.
public struct FailedSave: Sendable, Equatable {
    public var type: String
    public var name: String
    public var reason: SaveFailure

    public init(type: String, name: String, reason: SaveFailure) {
        self.type = type
        self.name = name
        self.reason = reason
    }
}

/// Why a save failed, as far as the rules need to know.
public enum SaveFailure: Sendable, Equatable {
    /// iCloud has another version of the record than the one the save was built on, or a record of that name exists
    /// where the save made a new one (`CKError.serverRecordChanged`). `serverRecord` is iCloud's record, from the error's
    /// `serverRecord`, when the error carries it.
    case refused(serverRecord: CloudRecord?)
    /// iCloud no longer knows the record the save meant to change (`CKError.unknownItem`).
    case unknownItem
    /// The zone is missing (`CKError.zoneNotFound`). `encryptedDataReset` when the error is marked as a reset of the
    /// person's encrypted data (`CKErrorUserDidResetEncryptedDataKey`).
    case zoneMissing(encryptedDataReset: Bool)
    /// The person's iCloud storage is full (`CKError.quotaExceeded`).
    case storageFull
    /// The answer to the save was lost, and the save may have landed (`CKError.serverResponseLost`).
    case answerLost
    /// A failure the engine retries by itself: the network, a server limit, a busy zone, the service or the account
    /// unavailable for a while.
    case temporary
    /// Anything else, such as a setup error. The app logs it; the data stays marked as not received.
    case other
}

/// A deletion that failed: the record's name, and why.
public struct FailedDeletion: Sendable, Equatable {
    public var name: String
    public var reason: DeletionFailure

    public init(name: String, reason: DeletionFailure) {
        self.name = name
        self.reason = reason
    }
}

/// Why a deletion failed, as far as the rules need to know.
public enum DeletionFailure: Sendable, Equatable {
    /// The record is already gone (`CKError.unknownItem`).
    case alreadyGone
    /// The zone is missing, and with it the record (`CKError.zoneNotFound`); `encryptedDataReset` as for a save.
    case zoneMissing(encryptedDataReset: Bool)
    /// The answer was lost (`CKError.serverResponseLost`).
    case answerLost
    /// A failure the engine retries by itself.
    case temporary
    /// Anything else. The app logs it; the entry stays cleared and its deletion is queued again at the next launch.
    case other
}

/// What the engine reports about the device's iCloud account: its `accountChange` event, with the user record ids'
/// names.
public enum AccountChange: Sendable, Equatable {
    /// An account signed in: the current account.
    case signIn(String)
    /// The account signed out: the previous account.
    case signOut(String)
    /// The account changed from one to another while the app watched, or while it was not running.
    case switchAccounts(from: String, to: String)
}

/// Why iCloud's copy, the app's zone, was deleted: the reason the engine gives with the zone's deletion.
public enum ZoneDeletionReason: Sendable, Equatable {
    /// Another copy of the app deleted the zone.
    case deleted
    /// The person deleted the app's data from iCloud in Settings.
    case purged
    /// The person reset their encrypted data, and the zone could no longer be decrypted.
    case encryptedDataReset
}

/// What the rules ask the delegate to do with the engine after an event.
///
/// The delegate applies it in this order: ``dropsEveryPendingChange``, the withdrawals, ``savesZone``, ``saves``,
/// ``deletions``. Then, outside the delegate's callback, since the engine stops an app that fetches or sends from inside
/// one: ``fetches`` and ``sendsNow``.
public struct EngineRequests: Sendable, Equatable {
    /// Remove every pending change of the zone, first.
    public var dropsEveryPendingChange = false
    /// Pending saves to remove, by record name.
    public var withdrawnSaves: [String] = []
    /// Pending deletions to remove, by record name.
    public var withdrawnDeletions: [String] = []
    /// Queue the zone for saving. Saving a zone that exists changes nothing.
    public var savesZone = false
    /// Record names to queue for saving. The record is built only when the engine asks for it
    /// (``ICloudSync/recordsToSend(named:)``).
    public var saves: [String] = []
    /// Record names to queue for deletion.
    public var deletions: [String] = []
    /// Ask the engine to fetch.
    public var fetches = false
    /// Ask the engine to send now.
    public var sendsNow = false

    public init() {}

    /// Whether it asks for nothing.
    public var isEmpty: Bool { self == EngineRequests() }

    /// Adds `other`'s requests to these, each name once.
    mutating func add(_ other: EngineRequests) {
        dropsEveryPendingChange = dropsEveryPendingChange || other.dropsEveryPendingChange
        withdrawnSaves.appendNew(other.withdrawnSaves)
        withdrawnDeletions.appendNew(other.withdrawnDeletions)
        savesZone = savesZone || other.savesZone
        saves.appendNew(other.saves)
        deletions.appendNew(other.deletions)
        fetches = fetches || other.fetches
        sendsNow = sendsNow || other.sendsNow
    }
}

/// What an event from the engine changed, beyond the store.
public struct SyncResult: Sendable, Equatable {
    /// What to do with the engine.
    public var engine = EngineRequests()
    /// The toy the rules put in place of the one on screen, which the app shows at once: the toy put back to its
    /// untouched start, after another account signed in or the app's data was deleted from iCloud. A toy that waits to be
    /// taken up is not here: the app takes it up at a calm moment (``ICloudSync/takeUpHeldToy()``).
    public var replacedToy: ToySnapshot?
    /// Whether the history may have changed, so that a screen reads it again (``ICloudSync/history()``).
    public var changesHistory = false

    public init() {}
}

extension Array where Element == String {
    /// Appends each of `names` that is not here yet.
    mutating func appendNew(_ names: [String]) {
        guard !names.isEmpty else { return }
        var present = Set(self)
        for name in names where present.insert(name).inserted { append(name) }
    }
}
