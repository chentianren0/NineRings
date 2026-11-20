import Foundation
import Session

// The calls the app's `CKSyncEngine` delegate makes for the engine's events and for its own requests, as the table in
// `ICloudSync`'s documentation lists them.

extension ICloudSync {
    // MARK: The engine's state

    /// The engine handed over its state. It is saved with the store; during a start from nothing it is saved only with
    /// the account's part (section 8), and not at all after a failed write of fetched changes or after the app discarded
    /// the state (section 10).
    public func engineStateUpdated(_ state: Data) throws {
        guard run.savesEngineState else { return }
        if run.startFromNothing != nil {
            run.heldEngineState = state
            return
        }
        _ = try call { _ in try store.syncNotes().engineState = state }
    }

    /// The engine cannot go on from its saved state (open points 4 and 5): the state is removed, and not saved again in
    /// this run, so that the next launch is a start from nothing.
    public func discardEngineState() throws {
        _ = try call { _ in try store.syncNotes().engineState = nil }
        run.savesEngineState = false
        run.heldEngineState = nil
    }

    // MARK: The account (section 8)

    /// The engine reports a change of the device's account (section 8, the account table).
    ///
    /// A sign-in or a switch is a start from nothing, unless it is the sign-in of an engine created without saved state,
    /// which belongs to the start from nothing that began at launch; then the account it names is handled as the table
    /// says, and confirmed for this run. A sign-out keeps everything: the device notes the account that signed out if
    /// it noted none, empties its zone note, and the account is not confirmed.
    public func accountChanged(_ change: AccountChange) throws -> SyncResult {
        try call { result in
            let notes = try store.syncNotes()
            var side = try store.toySide()
            let awaitedSignIn = run.awaitsEnginesSignIn
            run.awaitsEnginesSignIn = false
            switch change {
            case .signIn(let account):
                if !awaitedSignIn { try beginStartFromNothing(notes: notes, into: &result) }
                try accountNamed(account, notes: notes, side: &side, into: &result)
            case .switchAccounts(_, let account):
                try beginStartFromNothing(notes: notes, into: &result)
                try accountNamed(account, notes: notes, side: &side, into: &result)
            case .signOut(let account):
                if notes.account == nil { notes.account = account }
                if usedZone(notes) != nil { run.noZoneSince = run.moment }
                setZoneNote(notes, nil)
                run.accountConfirmed = false
                run.knowsNoAccount = true
            }
            try store.write(side)
        }
    }

    /// CloudKit answered the app's question for the account's id. An id it names counts as a sign-in with that id, but
    /// begins no start from nothing: it is handled by the account table and confirms the account for this run.
    public func accountAnswered(_ answer: AccountAnswer) throws -> SyncResult {
        try call { result in
            switch answer {
            case .account(let account):
                let notes = try store.syncNotes()
                var side = try store.toySide()
                try accountNamed(account, notes: notes, side: &side, into: &result)
                try store.write(side)
            case .noAccount:
                run.knowsNoAccount = true
            case .failed:
                break
            }
        }
    }

    // MARK: Reports of zones (section 9)

    /// The engine reports the database's zones, from any fetch, the engine's own included.
    ///
    /// The device notes the highest number named. It handles the deleted zones first, by when a deletion counts, then
    /// the existing ones: a report that names its zone as existing while the note marks it not known to exist makes it
    /// join that zone again; one that names a higher existing zone makes it join that one; a device that uses no zone
    /// joins the highest existing zone named, whatever its number.
    public func databaseChanged(_ changes: DatabaseChanges) throws -> SyncResult {
        guard !run.writeFailed else { return SyncResult() }
        return try call(writesFetchedChanges: true) { result in
            let existing = changes.existing.compactMap(ZoneName.init)
            let deleted = changes.deleted.compactMap { deletion in ZoneName(deletion.zone).map { (zone: $0, reason: deletion.reason) } }
            guard !existing.isEmpty || !deleted.isEmpty else { return }
            let notes = try store.syncNotes()
            var side = try store.toySide()
            notes.highestNumber = max(notes.highestNumber, (existing.map(\.number) + deleted.map(\.zone.number)).max() ?? 0)
            try zonesDeleted(deleted, notes: notes, side: &side, into: &result)
            if let used = usedZone(notes) {
                let target = existing.filter { $0 > used.zone || ($0 == used.zone && used.knowledge == .notKnownToExist) }.max()
                if let target { try join(target, notes: notes, side: &side, into: &result) }
            } else if let target = existing.max() {
                try join(target, notes: notes, side: &side, into: &result)
            }
            try store.write(side)
        }
    }

    // MARK: Fetching (section 11)

    /// The app is about to ask the engine to fetch (`fetchChanges`). The request it returns goes back to
    /// ``fetchRequestReturned(_:error:pendingZoneSaves:)`` when the request returns.
    public func fetchWillBeRequested() -> FetchRequest {
        run.moment += 1
        let number = run.nextRequest
        run.nextRequest += 1
        run.requests[number] = RunNotes.RequestNote(asksAgain: run.nextRequestAsksAgain)
        run.nextRequestAsksAgain = false
        return FetchRequest(number: number)
    }

    /// The engine reports the beginning of a fetch (`willFetchChanges`), with whether its reason is *manual*: a fetch the
    /// app asked for.
    public func fetchBegan(manual: Bool) {
        run.moment += 1
        guard manual else { return }
        let moment = run.moment
        run.manualFetch = RunNotes.ManualFetch(began: moment)
        for number in Array(run.requests.keys) where run.requests[number]?.began == nil {
            run.requests[number]?.began = moment
        }
    }

    /// The engine fetched changes of records (`fetchedRecordZoneChanges`). Only those of the zone the device uses are
    /// applied: a toy arrives (section 6, step 5), a play arrives or its deletion (section 7, rules 5 and 6), and a
    /// deletion of the Toy record empties the base (section 10). A device that uses no zone applies none.
    public func fetched(_ changes: FetchedChanges) throws -> SyncResult {
        guard !run.writeFailed else { return SyncResult() }
        return try call(writesFetchedChanges: true) { result in
            guard let zone = usedZone(try store.syncNotes())?.zone.name else { return }
            var side = try store.toySide()
            var events: [(UUID, PlayRules.Event)] = []
            for record in changes.records where record.zone == zone {
                if record.isToy {
                    try toyArrived(record, side: &side, into: &result)
                } else if let id = record.playID {
                    events.append((id, .arrived(record)))
                }
            }
            for deletion in changes.deletions where deletion.id.zone == zone {
                if deletion.id.isToy {
                    side.forgetBase()
                } else if let id = deletion.id.playID {
                    events.append((id, .deletionArrived))
                }
            }
            try applyToPlays(events, into: &result)
            try store.write(side)
        }
    }

    /// The engine reports the end of one zone's fetch (`didFetchRecordZoneChanges`), with its error. For the zone the
    /// device uses, the three errors that say a zone is gone report that zone's end (section 9); any other error keeps
    /// the fetch under way from counting.
    public func zoneFetchEnded(zone: String, error: ZoneFetchError?) throws -> SyncResult {
        guard !run.writeFailed, let error else { return SyncResult() }
        return try call(writesFetchedChanges: true) { result in
            let notes = try store.syncNotes()
            guard usedZone(notes)?.zone.name == zone else { return }
            switch error {
            case .zoneGone(let gone):
                var side = try store.toySide()
                try zoneGone(zone, gone, notes: notes, side: &side, into: &result)
                try store.write(side)
            case .other:
                markManualFetchFailed()
            }
        }
    }

    /// The engine reports the end of a fetch (`didFetchChanges`), with whether its reason is *manual*. While the account
    /// is not confirmed, the app asks CloudKit for it again.
    public func fetchEnded(manual: Bool) throws -> SyncResult {
        try call { result in
            if manual, let fetch = run.manualFetch {
                for number in Array(run.requests.keys) where run.requests[number]?.began == fetch.began {
                    run.requests[number]?.ended = true
                }
                run.manualFetch = nil
            }
            if !run.accountConfirmed { result.engine.asksForAccount = true }
        }
    }

    /// The app's request to fetch returned, without an error or with `error`; `pendingZoneSaves` names the zones whose
    /// save is still in the engine's pending list.
    ///
    /// The fetch counts when the engine reported its beginning with the reason *manual* after the request and its end
    /// before the request returned; the request returned without an error, or with one that names only zones the
    /// device does not use, or the zone it uses with an error that says the zone is gone; no other error was reported
    /// for the zone the device uses; and no write of fetched changes has failed in this run. A fetch that counts may open
    /// the gate, lets the rule for a zone not known to exist conclude from silence, and may let a zone be created. A
    /// request for which no fetch began is asked again once, unless the app knows of no signed-in account.
    public func fetchRequestReturned(_ request: FetchRequest, error: FetchRequestError?, pendingZoneSaves: Set<String>) throws -> SyncResult {
        try call { result in
            guard let note = run.requests.removeValue(forKey: request.number) else { return }
            let notes = try store.syncNotes()
            var side = try store.toySide()
            let used = usedZone(notes)?.zone.name
            var errorCounts = true
            switch error {
            case nil:
                break
            case .whole:
                errorCounts = false
            case .zones(let errors):
                for (zone, zoneError) in errors where zone == used {
                    switch zoneError {
                    case .zoneGone(let gone):
                        if !run.writeFailed { try zoneGone(zone, gone, notes: notes, side: &side, into: &result) }
                    case .other:
                        errorCounts = false
                    }
                }
            }
            guard let began = note.began else {
                if !note.asksAgain, !run.knowsNoAccount {
                    run.nextRequestAsksAgain = true
                    result.engine.fetches = true
                }
                try store.write(side)
                return
            }
            guard note.ended, !note.zoneFailed, errorCounts, !run.writeFailed else {
                try store.write(side)
                return
            }
            run.lastCountedFetchBegan = max(run.lastCountedFetchBegan ?? began, began)
            // A zone not known to exist, still so, that the fetch began after it came to be so, and whose save the
            // engine no longer holds, is given up: at most once in a run.
            if let note = zoneNote(notes), note.knowledge == .notKnownToExist, began > run.notKnownSince,
               !pendingZoneSaves.contains(note.zone.name), !run.gaveUpZone {
                try giveUpZone(notes: notes, side: &side, into: &result)
            }
            try store.write(side)
        }
    }

    /// An error was reported for the zone the device uses during the manual fetch under way: it does not count.
    private func markManualFetchFailed() {
        guard var fetch = run.manualFetch else { return }
        fetch.zoneFailed = true
        run.manualFetch = fetch
        for number in Array(run.requests.keys) where run.requests[number]?.began == fetch.began {
            run.requests[number]?.zoneFailed = true
        }
    }

    // MARK: Sending (sections 6, 7, 10 and 11)

    /// The engine asks for a batch, offering `pending`, changes from its list (`nextRecordZoneChangeBatch`).
    ///
    /// The gate is asked for each: a save or a deletion goes only into the zone the device uses, while the gate lets it
    /// through; the toy only while it is due; a play only while it is unsent or sent, and it becomes sent; a deletion
    /// only while its entry is cleared. Everything else goes into no batch, and is withdrawn. What the records need is
    /// saved before they are handed over: the toy's stamp (section 6, step 2) and each play's state *sent* (section 7,
    /// rule 2). When that save fails, the call throws and nothing is to be handed over.
    public func batch(for pending: [PendingChange]) throws -> Batch {
        var batch = Batch()
        _ = try call { _ in
            let notes = try store.syncNotes()
            let zone = gateZone(notes)
            var side = try store.toySide()
            let ids = pending.compactMap { change -> UUID? in
                switch change {
                case .save(let id), .delete(let id): id.playID
                }
            }
            let entries = try store.plays(ids)
            for change in pending {
                switch change {
                case .save(let id):
                    guard let zone, id.zone == zone, !run.storageFullThisRun else {
                        batch.withdrawn.append(change)
                        continue
                    }
                    if id.isToy, let record = try side.recordToSend(in: zone, appVersion: appVersion, makeStamp: makeID) {
                        batch.records.append(record)
                    } else if let playID = id.playID, let entry = entries[playID],
                              case .state(let state) = PlayRules.step(.handedOver, from: entry.sync).change {
                        entry.sync = state
                        batch.records.append(entry.recordToSend(in: zone))
                    } else {
                        batch.withdrawn.append(change)
                    }
                case .delete(let id):
                    if let zone, id.zone == zone, let playID = id.playID, entries[playID]?.sync == .cleared {
                        batch.deletions.append(id)
                    } else {
                        batch.withdrawn.append(change)
                    }
                }
            }
            try store.write(side)
        }
        return batch
    }

    /// The engine sent changes of records, and this is what came back (`sentRecordZoneChanges`): section 6, steps 3 and
    /// 4; section 7, rules 3, 4 and 7; section 10. Answers of a zone other than the one the device uses are ignored.
    public func sent(_ changes: SentChanges) throws -> SyncResult {
        try call { result in
            let notes = try store.syncNotes()
            var side = try store.toySide()
            guard let zone = usedZone(notes)?.zone.name else { return }
            var events: [(UUID, PlayRules.Event)] = []
            var gone: ZoneGone?
            if !changes.saved.isEmpty { notes.storageFull = false }
            for record in changes.saved where record.zone == zone {
                if record.isToy {
                    side.accepted(record)
                } else if let id = record.playID {
                    events.append((id, .accepted(record)))
                }
            }
            for failure in changes.failedSaves where failure.id.zone == zone {
                switch failure.reason {
                case .refused(let serverRecord):
                    if failure.id.isToy {
                        if let serverRecord, serverRecord.zone == zone {
                            try toyArrived(serverRecord, side: &side, into: &result)
                        } else {
                            result.engine.fetches = true
                        }
                    } else if let id = failure.id.playID {
                        events.append((id, .refusedAsExisting(serverRecord: serverRecord)))
                    }
                case .unknownItem:
                    if failure.id.isToy {
                        side.forgetBase()
                    } else if let id = failure.id.playID {
                        events.append((id, .refusedAsUnknown))
                    }
                case .zoneGone(let error):
                    gone = worse(gone, error)
                case .storageFull:
                    notes.storageFull = true
                    run.storageFullThisRun = true
                case .other:
                    var withdrawal = EngineRequests()
                    withdrawal.withdrawnSaves = [failure.id]
                    result.engine.add(withdrawal)
                case .answerLost, .temporary:
                    break
                }
            }
            for id in changes.deleted where id.zone == zone {
                if let playID = id.playID { events.append((playID, .deletionAnswered)) }
            }
            for failure in changes.failedDeletions where failure.id.zone == zone {
                switch failure.reason {
                case .alreadyGone:
                    if let playID = failure.id.playID { events.append((playID, .deletionAnswered)) }
                case .zoneGone(let error):
                    gone = worse(gone, error)
                case .other:
                    var withdrawal = EngineRequests()
                    withdrawal.withdrawnDeletions = [failure.id]
                    result.engine.add(withdrawal)
                case .answerLost, .temporary:
                    break
                }
            }
            try applyToPlays(events, into: &result)
            if let gone { try zoneGone(zone, gone, notes: notes, side: &side, into: &result) }
            try store.write(side)
        }
    }

    /// The engine sent zones' saves, and this is what came back (`sentDatabaseChanges`). When iCloud confirms the zone
    /// the device created, the device joins it (section 9). A zone's save refused for a full storage is noted like a
    /// record's.
    public func zonesSent(_ changes: SentZones) throws -> SyncResult {
        try call { result in
            let notes = try store.syncNotes()
            var side = try store.toySide()
            if let note = zoneNote(notes), note.knowledge == .notKnownToExist, changes.saved.contains(note.zone.name) {
                try join(note.zone, notes: notes, side: &side, into: &result)
            }
            if changes.failed.contains(where: \.storageFull) {
                notes.storageFull = true
                run.storageFullThisRun = true
            }
            try store.write(side)
        }
    }

    /// Of two errors that say a zone is gone, met in one answer, the one that decides: a reset or a purge over a plain
    /// missing zone.
    private func worse(_ a: ZoneGone?, _ b: ZoneGone) -> ZoneGone {
        switch (a, b) {
        case (nil, _), (.missing?, _): b
        case (let a?, .missing): a
        case (_, let b): b
        }
    }
}
