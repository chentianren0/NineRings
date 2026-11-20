import Foundation
import Session
import SwiftData

/// The rules of the iCloud design over the device's store: what the app and its `CKSyncEngine` delegate tell them, what
/// they change in the store, and what they ask of the engine (docs/icloud.md, sections 5 to 11 and 14).
///
/// It knows nothing of CloudKit. CloudKit's records arrive as ``CloudRecord``s and the engine's events as plain values;
/// what the engine is to do comes back as ``EngineRequests``. The delegate decides nothing: it translates. Every call
/// that changes the store saves once, so that what one call changes reaches the store together, and the store alone
/// always says what iCloud has not yet received (principle 1). When a save fails the store stays as it was before the
/// call, and the call throws, for the app to log.
///
/// The rules mark the store, and one gate decides what is queued in the engine and what is handed over
/// (section 11). The gate is asked at the app's sending moments, when one of its conditions lifts, and when the engine
/// asks for records (``batch(for:)``).
///
/// ## The engine's events
///
/// The app creates one engine at every launch, from ``engineState()``, with automatic syncing on and with fetches not
/// limited to some zones, and from then on changes the store only through these rules. The delegate turns each event,
/// and each request it makes of the engine, into one call:
///
/// | The engine, or the app's request | The delegate calls |
/// |---|---|
/// | the engine was created, at launch | ``launched(engineStartsFromNothing:)``, with whether ``engineState()`` was nil |
/// | `stateUpdate` | ``engineStateUpdated(_:)``, with the state serialized |
/// | `accountChange` | ``accountChanged(_:)``, with the user record ids' `recordName`s |
/// | `fetchedDatabaseChanges` | ``databaseChanged(_:)``, with every zone it names, changed and deleted |
/// | `willFetchChanges` | ``fetchBegan(manual:)``, with whether its context's reason is `.manual` |
/// | `fetchedRecordZoneChanges` | ``fetched(_:)`` |
/// | `didFetchRecordZoneChanges` | ``zoneFetchEnded(zone:error:)``, with the zone's error, if any |
/// | `didFetchChanges` | ``fetchEnded(manual:)``, with whether its context's reason is `.manual` |
/// | `sentDatabaseChanges` | ``zonesSent(_:)`` |
/// | `sentRecordZoneChanges` | ``sent(_:)`` |
/// | `nextRecordZoneChangeBatch` | ``batch(for:)``, with the pending changes the engine offers for the batch |
/// | the app asks the engine to fetch (`fetchChanges`) | ``fetchWillBeRequested()`` just before, and ``fetchRequestReturned(_:error:pendingZoneSaves:)`` when it returns or throws |
/// | the app asks CloudKit for the account's id (`userRecordID()`) | ``accountAnswered(_:)`` with the answer |
/// | the engine cannot go on from its saved state | ``discardEngineState()`` |
///
/// The events `willFetchRecordZoneChanges`, `willSendChanges` and `didSendChanges` need no call.
///
/// Each call returns what to do, which the delegate applies as ``EngineRequests`` describes: the changes to the pending
/// list at once, and the question for the account, the fetch and the send outside the engine's callback, since the
/// engine stops an app that fetches or sends from inside one. A fetch it asks for is one request of the app's: the
/// delegate calls ``fetchWillBeRequested()``, then `fetchChanges()`, then
/// ``fetchRequestReturned(_:error:pendingZoneSaves:)`` with the error it threw and the zones whose save is still in the
/// engine's pending list. A ``SyncResult/replacedToy`` replaces the toy on screen at once.
///
/// ## The app's moments
///
/// | Moment (section 11) | The app calls |
/// |---|---|
/// | Launch | ``toy()`` for the toy to show (nil: an untouched toy), ``engineState()``, then the engine's part above |
/// | The toy comes to rest | ``keep(_:at:)`` |
/// | The toy changes: at most once a minute while it changes | ``toyChanged()`` |
/// | A play is finished | ``finished(_:)`` |
/// | The person clears the history | ``clearHistory()`` |
/// | A calm moment, while ``heldToy()`` waits to be taken up | ``takeUpHeldToy()`` |
/// | The person answers the offer | ``playThatOne()`` or ``keepThisOne()`` |
/// | The app comes to the front | ``cameToFront()`` |
/// | The app leaves the front | ``leftFront()``, inside a background task, kept while the result says so |
/// | A push arrives | nothing: the engine fetches by itself |
///
/// Screens read ``history()``, ``heldToy()`` and ``storageIsFull``.
@MainActor
public final class ICloudSync {
    /// The device's store. Everything that changes it goes through these rules.
    let store: RecordStore
    let madeOn: MadeOn
    let appVersion: String
    /// Makes the random ids of stamps and of zones.
    let makeID: () -> UUID
    let freshToy: () -> ToySnapshot
    /// The notes of this run.
    var run = RunNotes()

    /// The rules over `store`, on a device of kind `madeOn`, in version `appVersion` of the app.
    public convenience init(store: RecordStore, madeOn: MadeOn, appVersion: String) {
        self.init(store: store, madeOn: madeOn, appVersion: appVersion, makeID: UUID.init, freshToy: { PlayState().snapshot })
    }

    /// The rules, with the random ids and the untouched toy made by `makeID` and `freshToy`.
    init(store: RecordStore, madeOn: MadeOn, appVersion: String, makeID: @escaping () -> UUID, freshToy: @escaping () -> ToySnapshot) {
        self.store = store
        self.madeOn = madeOn
        self.appVersion = appVersion
        self.makeID = makeID
        self.freshToy = freshToy
    }

    // MARK: Launch (section 8)

    /// The engine's state, to create the engine with; nil to create it from nothing.
    public func engineState() throws -> Data? {
        try store.existingSyncNotes()?.engineState
    }

    /// The app launched and created the engine, with its saved state or, when `engineStartsFromNothing`, without one.
    ///
    /// A start from nothing begins. A held toy in a higher format that this version can now read is handled as an
    /// arriving toy. The app asks CloudKit for the account's id and the engine to fetch; nothing is sent until the
    /// account is confirmed in this run and a fetch that counts has finished.
    public func launched(engineStartsFromNothing: Bool) throws -> SyncResult {
        run = RunNotes()
        return try call { result in
            let notes = try store.syncNotes()
            var side = try store.toySide()
            if engineStartsFromNothing {
                try beginStartFromNothing(notes: notes, awaitsEnginesSignIn: true, into: &result)
            }
            // A held toy is of the zone the device uses, or has no system fields since its zone was left.
            let heldZone = side.held?.record.zone
            if heldZone == nil || heldZone == usedZone(notes)?.zone.name, let record = side.takeHeldUnreadableThatNowReads() {
                try toyArrived(record, side: &side, into: &result)
            }
            try store.write(side)
            result.engine.asksForAccount = true
            result.engine.fetches = true
        }
    }

    // MARK: The toy (section 6)

    /// The toy to show, as the store keeps it; nil when it keeps none, and the app starts from an untouched toy.
    public func toy() throws -> ToySnapshot? {
        try store.toySide().toy?.snapshot
    }

    /// Keeps `snapshot` as the toy at `date`, at a rest (step 1). The store marks the toy as changed when it differs in
    /// more than time spent, and a first toy unless it is untouched. Returns whether anything was written. It asks the
    /// gate nothing: ``toyChanged()`` does, at most once a minute.
    @discardableResult
    public func keep(_ snapshot: ToySnapshot, at date: Date = .now) throws -> Bool {
        var changed = false
        _ = try call { _ in
            var side = try store.toySide()
            changed = side.keep(snapshot, at: date, on: madeOn.rawValue)
            if changed { try store.write(side) }
        }
        return changed
    }

    /// The toy changes: a sending moment, at most once a minute while the person plays (section 11).
    public func toyChanged() throws -> SyncResult {
        try call { result in try askGate(sendingMoment: true, into: &result) }
    }

    /// What this device holds of another device's toy, or nil when it holds none.
    public func heldToy() throws -> HeldToy? {
        guard let held = try store.toySide().held else { return nil }
        let payload = held.payload
        let kind: HeldToy.Kind = switch held.kind {
        case .unreadable: .needsNewerVersion
        case .toTakeUp: .toTakeUp
        case .offered: .offered
        }
        return HeldToy(kind: kind, changedAt: payload?.changedAt, changedOn: payload?.changedOn)
    }

    /// A calm moment: the held toy that waits to be taken up replaces the toy here (step 5, cases 5 and 6). The result's
    /// ``SyncResult/replacedToy`` is the toy to show; nil when no held toy waits to be taken up.
    public func takeUpHeldToy() throws -> SyncResult {
        try call { result in
            var side = try store.toySide()
            guard let taken = side.takeUp() else { return }
            try store.write(side)
            result.replacedToy = taken
        }
    }

    /// Play That One (step 6): the held toy replaces the toy here. The result's ``SyncResult/replacedToy`` is the toy to
    /// show; nil when no toy is offered.
    public func playThatOne() throws -> SyncResult {
        try call { result in
            var side = try store.toySide()
            guard let taken = side.playThatOne() else { return }
            try store.write(side)
            result.replacedToy = taken
        }
    }

    /// Keep This One (step 6): the held toy becomes the base, the toy here is marked as changed, and the gate is asked at
    /// once.
    public func keepThisOne() throws -> SyncResult {
        try call { result in
            var side = try store.toySide()
            guard side.keepThisOne() else { return }
            try store.write(side)
            try askGate(sendingMoment: true, into: &result)
        }
    }

    // MARK: The history (section 7)

    /// The history as a screen shows it: every entry that is not cleared, newest first, and how many this build cannot
    /// read.
    public func history() throws -> PlayHistory {
        var history = PlayHistory()
        for entry in try store.playsShown() {
            if let record = entry.record {
                history.plays.append(record)
            } else {
                history.unreadable += 1
            }
        }
        return history
    }

    /// A play is finished (rule 1): it is added as unsent, with no system fields, and the gate is asked at once. A play is
    /// recorded once on a device: finishing under an id the store already holds changes nothing.
    public func finished(_ play: PlayRecord) throws -> SyncResult {
        try call { result in
            if try store.plays([play.playID]).isEmpty {
                let entry = KeptPlay(id: play.playID)
                let payload = try FinishedPlayPayload(play: play, madeOn: madeOn.rawValue, appVersion: appVersion).encoded()
                entry.takeContent(of: CloudRecord(
                    type: CloudRecord.finishedPlayType, zone: nil, name: play.playID.uuidString, changeTag: nil,
                    systemFields: nil, format: FinishedPlayPayload.format, payload: payload
                ))
                entry.sync = .unsent
                store.insert(entry)
                result.changesHistory = true
            }
            try askGate(sendingMoment: true, into: &result)
        }
    }

    /// The person clears the history (rule 7). It reaches every entry, the plays counted and not shown too: entries that
    /// are unsent are removed at once, and every other one becomes cleared, its deletion marked. A save still queued for
    /// a play is withdrawn. Then the gate is asked at once.
    public func clearHistory() throws -> SyncResult {
        try call { result in
            var events: [(UUID, PlayRules.Event)] = []
            for entry in try store.allPlays() { events.append((entry.playID, .clearing)) }
            try applyToPlays(events, into: &result)
            try askGate(sendingMoment: true, into: &result)
        }
    }

    /// Whether iCloud last refused a save because the person's iCloud storage is full, for the line in the settings: the
    /// store's note, which a save accepted again clears.
    public var storageIsFull: Bool {
        (try? store.existingSyncNotes()?.storageFull) ?? false
    }

    // MARK: Front and back

    /// The app comes to the front: it asks for a fetch, asks CloudKit for the account's id if it is not yet confirmed,
    /// forgets a full storage noted in this run, and asks the gate.
    public func cameToFront() throws -> SyncResult {
        try call { result in
            run.storageFullThisRun = false
            run.keepsBackgroundTime = false
            result.engine.fetches = true
            if !run.accountConfirmed { result.engine.asksForAccount = true }
            try askGate(sendingMoment: true, into: &result)
        }
    }

    /// The app leaves the front: the gate is asked for the toy, and the engine to send. If the gate still waits, for the
    /// account's confirmation or for this run's fetch, the result keeps the background time, until a later result ends
    /// it (``SyncResult/endsBackgroundTime``) or the time runs out.
    public func leftFront() throws -> SyncResult {
        try call { result in
            try askGate(sendingMoment: true, into: &result)
            result.engine.sendsNow = true
            if gateWaitsForAccountOrFetch(try store.syncNotes()) {
                run.keepsBackgroundTime = true
                result.keepsBackgroundTime = true
            }
        }
    }

    // MARK: Inside

    /// Runs `body`, which changes the store and the run's notes; then asks the gate if one of its conditions lifted,
    /// and ends the background time if the gate no longer waits; then saves once. When anything fails, the store and the
    /// run's notes go back to what they were, and the error is thrown. With `writesFetchedChanges`, a failure is a
    /// failed write of fetched changes: nothing more is applied, sent, counted or concluded in this run (section 10).
    func call(writesFetchedChanges: Bool = false, _ body: (inout SyncResult) throws -> Void) throws -> SyncResult {
        let runBefore = run
        var result = SyncResult()
        do {
            run.moment += 1
            let before = try conditions()
            try body(&result)
            if try conditions().lifted(since: before) { try askGate(sendingMoment: false, into: &result) }
            let notes = try store.syncNotes()
            if run.keepsBackgroundTime, !gateWaitsForAccountOrFetch(notes) {
                run.keepsBackgroundTime = false
                result.endsBackgroundTime = true
                result.engine.sendsNow = true
            }
            try store.saveSync()
        } catch {
            store.rollBackSync()
            run = runBefore
            if writesFetchedChanges {
                run.writeFailed = true
                run.savesEngineState = false
            }
            throw error
        }
        return result
    }

    /// A toy arrived from the zone the device uses, through a fetch or with a refusal (step 5).
    func toyArrived(_ record: CloudRecord, side: inout ToySide, into result: inout SyncResult) throws {
        side.arrived(record)
    }

    /// Applies `events` to the plays' entries, in order, by the rules of section 7. The saves and deletions they withdraw
    /// are of the zone the device uses, where the gate queued them.
    func applyToPlays(_ events: [(UUID, PlayRules.Event)], into result: inout SyncResult) throws {
        guard !events.isEmpty else { return }
        var entries = try store.plays(events.map(\.0))
        let zone = usedZone(try store.syncNotes())?.zone.name
        var requests = EngineRequests()
        for (id, event) in events {
            let entry = entries[id]
            let step = PlayRules.step(event, from: entry?.sync)
            switch step.change {
            case .none:
                break
            case .state(let state):
                entry?.sync = state
            case .systemFields(let record, let state):
                entry?.takeSystemFields(of: record)
                entry?.sync = state
            case .content(let record, let state):
                let target = entry ?? KeptPlay(id: id)
                if entry == nil {
                    store.insert(target)
                    entries[id] = target
                }
                target.takeContent(of: record)
                target.takeSystemFields(of: record)
                target.sync = state
            case .comesBackCleared(let record):
                if entry == nil {
                    let target = KeptPlay(id: id)
                    if let record {
                        target.takeContent(of: record)
                        target.takeSystemFields(of: record)
                    }
                    target.sync = .cleared
                    store.insert(target)
                    entries[id] = target
                }
            case .remove:
                if let entry {
                    store.delete(entry)
                    entries[id] = nil
                }
            }
            if step.change != .none { result.changesHistory = true }
            if let zone {
                if step.withdrawsSave { requests.withdrawnSaves.append(RecordID(zone: zone, name: id.uuidString)) }
                if step.withdrawsDeletion { requests.withdrawnDeletions.append(RecordID(zone: zone, name: id.uuidString)) }
            }
            if step.fetches { result.engine.fetches = true }
        }
        result.engine.add(requests)
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
        /// while it is held. The line in the settings says so.
        case needsNewerVersion
    }

    public var kind: Kind
    /// When the held toy last changed, by the clock of the device that changed it, for the offer line; nil when this
    /// version cannot read it.
    public var changedAt: Date?
    /// The kind of device of its last change, as ``MadeOn`` writes it; nil when this version cannot read it.
    public var changedOn: String?
}
