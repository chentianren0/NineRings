import Foundation
import Session

// The plain values that pass between the app's `CKSyncEngine` delegate and the rules (`ICloudSync`). The rules know
// nothing of CloudKit: the delegate turns what CloudKit hands over into these values, and turns `EngineRequests` back
// into calls on the engine. The names of the record types, the toy's record and the fields are the schema's, from
// docs/icloud.md section 5. A zone is named by its name, `CKRecordZone.ID.zoneName`: every zone of the app is in the
// private database of its one container, and the owner is always the current user.

/// A record's id: its zone's name and its own name (`CKRecord.ID`).
public struct RecordID: Sendable, Hashable, Codable, CustomStringConvertible {
    public var zone: String
    public var name: String

    public init(zone: String, name: String) {
        self.zone = zone
        self.name = name
    }

    /// The toy's record in `zone`.
    public static func toy(in zone: String) -> RecordID { RecordID(zone: zone, name: CloudRecord.toyName) }

    /// Whether it names the toy's record.
    public var isToy: Bool { name == CloudRecord.toyName }

    /// The play it names, when it names a finished play's record: its name is the play's id.
    public var playID: UUID? { isToy ? nil : UUID(uuidString: name) }

    public var description: String { "\(zone)/\(name)" }
}

/// A record of one of the app's zones, as CloudKit hands it over: fetched, attached to a refused save, or returned by a
/// save it accepted.
///
/// The delegate fills it from a `CKRecord`: `type` from `recordType`, `zone` from `recordID.zoneID.zoneName`, `name` from
/// `recordID.recordName`, `changeTag` from `recordChangeTag`, `systemFields` from `encodeSystemFields(with:)`, and
/// `format` and `payload` from the record's encrypted values. A field the record lacks is nil. The rules keep
/// `systemFields` as opaque data and hand them back for a later save of the same record.
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
    /// The name of its zone. Nil only for a held toy whose zone is gone, kept without its system fields.
    public var zone: String?
    public var name: String
    public var changeTag: String?
    public var systemFields: Data?
    public var format: Int?
    public var payload: Data?

    public init(type: String, zone: String?, name: String, changeTag: String?, systemFields: Data?, format: Int?, payload: Data?) {
        self.type = type
        self.zone = zone
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

    /// The same record without what ties it to its zone: its system fields, its change tag and its zone.
    var withoutSystemFields: CloudRecord {
        var copy = self
        copy.zone = nil
        copy.changeTag = nil
        copy.systemFields = nil
        return copy
    }
}

/// A record for the engine to send, built when the engine asks for it.
///
/// The delegate makes a `CKRecord` from `systemFields` when there are some, so that the save carries the change tag this
/// device last saw; otherwise a new record of type `type` named `name` in zone `zone`. Then it sets the encrypted
/// values `format` and `payload`.
public struct RecordToSend: Sendable, Equatable {
    public var type: String
    public var zone: String
    public var name: String
    public var systemFields: Data?
    public var format: Int
    public var payload: Data

    public init(type: String, zone: String, name: String, systemFields: Data?, format: Int, payload: Data) {
        self.type = type
        self.zone = zone
        self.name = name
        self.systemFields = systemFields
        self.format = format
        self.payload = payload
    }

    public var id: RecordID { RecordID(zone: zone, name: name) }
}

/// A record that iCloud reports as deleted, in a fetch: its type and its id.
public struct DeletedRecord: Sendable, Hashable {
    public var type: String
    public var id: RecordID

    public init(type: String, id: RecordID) {
        self.type = type
        self.id = id
    }
}

/// What one batch of a fetch brought: the engine's `fetchedRecordZoneChanges` event, of any zones.
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

/// One report of the database's zones: the engine's `fetchedDatabaseChanges` event. Every zone of the database is in
/// it, by name; the rules ignore the names that are not of the design's form (docs/icloud.md, section 9).
public struct DatabaseChanges: Sendable, Equatable {
    /// The zones the report names as changed: zones that exist.
    public var existing: [String]
    /// The zones it names as deleted, each with the reason the engine gives.
    public var deleted: [ZoneDeletion]

    public init(existing: [String] = [], deleted: [ZoneDeletion] = []) {
        self.existing = existing
        self.deleted = deleted
    }
}

/// A zone the engine reports as deleted, with the reason it gives (`CKDatabase.DatabaseChange.Deletion`, in the engine's
/// `fetchedDatabaseChanges` event).
public struct ZoneDeletion: Sendable, Equatable {
    public var zone: String
    public var reason: ZoneDeletionReason

    public init(zone: String, reason: ZoneDeletionReason) {
        self.zone = zone
        self.reason = reason
    }
}

/// Why a zone was deleted: the reason the engine gives with the zone's deletion (`CKDatabase.DatabaseChange.Deletion.Reason`;
/// `CKSyncEngineZoneDeletionReason` in Objective-C).
public enum ZoneDeletionReason: Sendable, Equatable {
    /// Another copy of the app deleted the zone (`.deleted`).
    case deleted
    /// The person deleted the app's data from iCloud in Settings (`.purged`).
    case purged
    /// The person reset their encrypted data, and the zone could no longer be decrypted (`.encryptedDataReset`).
    case encryptedDataReset
}

/// One of the three errors that say a zone is gone (docs/icloud.md, section 9), wherever it comes: in the answer to a
/// save or a deletion, at the end of a zone's fetch, or in the error of the app's own request to fetch.
public enum ZoneGone: Sendable, Equatable {
    /// `CKError.zoneNotFound`, plain.
    case missing
    /// `CKError.zoneNotFound` marked as a reset of the person's encrypted data
    /// (`CKErrorUserDidResetEncryptedDataKey` in its user info).
    case encryptedDataReset
    /// `CKError.userDeletedZone`.
    case userDeletedZone
}

/// What one send brought back for records: the engine's `sentRecordZoneChanges` event, of any zones.
public struct SentChanges: Sendable, Equatable {
    /// The records iCloud saved, as it returned them: the system fields with the new change tag, and the fields that were
    /// sent.
    public var saved: [CloudRecord]
    /// The saves that failed.
    public var failedSaves: [FailedSave]
    /// The records iCloud deleted.
    public var deleted: [RecordID]
    /// The deletions that failed.
    public var failedDeletions: [FailedDeletion]

    public init(saved: [CloudRecord] = [], failedSaves: [FailedSave] = [], deleted: [RecordID] = [], failedDeletions: [FailedDeletion] = []) {
        self.saved = saved
        self.failedSaves = failedSaves
        self.deleted = deleted
        self.failedDeletions = failedDeletions
    }
}

/// A save that failed: the record's type and id, and why.
public struct FailedSave: Sendable, Equatable {
    public var type: String
    public var id: RecordID
    public var reason: SaveFailure

    public init(type: String, id: RecordID, reason: SaveFailure) {
        self.type = type
        self.id = id
        self.reason = reason
    }
}

/// Why a save failed, as far as the rules need to know.
public enum SaveFailure: Sendable, Equatable {
    /// iCloud has another version of the record than the one the save was built on, or a record of that name exists
    /// where the save made a new one (`CKError.serverRecordChanged`). `serverRecord` is iCloud's record, from the error's
    /// `serverRecord`, when the error carries it.
    case refused(serverRecord: CloudRecord?)
    /// iCloud does not know the record the save meant to change (`CKError.unknownItem`).
    case unknownItem
    /// The zone is gone (section 9).
    case zoneGone(ZoneGone)
    /// The person's iCloud storage is full (`CKError.quotaExceeded`).
    case storageFull
    /// The answer to the save was lost, and the save may have landed (`CKError.serverResponseLost`).
    case answerLost
    /// A failure the engine retries by itself: `notAuthenticated`, `accountTemporarilyUnavailable`, `networkFailure`,
    /// `networkUnavailable`, `requestRateLimited`, `serviceUnavailable` or `zoneBusy`.
    case temporary
    /// Anything else, such as a setup error or `limitExceeded`. The app logs it.
    case other
}

/// A deletion that failed: the record's id, and why.
public struct FailedDeletion: Sendable, Equatable {
    public var id: RecordID
    public var reason: DeletionFailure

    public init(id: RecordID, reason: DeletionFailure) {
        self.id = id
        self.reason = reason
    }
}

/// Why a deletion failed, as far as the rules need to know.
public enum DeletionFailure: Sendable, Equatable {
    /// The record is already gone (`CKError.unknownItem`).
    case alreadyGone
    /// The zone is gone (section 9).
    case zoneGone(ZoneGone)
    /// The answer was lost (`CKError.serverResponseLost`).
    case answerLost
    /// A failure the engine retries by itself, as for a save.
    case temporary
    /// Anything else. The app logs it.
    case other
}

/// What one send brought back for zones: the engine's `sentDatabaseChanges` event.
public struct SentZones: Sendable, Equatable {
    /// The zones iCloud saved, by name.
    public var saved: [String]
    /// The zones whose save failed, with why.
    public var failed: [FailedZoneSave]

    public init(saved: [String] = [], failed: [FailedZoneSave] = []) {
        self.saved = saved
        self.failed = failed
    }
}

/// A zone's save that failed.
public struct FailedZoneSave: Sendable, Equatable {
    public var zone: String
    /// Whether it failed because the person's iCloud storage is full (`CKError.quotaExceeded`). Any other failure is left
    /// to the engine, which tries again after the errors it retries by itself.
    public var storageFull: Bool

    public init(zone: String, storageFull: Bool) {
        self.zone = zone
        self.storageFull = storageFull
    }
}

/// An error at the end of one zone's fetch: the error of the engine's `didFetchRecordZoneChanges` event, or a zone's
/// error inside the error of the app's own request to fetch.
public enum ZoneFetchError: Sendable, Equatable {
    /// One of the three errors that say the zone is gone.
    case zoneGone(ZoneGone)
    /// Any other error.
    case other
}

/// The error that the app's own request to fetch (`fetchChanges`) threw.
public enum FetchRequestError: Sendable, Equatable {
    /// An error that names zones, each with its error: a `CKError.partialFailure` whose `partialErrorsByItemID` are keyed
    /// by zone ids.
    case zones([String: ZoneFetchError])
    /// Any other error: the request failed as a whole.
    case whole
}

/// One request of the app's to fetch, from ``ICloudSync/fetchWillBeRequested()`` to
/// ``ICloudSync/fetchRequestReturned(_:error:pendingZoneSaves:)``.
public struct FetchRequest: Sendable, Hashable {
    let number: Int
}

/// What the engine reports about the device's iCloud account: its `accountChange` event, with the user record ids'
/// names (`CKRecord.ID.recordName`).
public enum AccountChange: Sendable, Equatable {
    /// An account signed in: the current account.
    case signIn(String)
    /// The account signed out: the previous account.
    case signOut(String)
    /// The account changed from one to another, while the app watched or while it was not running.
    case switchAccounts(from: String, to: String)
}

/// What CloudKit answered when the app asked for the account's id (`CKContainer.userRecordID()`).
public enum AccountAnswer: Sendable, Equatable {
    /// The id of the current account, its `recordName`.
    case account(String)
    /// `CKError.notAuthenticated`: no account, iCloud turned off for the app, or access restricted.
    case noAccount
    /// Any other error.
    case failed
}

/// A change in the engine's list of pending changes for records (`CKSyncEngine.PendingRecordZoneChange`).
public enum PendingChange: Sendable, Hashable {
    case save(RecordID)
    case delete(RecordID)
}

/// What to hand the engine for one batch (``ICloudSync/batch(for:)``).
public struct Batch: Sendable, Equatable {
    /// The records to save, built now.
    public var records: [RecordToSend] = []
    /// The deletions to send.
    public var deletions: [RecordID] = []
    /// The pending changes that go into no batch: the delegate removes them from the engine's list.
    public var withdrawn: [PendingChange] = []

    public init() {}
}

/// What the rules ask the delegate to do with the engine after a call.
///
/// The delegate applies it in this order: the withdrawals (``withdrawsEverything``, ``withdrawsEverythingOutside``,
/// ``withdrawnSaves`` and ``withdrawnDeletions``), then ``savesZone``, ``saves`` and ``deletions``. Then, outside the
/// engine's callback, since the engine stops an app that fetches or sends from inside one: ``asksForAccount``,
/// ``fetches`` and ``sendsNow``.
public struct EngineRequests: Sendable, Equatable {
    /// Remove every pending change: of records, and the zones' own saves.
    public var withdrawsEverything = false
    /// Remove every pending change of a zone other than this one: of records, and the zones' own saves.
    public var withdrawsEverythingOutside: String?
    /// Pending saves of records to remove.
    public var withdrawnSaves: [RecordID] = []
    /// Pending deletions of records to remove.
    public var withdrawnDeletions: [RecordID] = []
    /// A zone to queue for saving (`CKSyncEngine.PendingDatabaseChange.saveZone`), by name. Only a new zone is ever
    /// queued, once.
    public var savesZone: String?
    /// Records to queue for saving. Each is built only when the engine asks for it (``ICloudSync/batch(for:)``).
    public var saves: [RecordID] = []
    /// Records to queue for deletion.
    public var deletions: [RecordID] = []
    /// Ask CloudKit for the account's id (`CKContainer.userRecordID()`), and hand the answer to
    /// ``ICloudSync/accountAnswered(_:)``.
    public var asksForAccount = false
    /// Ask the engine to fetch, as one request (``ICloudSync/fetchWillBeRequested()``).
    public var fetches = false
    /// Ask the engine to send now (`sendChanges`).
    public var sendsNow = false

    public init() {}

    /// Whether it asks for nothing.
    public var isEmpty: Bool { self == EngineRequests() }

    /// Adds `later`'s requests to these, as if the delegate applied these first and then `later`.
    mutating func add(_ later: EngineRequests) {
        if later.withdrawsEverything {
            withdrawsEverything = true
            withdrawsEverythingOutside = nil
            saves = []
            deletions = []
            savesZone = nil
        } else if let zone = later.withdrawsEverythingOutside {
            if !withdrawsEverything { withdrawsEverythingOutside = zone }
            saves.removeAll { $0.zone != zone }
            deletions.removeAll { $0.zone != zone }
            if savesZone != zone { savesZone = nil }
        }
        withdrawnSaves.appendNew(later.withdrawnSaves)
        withdrawnDeletions.appendNew(later.withdrawnDeletions)
        saves.removeAll { later.withdrawnSaves.contains($0) }
        deletions.removeAll { later.withdrawnDeletions.contains($0) }
        if let zone = later.savesZone { savesZone = zone }
        saves.appendNew(later.saves)
        deletions.appendNew(later.deletions)
        withdrawnSaves.removeAll { later.saves.contains($0) }
        withdrawnDeletions.removeAll { later.deletions.contains($0) }
        asksForAccount = asksForAccount || later.asksForAccount
        fetches = fetches || later.fetches
        sendsNow = sendsNow || later.sendsNow
    }
}

/// What a call changed, beyond the store.
public struct SyncResult: Sendable, Equatable {
    /// What to do with the engine.
    public var engine = EngineRequests()
    /// A toy to show at once in place of the one on screen: the toy taken up or chosen, or the toy put back to its
    /// untouched start, after another account signed in or the app's data was deleted from iCloud.
    public var replacedToy: ToySnapshot?
    /// Whether the history may have changed, so that a screen reads it again (``ICloudSync/history()``).
    public var changesHistory = false
    /// Whether the held toy appeared, changed its kind or went (``ICloudSync/heldToy()``): the app reads it again, takes
    /// it up at once if it waits to be taken up and the moment is calm, and shows or hides the offer line.
    public var changesHeldToy = false
    /// The app is leaving the front and the gate still waits for the account or for this run's fetch: the app keeps the
    /// background time the system grants until a later result ends it (``endsBackgroundTime``), or until it runs out
    /// (docs/icloud.md, section 11).
    public var keepsBackgroundTime = false
    /// The gate no longer waits for the account or for this run's fetch: the background time kept as the app left the
    /// front can end, once the requests of this result are applied and the engine has been asked to send.
    public var endsBackgroundTime = false

    public init() {}

    /// Adds `later`'s changes to these.
    mutating func add(_ later: SyncResult) {
        engine.add(later.engine)
        if let toy = later.replacedToy { replacedToy = toy }
        changesHistory = changesHistory || later.changesHistory
        changesHeldToy = changesHeldToy || later.changesHeldToy
        keepsBackgroundTime = keepsBackgroundTime || later.keepsBackgroundTime
        endsBackgroundTime = endsBackgroundTime || later.endsBackgroundTime
    }
}

extension Array where Element: Hashable {
    /// Appends each of `elements` that is not here yet.
    mutating func appendNew(_ elements: [Element]) {
        guard !elements.isEmpty else { return }
        var present = Set(self)
        for element in elements where present.insert(element).inserted { append(element) }
    }
}
