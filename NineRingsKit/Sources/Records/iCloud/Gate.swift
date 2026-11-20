import Foundation
import Session

// The rules that decide what is sent, which zone a device uses, and whom the data belongs to (docs/icloud.md,
// sections 8, 9 and 11), over the store and the notes of one run. `ICloudSync`'s calls use them; nothing else does.

/// The notes that hold for one run only (docs/icloud.md, section 5, "the notes of one run"). They are not saved, and
/// every launch starts without them.
///
/// Times within the run are *moments*: a counter that each call from the engine or the app moves on, so that "a fetch
/// that began after the device came to use its zone" compares two moments. The launch is moment 0.
struct RunNotes: Equatable {
    var moment = 0

    /// Whether the account has been confirmed in this run (section 8).
    var accountConfirmed = false
    /// Whether the app knows of no signed-in account: the engine reported a sign-out, or CloudKit answered that there
    /// is no account. No fetch is asked again for a request then (section 11).
    var knowsNoAccount = false
    /// A start from nothing whose account's part is still to come (section 8).
    var startFromNothing: StartFromNothing?
    /// Whether the engine was created without saved state and has not yet reported an account: its sign-in belongs to
    /// the start from nothing that began at launch.
    var awaitsEnginesSignIn = false
    /// The engine's latest state while a start from nothing waits for its account's part, saved with that part.
    var heldEngineState: Data?
    /// Whether the engine's state is saved as it comes: false after a failed write of fetched changes, or after the app
    /// discarded the state.
    var savesEngineState = true

    /// When the device began to use its zone: the launch, for the zone the store then noted as existing, or the join.
    var zoneUseBegan = 0
    /// The moment the latest fetch that counts began.
    var lastCountedFetchBegan: Int?
    /// When the zone in the note came to be not known to exist, or the launch when it was so already.
    var notKnownSince = 0
    /// When the device came to use no zone, or the launch when it used none then.
    var noZoneSince = 0
    /// Whether a save was refused for a full storage since the launch or the last return to the front.
    var storageFullThisRun = false
    /// Whether the device has given up a zone without a report of its deletion in this run.
    var gaveUpZone = false
    /// Whether a write of fetched changes has failed in this run.
    var writeFailed = false

    /// The app's requests to fetch that have not returned, by number.
    var requests: [Int: RequestNote] = [:]
    var nextRequest = 0
    /// Whether the next request asks again for one that found no fetch of its own.
    var nextRequestAsksAgain = false
    /// The fetch with the reason *manual* that is under way: when it began, and whether an error was reported for the
    /// zone the device uses.
    var manualFetch: ManualFetch?

    /// Whether the app left the front while the gate waited, and keeps background time until it no longer does.
    var keepsBackgroundTime = false

    struct StartFromNothing: Equatable {}

    struct ManualFetch: Equatable {
        var began: Int
        var zoneFailed = false
    }

    struct RequestNote: Equatable {
        /// Whether this request asks again for an earlier one.
        var asksAgain: Bool
        /// The fetch with the reason *manual* that began after the request: when, whether it ended, and whether an error
        /// was reported for the zone the device uses.
        var began: Int?
        var ended = false
        var zoneFailed = false
    }
}

/// The conditions whose lifting asks the gate (section 11), to tell when one lifted.
struct Conditions: Equatable {
    var accountConfirmed: Bool
    var zoneKnownToExist: String?
    var fetchCountedSinceZoneUse: Bool
    var fetchCountedSinceNoZone: Bool
    var storageNotFull: Bool
    var noToyHeld: Bool

    /// Whether one of these is true now and was not in `before`, or the zone known to exist is another.
    func lifted(since before: Conditions) -> Bool {
        (accountConfirmed && !before.accountConfirmed)
            || (zoneKnownToExist != nil && zoneKnownToExist != before.zoneKnownToExist)
            || (fetchCountedSinceZoneUse && !before.fetchCountedSinceZoneUse)
            || (fetchCountedSinceNoZone && !before.fetchCountedSinceNoZone)
            || (storageNotFull && !before.storageNotFull)
            || (noToyHeld && !before.noToyHeld)
    }
}

extension ICloudSync {
    // MARK: The zone note

    /// The zone note, or nil when the device has none.
    func zoneNote(_ notes: SyncNotes) -> ZoneNote? {
        guard let name = notes.zoneName, let zone = ZoneName(name) else { return nil }
        return ZoneNote(zone: zone, knowledge: ZoneKnowledge(rawValue: notes.zoneKnowledge) ?? .notKnownToExist)
    }

    /// The zone the device uses: the note's zone, unless it is marked deleted.
    func usedZone(_ notes: SyncNotes) -> ZoneNote? {
        guard let note = zoneNote(notes), note.knowledge != .deleted else { return nil }
        return note
    }

    /// The zone the device uses, when it knows it to exist.
    func zoneKnownToExist(_ notes: SyncNotes) -> ZoneName? {
        guard let note = zoneNote(notes), note.knowledge == .existing else { return nil }
        return note.zone
    }

    func setZoneNote(_ notes: SyncNotes, _ note: ZoneNote?) {
        notes.zoneName = note?.zone.name
        notes.zoneKnowledge = (note?.knowledge ?? .notKnownToExist).rawValue
        if let note { notes.highestNumber = max(notes.highestNumber, note.zone.number) }
    }

    // MARK: The gate (section 11)

    /// Condition 3: a fetch that counts has finished in this run since the device began to use its zone.
    var fetchCountedSinceZoneUse: Bool { (run.lastCountedFetchBegan ?? -1) > run.zoneUseBegan }

    /// The condition of creating a zone: a fetch that counts has finished that began after the device came to use no
    /// zone, or in this run if it used none at the launch.
    var fetchCountedSinceNoZone: Bool { (run.lastCountedFetchBegan ?? -1) > run.noZoneSince }

    /// The zone the gate lets records into, or nil when it lets none: conditions 1, 2, 3 and 6. Conditions 4 and 5 are
    /// the toy's and the saves' own.
    func gateZone(_ notes: SyncNotes) -> String? {
        guard run.accountConfirmed, !run.writeFailed, fetchCountedSinceZoneUse, let zone = zoneKnownToExist(notes) else {
            return nil
        }
        return zone.name
    }

    /// Whether the gate waits for the account's confirmation or for this run's fetch, for the background time as the
    /// app leaves the front.
    func gateWaitsForAccountOrFetch(_ notes: SyncNotes) -> Bool {
        guard !run.writeFailed else { return false }
        if !run.accountConfirmed { return true }
        if zoneKnownToExist(notes) != nil { return !fetchCountedSinceZoneUse }
        return run.lastCountedFetchBegan == nil
    }

    func conditions() throws -> Conditions {
        let notes = try store.syncNotes()
        return Conditions(
            accountConfirmed: run.accountConfirmed, zoneKnownToExist: zoneKnownToExist(notes)?.name,
            fetchCountedSinceZoneUse: fetchCountedSinceZoneUse, fetchCountedSinceNoZone: fetchCountedSinceNoZone,
            storageNotFull: !run.storageFullThisRun, noToyHeld: try store.toySide().held == nil
        )
    }

    /// Whether the store holds something to send: a play that is unsent or sent, a cleared entry, or a toy that is
    /// marked as changed while none is held (section 9).
    func hasSomethingToSend(_ side: ToySide) throws -> Bool {
        if side.isDue { return true }
        return try !store.playsNotInICloud().isEmpty
    }

    /// The gate is asked: at a sending moment (`sendingMoment`), or because one of its conditions lifted.
    ///
    /// A device that uses no zone and has something to send creates one when the creating rule allows it (section 9).
    /// While something waits for a fetch that counts, a sending moment asks for one. When the gate is open, everything
    /// the store marks is queued: every play that is unsent or sent, a deletion for every cleared entry, and the toy if
    /// condition 4 lets it through; saves only while condition 5 holds.
    func askGate(sendingMoment: Bool, into result: inout SyncResult) throws {
        guard !run.writeFailed else { return }
        let notes = try store.syncNotes()
        let side = try store.toySide()
        let asksFetches = sendingMoment && !run.knowsNoAccount

        if usedZone(notes) == nil, try hasSomethingToSend(side) {
            if run.accountConfirmed, fetchCountedSinceNoZone, !run.storageFullThisRun {
                createZone(notes, into: &result)
            } else if asksFetches, !fetchCountedSinceNoZone {
                result.engine.fetches = true
            }
        }
        if asksFetches, let note = usedZone(notes) {
            if note.knowledge == .notKnownToExist || !fetchCountedSinceZoneUse { result.engine.fetches = true }
        }

        guard let zone = gateZone(notes) else { return }
        var saves: [RecordID] = []
        var deletions: [RecordID] = []
        for entry in try store.playsNotInICloud() {
            let id = RecordID(zone: zone, name: entry.playID.uuidString)
            switch entry.sync {
            case .unsent, .sent: if !run.storageFullThisRun { saves.append(id) }
            case .cleared: deletions.append(id)
            case .inICloud: break
            }
        }
        if side.isDue, !run.storageFullThisRun { saves.append(.toy(in: zone)) }
        var queued = EngineRequests()
        queued.saves = saves
        queued.deletions = deletions
        result.engine.add(queued)
    }

    /// Creating a zone (section 9): the new name takes the number after the highest the device has heard of and a new
    /// random id, the note holds it as not known to exist, and only the zone's save is queued.
    private func createZone(_ notes: SyncNotes, into result: inout SyncResult) {
        let zone = ZoneName(number: notes.highestNumber + 1, id: makeID())
        setZoneNote(notes, ZoneNote(zone: zone, knowledge: .notKnownToExist))
        run.notKnownSince = run.moment
        result.engine.savesZone = zone.name
        result.engine.fetches = true
    }

    // MARK: Joining and leaving (sections 8 and 9)

    /// The device joins `zone` (section 8): it is noted as the zone the device uses, as existing; the device leaves every
    /// other zone, in the same save; and it asks the engine to fetch. The gate opens once a fetch that counts, and that
    /// began after now, has finished.
    func join(_ zone: ZoneName, notes: SyncNotes, side: inout ToySide, into result: inout SyncResult) throws {
        setZoneNote(notes, ZoneNote(zone: zone, knowledge: .existing))
        try leaveZones(keeping: zone.name, side: &side, into: &result)
        run.zoneUseBegan = run.moment
        result.engine.fetches = true
    }

    /// Leaves every zone but `kept`, or every zone (section 9, "Leaving a zone"): what is queued for them is withdrawn,
    /// the toy's base and a held toy's system fields of those zones are emptied (the toy marked when its base was of
    /// one, unless it is untouched), and so are the plays' system fields of those zones, each play in iCloud going back
    /// to sent. Afterwards the store holds nothing that belongs to them.
    func leaveZones(keeping kept: String?, side: inout ToySide, into result: inout SyncResult) throws {
        var withdrawal = EngineRequests()
        if let kept { withdrawal.withdrawsEverythingOutside = kept } else { withdrawal.withdrawsEverything = true }
        result.engine.add(withdrawal)
        side.leaveZones(keeping: kept)
        for entry in try store.plays(withSystemFieldsOutside: kept) {
            entry.systemFields = nil
            entry.systemFieldsZone = nil
            if entry.sync == .inICloud { entry.sync = .sent }
        }
    }

    /// The device gives up the zone in its note, which is not known to exist (section 9): the note marks it deleted, and
    /// the device leaves it, keeping its data. It then uses no zone, and asks at once for the fetch that creating a zone
    /// waits for.
    func giveUpZone(notes: SyncNotes, side: inout ToySide, into result: inout SyncResult) throws {
        notes.zoneKnowledge = ZoneKnowledge.deleted.rawValue
        try leaveZones(keeping: nil, side: &side, into: &result)
        run.noZoneSince = run.moment
        run.gaveUpZone = true
        result.engine.fetches = true
    }

    // MARK: Deleted zones (section 9)

    /// Zones reported as deleted, or met as deleted through an error. A deletion counts if the deleted zone is higher
    /// than the zone in the note, or is that zone while the note does not yet mark it deleted; a device with no zone
    /// note counts none. The highest that counts becomes the note's zone, marked deleted. If one of those that count is
    /// a purge or has the reason *deleted*, the device removes its data as for a purge; otherwise it keeps its data,
    /// leaves the zone, and asks at once for the fetch that creating a zone waits for.
    func zonesDeleted(_ deletions: [(zone: ZoneName, reason: ZoneDeletionReason)], notes: SyncNotes, side: inout ToySide, into result: inout SyncResult) throws {
        guard let note = zoneNote(notes) else { return }
        let counting = deletions.filter { $0.zone > note.zone || ($0.zone == note.zone && note.knowledge != .deleted) }
        guard let top = counting.map(\.zone).max() else { return }
        setZoneNote(notes, ZoneNote(zone: top, knowledge: .deleted))
        run.noZoneSince = run.moment
        if counting.contains(where: { $0.reason != .encryptedDataReset }) {
            try purge(side: &side, into: &result)
        } else {
            try leaveZones(keeping: nil, side: &side, into: &result)
            result.engine.fetches = true
        }
    }

    /// The person deleted the app's data from iCloud (section 9): the history is removed, the toy is put back to its
    /// untouched start and its notes are emptied, and everything queued is withdrawn. The account note, the engine's
    /// state and the highest number stay.
    private func purge(side: inout ToySide, into result: inout SyncResult) throws {
        let fresh = freshToy()
        side.putBack(to: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: madeOn.rawValue))
        try store.removeAllPlays()
        var withdrawal = EngineRequests()
        withdrawal.withdrawsEverything = true
        result.engine.add(withdrawal)
        result.replacedToy = fresh
        result.changesHistory = true
    }

    /// One of the three errors that say a zone is gone, met in an answer or at the end of a fetch (section 9). It counts
    /// only for the zone the device uses: a reset is a deletion of that zone with the reason *encrypted data reset*,
    /// `userDeletedZone` a deletion with the reason *purged*, and a plain missing zone makes the zone not known to
    /// exist.
    func zoneGone(_ name: String, _ error: ZoneGone, notes: SyncNotes, side: inout ToySide, into result: inout SyncResult) throws {
        guard let used = usedZone(notes), used.zone.name == name else { return }
        switch error {
        case .encryptedDataReset:
            try zonesDeleted([(used.zone, .encryptedDataReset)], notes: notes, side: &side, into: &result)
        case .userDeletedZone:
            try zonesDeleted([(used.zone, .purged)], notes: notes, side: &side, into: &result)
        case .missing:
            guard used.knowledge == .existing else { return }
            notes.zoneKnowledge = ZoneKnowledge.notKnownToExist.rawValue
            run.notKnownSince = run.moment
            result.engine.fetches = true
        }
    }

    // MARK: The account (section 8)

    /// A start from nothing begins, before any report is handled: every play in iCloud goes back to sent, keeping its
    /// system fields; a zone note that marks its zone existing now marks it not known to exist; and the engine's stored
    /// state is emptied, so that a quit before the account's part makes the next launch a start from nothing again. The
    /// account is not confirmed until the engine or CloudKit names it.
    func beginStartFromNothing(notes: SyncNotes, into result: inout SyncResult) throws {
        for entry in try store.plays(in: .inICloud) {
            if case .state(let state) = PlayRules.step(.startFromNothing, from: entry.sync).change { entry.sync = state }
        }
        if let note = zoneNote(notes), note.knowledge == .existing {
            notes.zoneKnowledge = ZoneKnowledge.notKnownToExist.rawValue
            run.notKnownSince = run.moment
            result.engine.fetches = true
        }
        notes.engineState = nil
        run.heldEngineState = nil
        run.accountConfirmed = false
        run.startFromNothing = RunNotes.StartFromNothing()
    }

    /// The engine or CloudKit named `account`: the account table's row for an account, compared with the store's note.
    /// With no note, the account is noted, and what was made without iCloud goes into it. With the same account,
    /// nothing more. With another, the toy goes back to its untouched start, the history and the sync notes are
    /// removed, and the new account is noted. The account is then confirmed for this run, and a start from nothing
    /// saves its account's part, with the engine's state.
    func accountNamed(_ account: String, notes: SyncNotes, side: inout ToySide, into result: inout SyncResult) throws {
        run.knowsNoAccount = false
        if let noted = notes.account, noted != account {
            let usedAZone = usedZone(notes) != nil
            let fresh = freshToy()
            side.putBack(to: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: madeOn.rawValue))
            try store.removeAllPlays()
            notes.engineState = nil
            setZoneNote(notes, nil)
            notes.highestNumber = 0
            notes.storageFull = false
            var withdrawal = EngineRequests()
            withdrawal.withdrawsEverything = true
            result.engine.add(withdrawal)
            result.replacedToy = fresh
            result.changesHistory = true
            if usedAZone { run.noZoneSince = run.moment }
        }
        notes.account = account
        if run.startFromNothing != nil {
            if run.savesEngineState, let state = run.heldEngineState { notes.engineState = state }
            run.heldEngineState = nil
            run.startFromNothing = nil
        }
        run.accountConfirmed = true
    }
}
