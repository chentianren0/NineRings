import Foundation
import Session
import SwiftData

/// The rules of the iCloud design over the device's store: what the app's `CKSyncEngine` delegate tells them, what they
/// change in the store, and what they ask of the engine (docs/icloud.md, sections 6 to 10).
///
/// It knows nothing of CloudKit. CloudKit's records arrive as ``CloudRecord``s and the engine's events as plain values;
/// what the engine is to do comes back as ``EngineRequests``. Every call that changes the store saves once, so that what
/// one event changes reaches the store together, and the store alone always says what iCloud has not yet received
/// (principle 1). When a save fails the store stays as it was before the call, and the call throws, for the app to log.
///
/// ## The delegate's part
///
/// The app creates one engine at every launch, from ``engineState()``, with automatic syncing on, and from then on
/// changes the store only through these rules. The delegate turns each event into one call:
///
/// | The engine | The delegate calls |
/// |---|---|
/// | was created | ``start(engineStartsFromNothing:)`` |
/// | `stateUpdate` | ``engineStateUpdated(_:)``, with the state serialized |
/// | `accountChange` | ``accountChanged(_:)`` |
/// | `fetchedDatabaseChanges`, with a deletion of the app's zone | ``zoneDeleted(_:)``, with its reason |
/// | `fetchedRecordZoneChanges` | ``fetched(_:)`` |
/// | `sentRecordZoneChanges` | ``sent(_:)`` |
/// | `didFetchChanges` | ``fetchFinished()`` |
/// | `nextRecordZoneChangeBatch` | ``recordsToSend(named:)``, for the pending saves of the batch |
///
/// Each call returns what to do with the engine, which the delegate applies as ``EngineRequests`` describes; a pending
/// save for which ``recordsToSend(named:)`` gives no record is removed. If the engine starts from nothing and reports no
/// sign-in (docs/icloud.md, open point 14), the app asks CloudKit for the account's id and reports it as a sign-in. When
/// the engine's saved state has to be discarded, the app calls ``discardEngineState()``, creates the engine from
/// nothing, and calls ``start(engineStartsFromNothing:)`` again.
///
/// ## The app's part
///
/// | Moment (section 11) | The app calls |
/// |---|---|
/// | Launch | ``toy()`` for the toy to show; then the engine's part above |
/// | The toy rests | ``keep(_:at:)``, and at most once a minute ``queueToy()`` |
/// | A play is finished | ``record(_:)`` |
/// | The app comes to the front | ``notYetReceived()``, and asks the engine to fetch |
/// | The app leaves the front | ``queueToy()``, and asks the engine to send |
/// | A calm moment | ``takeUpHeldToy()`` when ``heldToy()`` waits to be taken up |
/// | The offer is answered | ``playThatOne()`` or ``keepThisOne()`` |
/// | The person clears the history | ``clearHistory()`` |
///
/// Screens read ``history()``, ``heldToy()`` and ``storageIsFull``. A ``SyncResult`` with a ``SyncResult/replacedToy``
/// replaces the toy on screen at once.
@MainActor
public final class ICloudSync {
    /// The device's store. Everything that changes it goes through these rules.
    let store: RecordStore
    private let madeOn: MadeOn
    private let appVersion: String
    private let makeStamp: () -> UUID
    private let freshToy: () -> ToySnapshot

    // What holds for this run only: a new run starts from the store.

    /// Whether the engine's state is saved as it comes. False after writing fetched changes failed in this run, so that
    /// the next launch fetches the same changes again (section 10).
    public private(set) var savesEngineState = true
    /// Whether the engine started from nothing and has not yet named the account. Until it does, nothing is queued and
    /// no record is built, so that no data goes out before the store's account note has been compared with the account
    /// the device is signed in to (section 8).
    public private(set) var waitsForAccount = false
    /// Whether a save failed in this run because the person's iCloud storage is full, and none has been accepted since:
    /// the line in Settings says so.
    public private(set) var storageIsFull = false
    /// Whether, after the next fetch, everything the store marks is queued: the device joined (joining step 5).
    private var queuesAfterFetch = false
    /// Whether, after the next fetch, the zone and everything the store marks are queued unless the fetch reported the
    /// zone's deletion: a save found the zone missing (section 9).
    private var checksZoneAfterFetch = false
    /// Whether a deletion of the zone was reported since the last fetch finished.
    private var zoneDeletionSeen = false

    /// The rules over `store`, on a device of kind `madeOn`, in version `appVersion` of the app.
    public convenience init(store: RecordStore, madeOn: MadeOn, appVersion: String) {
        self.init(store: store, madeOn: madeOn, appVersion: appVersion, makeStamp: UUID.init, freshToy: { PlayState().snapshot })
    }

    /// The rules, with the stamps and the untouched toy made by `makeStamp` and `freshToy`.
    init(store: RecordStore, madeOn: MadeOn, appVersion: String, makeStamp: @escaping () -> UUID, freshToy: @escaping () -> ToySnapshot) {
        self.store = store
        self.madeOn = madeOn
        self.appVersion = appVersion
        self.makeStamp = makeStamp
        self.freshToy = freshToy
    }

    // MARK: Launch (section 8)

    /// The engine's state, to create the engine with; nil to create it from nothing.
    public func engineState() throws -> Data? {
        try store.existingSyncNotes()?.engineState
    }

    /// The engine was created, at launch or anew (launch steps 3 to 5).
    ///
    /// With a saved state, everything the store marks as not yet received is queued again; the engine drops duplicates.
    /// From nothing, the device joins when the engine names the account (``accountChanged(_:)``), and nothing is queued
    /// until then. Either way the engine is asked to fetch, and a held toy is looked at again, so that a toy an earlier
    /// version of the app could not read is taken up or offered once this version can.
    public func start(engineStartsFromNothing: Bool) throws -> SyncResult {
        var result = SyncResult()
        try change {
            var side = try store.toySide()
            if side.lookAgainAtHeldToy() != nil { try store.write(side) }
        }
        waitsForAccount = engineStartsFromNothing
        queuesAfterFetch = false
        checksZoneAfterFetch = false
        result.engine.add(try notYetReceived())
        result.engine.fetches = true
        return result
    }

    // MARK: The toy (section 6)

    /// The toy to show: the one the store keeps, or, in a store that kept the toy the earlier way, that toy, so that it
    /// carries over. Nil when there is none, and the app starts from an untouched toy.
    public func toy() throws -> ToySnapshot? {
        if let kept = try store.toySide().toy { return kept.snapshot }
        return try store.savedToyLeftBefore()
    }

    /// Keeps `snapshot` as the toy at `date`, at a rest (step 1). The store marks the toy as changed when it differs in
    /// more than time spent; a first toy is marked unless nobody has touched it. Returns whether anything was written.
    @discardableResult
    public func keep(_ snapshot: ToySnapshot, at date: Date = .now) throws -> Bool {
        var changed = false
        try change {
            var side = try store.toySide()
            changed = side.keep(snapshot, at: date, on: madeOn.rawValue)
            if changed { try store.write(side) }
        }
        return changed
    }

    /// A sending moment (step 2): the toy is queued when it is marked as changed and no toy is held.
    public func queueToy() throws -> EngineRequests {
        var requests = EngineRequests()
        if !waitsForAccount, try store.toySide().isDue { requests.saves = [CloudRecord.toyName] }
        return requests
    }

    /// What this device holds of another device's toy, or nil when it holds none.
    public func heldToy() throws -> HeldToy? {
        let side = try store.toySide()
        guard let fate = side.heldFate else { return nil }
        let payload = side.heldPayload
        let kind: HeldToy.Kind = switch fate {
        case .unreadable: .needsNewerVersion
        case .toTakeUp: .toTakeUp
        case .offered: .offered
        }
        return HeldToy(kind: kind, changedAt: payload?.changedAt, changedOn: payload?.changedOn)
    }

    /// Takes the held toy up, at a calm moment (step 5, cases 4 and 5). Returns the toy to show, or nil when no held toy
    /// waits to be taken up.
    public func takeUpHeldToy() throws -> ToySnapshot? {
        var taken: ToySnapshot?
        try change {
            var side = try store.toySide()
            taken = side.takeUp()
            if taken != nil { try store.write(side) }
        }
        return taken
    }

    /// Play That One (step 6): the held toy replaces the toy here. Returns the toy to show, or nil when no toy this
    /// version can read is held.
    public func playThatOne() throws -> ToySnapshot? {
        var taken: ToySnapshot?
        try change {
            var side = try store.toySide()
            taken = side.playThatOne()
            if taken != nil { try store.write(side) }
        }
        return taken
    }

    /// Keep This One (step 6): the held toy becomes the base, and the toy here is sent at once.
    public func keepThisOne() throws -> EngineRequests {
        var requests = EngineRequests()
        try change {
            var side = try store.toySide()
            guard side.keepThisOne() else { return }
            try store.write(side)
            if side.isDue, !waitsForAccount {
                requests.saves = [CloudRecord.toyName]
                requests.sendsNow = true
            }
        }
        return requests
    }

    // MARK: The history (section 7)

    /// The history as a screen shows it: every entry that is not cleared, newest first, and how many this build cannot
    /// read.
    public func history() throws -> PlayHistory {
        try store.playHistory()
    }

    /// A play is finished (rule 1): it is recorded as unsent, and its record and the toy are queued. A play is recorded
    /// once on a device: finishing under an id the store already holds changes nothing.
    public func record(_ play: PlayRecord) throws -> EngineRequests {
        var recorded = false
        try change {
            guard try store.entries([play.playID]).isEmpty else { return }
            let entry = FinishedPlay(play, madeOn: madeOn, appVersion: appVersion)
            entry.format = FinishedPlayPayload.format
            entry.payload = try FinishedPlayPayload(play: play, madeOn: madeOn.rawValue, appVersion: appVersion).encoded()
            entry.sync = .unsent
            store.insert(entry)
            recorded = true
        }
        var requests = EngineRequests()
        guard recorded, !waitsForAccount else { return requests }
        requests.saves = [play.playID.uuidString]
        if try store.toySide().isDue { requests.saves.append(CloudRecord.toyName) }
        return requests
    }

    /// The person clears the history (rule 7): entries that are unsent are removed at once, and every other entry becomes
    /// cleared, with its deletion queued.
    public func clearHistory() throws -> EngineRequests {
        var deletions = NameList()
        try change {
            for entry in try store.allEntries() {
                let step = PlayRules.step(.clearing, from: entry.sync)
                switch step.change {
                case .remove: store.delete(entry)
                case .state(let state): entry.sync = state
                case .none, .content: break
                }
                if step.queuesDeletion { deletions.add(entry.recordName) }
            }
        }
        var requests = EngineRequests()
        if !waitsForAccount { requests.deletions = deletions.names }
        return requests
    }

    // MARK: What iCloud has not yet received

    /// Everything the store marks as not yet received: the saves of plays that are unsent or sent, the deletions of plays
    /// that are cleared, and the toy if it is marked as changed and no toy is held. The app queues it again as it comes
    /// to the front, which offers again what a full storage left unsent and what a lost answer left unconfirmed.
    ///
    /// Nothing while ``waitsForAccount``, and nothing while the device joins and waits for the join's fetch: the join
    /// queues everything once its fetch is done, after the deletions that iCloud still delivers have removed their
    /// entries (joining steps 4 and 5).
    public func notYetReceived() throws -> EngineRequests {
        var requests = EngineRequests()
        guard !waitsForAccount, !queuesAfterFetch else { return requests }
        let marked = try store.notYetReceived(toyIsDue: store.toySide().isDue)
        requests.saves = marked.saves
        requests.deletions = marked.deletions
        return requests
    }

    // MARK: Sending

    /// The records to hand to the engine for the pending saves `names`, by name. A name with nothing to send is left out,
    /// and the delegate removes its pending save: a toy that is not due, a play iCloud already has, a cleared play, one no
    /// longer here, or anything at all while ``waitsForAccount``.
    ///
    /// What the records need is saved before they are handed over: the toy's stamp (step 2), and each play's state
    /// *sent* (rule 2). When that save fails, the call throws and nothing is to be handed over. Records for plays the
    /// engine does not take into this batch stay *sent*, which only means that iCloud may have them.
    public func recordsToSend(named names: [String]) throws -> [String: RecordToSend] {
        guard !waitsForAccount else { return [:] }
        var records: [String: RecordToSend] = [:]
        try change {
            if names.contains(CloudRecord.toyName) {
                var side = try store.toySide()
                if let record = try side.recordToSend(appVersion: appVersion, makeStamp: makeStamp) {
                    try store.write(side)
                    records[CloudRecord.toyName] = record
                }
            }
            let ids = names.compactMap(UUID.init(uuidString:))
            let entries = try store.entries(ids)
            for id in ids {
                guard let entry = entries[id], case .state(let state) = PlayRules.step(.handedOver, from: entry.sync).change,
                      let record = try entry.recordToSend() else { continue }
                entry.sync = state
                records[record.name] = record
            }
        }
        return records
    }

    /// The engine sent a batch of changes, and this is what came back (steps 3 and 4 of section 6, rules 3, 4 and 7 of
    /// section 7, and section 10).
    public func sent(_ changes: SentChanges) throws -> SyncResult {
        var result = SyncResult()
        try change {
            var side = try store.toySide()
            let before = side
            var events: [(UUID, PlayRules.Event)] = []
            var zoneMissing: (encryptedDataReset: Bool, seen: Bool) = (false, false)
            for record in changes.saved {
                if record.isToy {
                    side.accepted(record)
                } else if let id = record.playID {
                    events.append((id, .accepted(record)))
                }
            }
            if !changes.saved.isEmpty { storageIsFull = false }
            for failure in changes.failedSaves {
                let isToy = failure.type == CloudRecord.toyType && failure.name == CloudRecord.toyName
                let playID = failure.type == CloudRecord.finishedPlayType ? UUID(uuidString: failure.name) : nil
                switch failure.reason {
                case .refused(let serverRecord):
                    if isToy {
                        if let serverRecord {
                            toyArrived(serverRecord, side: &side, result: &result)
                        } else {
                            result.engine.fetches = true
                        }
                    } else if let playID {
                        events.append((playID, .refused(serverRecord: serverRecord)))
                    }
                case .unknownItem:
                    if isToy {
                        side.forgetBase()
                        if side.isDue, !waitsForAccount { result.engine.saves.appendNew([CloudRecord.toyName]) }
                    }
                case .zoneMissing(let reset):
                    zoneMissing = (zoneMissing.encryptedDataReset || reset, true)
                case .storageFull:
                    storageIsFull = true
                case .answerLost, .temporary, .other:
                    // The marks stay: the change goes again at the next sending moment, launch or return to the front.
                    break
                }
            }
            for name in changes.deleted {
                if let id = UUID(uuidString: name) { events.append((id, .deletionAnswered)) }
            }
            for failure in changes.failedDeletions {
                guard let id = UUID(uuidString: failure.name) else { continue }
                switch failure.reason {
                case .alreadyGone:
                    events.append((id, .deletionAnswered))
                case .zoneMissing(let reset):
                    events.append((id, .deletionAnswered))
                    zoneMissing = (zoneMissing.encryptedDataReset || reset, true)
                case .answerLost, .temporary, .other:
                    break
                }
            }
            try apply(events, to: &result)
            if zoneMissing.seen {
                try zoneWasMissing(encryptedDataReset: zoneMissing.encryptedDataReset, side: &side, result: &result)
            }
            if side != before { try store.write(side) }
        }
        return result
    }

    // MARK: Fetching

    /// The engine fetched changes of the zone (step 5 of section 6, rules 5 and 6 of section 7). When writing them fails,
    /// the engine's state is no longer saved in this run, so that the next launch fetches them again (section 10).
    public func fetched(_ changes: FetchedChanges) throws -> SyncResult {
        var result = SyncResult()
        do {
            try change {
                var side = try store.toySide()
                let before = side
                var events: [(UUID, PlayRules.Event)] = []
                for record in changes.records {
                    if record.isToy {
                        toyArrived(record, side: &side, result: &result)
                    } else if let id = record.playID {
                        events.append((id, .arrived(record)))
                    }
                }
                for deletion in changes.deletions {
                    if deletion.type == CloudRecord.toyType, deletion.name == CloudRecord.toyName {
                        side.forgetBase()
                    } else if deletion.type == CloudRecord.finishedPlayType, let id = UUID(uuidString: deletion.name) {
                        events.append((id, .deletionArrived))
                    }
                }
                try apply(events, to: &result)
                if side != before { try store.write(side) }
            }
        } catch {
            savesEngineState = false
            throw error
        }
        return result
    }

    /// The engine finished fetching. After a join, everything the store marks is queued (joining step 5). After a save
    /// found the zone missing, the zone and everything the store marks are queued, unless the fetch reported the zone's
    /// deletion: then the deletion decided (section 9).
    public func fetchFinished() throws -> SyncResult {
        var result = SyncResult()
        var queues = false
        if checksZoneAfterFetch {
            checksZoneAfterFetch = false
            if !zoneDeletionSeen, !waitsForAccount {
                result.engine.savesZone = true
                queues = true
            }
        }
        if queuesAfterFetch {
            queuesAfterFetch = false
            queues = true
        }
        zoneDeletionSeen = false
        if queues { result.engine.add(try notYetReceived()) }
        return result
    }

    // MARK: The account (section 8)

    /// The engine reports a change of the device's account. The store's account note decides:
    /// - a sign-in to the account noted, or with none noted, notes the account and joins: what was made on the device
    ///   without iCloud goes into the account;
    /// - a sign-in to another account, and any switch of account, puts the toy back to its untouched start, removes the
    ///   history and the sync notes, notes the new account, and joins with nothing;
    /// - a sign-out keeps everything; with no account noted, it notes the account that signed out.
    public func accountChanged(_ change: AccountChange) throws -> SyncResult {
        var result = SyncResult()
        try self.change {
            let notes = try store.syncNotes()
            switch change {
            case .signIn(let account):
                if let noted = notes.account, noted != account {
                    try putEverythingBack(notes: notes, result: &result)
                }
                notes.account = account
                waitsForAccount = false
                try join(result: &result)
            case .switchAccounts(_, let account):
                try putEverythingBack(notes: notes, result: &result)
                notes.account = account
                waitsForAccount = false
                try join(result: &result)
            case .signOut(let account):
                if notes.account == nil { notes.account = account }
            }
        }
        return result
    }

    /// The account the data last synced with, as the store notes it; nil before the first time.
    public func account() throws -> String? {
        try store.existingSyncNotes()?.account
    }

    // MARK: When iCloud's copy is deleted (section 9)

    /// The engine reports the zone deleted, with `reason` (section 9):
    /// - Purged, or deleted by another copy of the app: the history is removed, the toy is put back to its untouched
    ///   start, and the toy's notes are emptied; the account note and the engine's state stay. Every pending change is
    ///   dropped, and nothing of it is sent again.
    /// - A reset of encrypted data: everything stays, the toy's base and the held toy's system fields are emptied, the toy
    ///   is marked as changed unless it is untouched, and the device joins, so that its copy goes to iCloud again.
    ///
    /// Section 9 is to change, after a probe of CloudKit found that a zone made again under its old name is not reported
    /// as deleted, and that an engine with no state hears of earlier deletions. A save that finds the zone missing with
    /// the mark of a reset comes to the same place.
    public func zoneDeleted(_ reason: ZoneDeletionReason) throws -> SyncResult {
        var result = SyncResult()
        try change {
            var side = try store.toySide()
            try zoneWasDeleted(reason, side: &side, result: &result)
            try store.write(side)
        }
        return result
    }

    // MARK: The engine's state

    /// The engine updated its state: it is saved with the store, unless writing fetched changes failed in this run.
    public func engineStateUpdated(_ state: Data) throws {
        guard savesEngineState else { return }
        try change { try store.syncNotes().engineState = state }
    }

    /// Removes the engine's saved state, which had to be discarded: the next engine starts from nothing, and the device
    /// joins (principle 4).
    public func discardEngineState() throws {
        try change { try store.syncNotes().engineState = nil }
    }

    // MARK: Inside

    /// Runs `body`, which changes the store, and saves once. When anything fails, the store goes back to what it was, and
    /// the error is thrown.
    private func change(_ body: () throws -> Void) throws {
        do {
            try body()
            try store.saveSync()
        } catch {
            store.rollBackSync()
            throw error
        }
    }

    /// A toy arrived, through a fetch or with a refusal (step 5). This device's own send coming back while the toy here
    /// has changed since is queued again.
    private func toyArrived(_ record: CloudRecord, side: inout ToySide, result: inout SyncResult) {
        if case .ownSend(queuesAgain: true) = side.arrived(record), side.isDue, !waitsForAccount {
            result.engine.saves.appendNew([CloudRecord.toyName])
        }
    }

    /// Applies `events` to the plays' entries, in order, by the rules of section 7.
    private func apply(_ events: [(UUID, PlayRules.Event)], to result: inout SyncResult) throws {
        guard !events.isEmpty else { return }
        var entries = try store.entries(events.map(\.0))
        var deletions = NameList(result.engine.deletions)
        var withdrawn = NameList(result.engine.withdrawnDeletions)
        for (id, event) in events {
            let entry = entries[id]
            let step = PlayRules.step(event, from: entry?.sync)
            switch step.change {
            case .none:
                break
            case .state(let state):
                entry?.sync = state
                result.changesHistory = true
            case .content(let record, let state):
                let target = entry ?? FinishedPlay(id: id)
                if entry == nil {
                    store.insert(target)
                    entries[id] = target
                }
                target.take(record)
                target.sync = state
                result.changesHistory = true
            case .remove:
                if let entry {
                    try store.remove(entry)
                    entries[id] = nil
                    result.changesHistory = true
                }
            }
            if step.queuesDeletion, !waitsForAccount { deletions.add(id.uuidString) }
            if step.withdrawsDeletion { withdrawn.add(id.uuidString) }
            if step.fetches { result.engine.fetches = true }
        }
        result.engine.deletions = deletions.names
        result.engine.withdrawnDeletions = withdrawn.names
    }

    /// The device joins (section 8): every play in iCloud goes back to *sent*, the zone is queued, and the engine is asked
    /// to fetch; everything the store marks is queued once the fetch is done. The toy has no step of its own. The account
    /// is noted by the caller.
    private func join(result: inout SyncResult) throws {
        for entry in try store.entries(in: .inICloud) {
            if case .state(let state) = PlayRules.step(.joining, from: entry.sync).change { entry.sync = state }
        }
        if !waitsForAccount { result.engine.savesZone = true }
        result.engine.fetches = true
        queuesAfterFetch = true
    }

    /// Another account arrived: the toy goes back to its untouched start, and the history and the sync notes go.
    private func putEverythingBack(notes: SyncNotes, result: inout SyncResult) throws {
        let fresh = freshToy()
        var side = ToySide()
        side.putBack(to: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: madeOn.rawValue))
        try store.write(side)
        try store.removeAllEntries()
        notes.engineState = nil
        notes.account = nil
        result.replacedToy = fresh
        result.changesHistory = true
    }

    /// A save or a deletion found the zone missing (section 9). Marked as a reset of encrypted data, it is handled as one.
    /// Otherwise the device does not create the zone at once: it fetches first, so that a deletion and its reason are seen
    /// before anything is sent again (``fetchFinished()``).
    private func zoneWasMissing(encryptedDataReset: Bool, side: inout ToySide, result: inout SyncResult) throws {
        if encryptedDataReset {
            try zoneWasDeleted(.encryptedDataReset, side: &side, result: &result)
        } else {
            checksZoneAfterFetch = true
            zoneDeletionSeen = false
            result.engine.fetches = true
        }
    }

    /// The one place where iCloud's copy, the app's zone, is taken as deleted with `reason` (``zoneDeleted(_:)``).
    private func zoneWasDeleted(_ reason: ZoneDeletionReason, side: inout ToySide, result: inout SyncResult) throws {
        zoneDeletionSeen = true
        switch reason {
        case .purged, .deleted:
            let fresh = freshToy()
            side.putBack(to: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: madeOn.rawValue))
            try store.removeAllEntries()
            result.engine.dropsEveryPendingChange = true
            result.replacedToy = fresh
            result.changesHistory = true
        case .encryptedDataReset:
            side.afterEncryptedDataReset()
            try join(result: &result)
        }
    }
}

/// What this device holds of another device's toy.
public struct HeldToy: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Both devices have changed the toy: the offer line shows, with Play That One and Keep This One.
        case offered
        /// It replaces the toy here at the next calm moment (``ICloudSync/takeUpHeldToy()``).
        case toTakeUp
        /// Another device uses a newer version of the app: its toy is held without an offer, and this device sends no toy
        /// while it is held. The line in Settings says so.
        case needsNewerVersion
    }

    public var kind: Kind
    /// When the held toy last changed, by the clock of the device that changed it, for the offer line; nil when this
    /// version cannot read it.
    public var changedAt: Date?
    /// The kind of device of its last change, as ``MadeOn`` writes it; nil when this version cannot read it.
    public var changedOn: String?
}

/// Names in the order they were added, each once.
private struct NameList {
    private(set) var names: [String]
    private var present: Set<String>

    init(_ names: [String] = []) {
        self.names = names
        present = Set(names)
    }

    mutating func add(_ name: String) {
        if present.insert(name).inserted { names.append(name) }
    }
}
