import Foundation
import Puzzle
import Session
import SwiftData

// The store's side of the iCloud design (docs/icloud.md, section 5): the device's store keeps, next to the data, what
// iCloud has not yet received, so that the engine's list of pending changes can always be rebuilt from the store alone.
//
// Three models hold it, all in the device's own store, which never syncs through SwiftData:
// - `FinishedPlay`, one for each play, with where it stands with iCloud (`syncState`) and its record's payload;
// - `KeptToy`, one for the store: the person's toy and its notes about iCloud;
// - `SyncNotes`, one for the store: the engine's saved state and the account.
// `ICloudSync` changes them and saves once for each event, so that a crash cannot leave the data and its marks
// disagreeing.

/// The person's toy on this device, with its notes about iCloud. There is one in a store.
@Model
final class KeptToy {
    /// The toy, a ``ToySnapshot`` encoded as JSON. Empty when no toy is kept yet, as when a toy arrived first.
    var snapshot: Data = Data()
    /// The format of `snapshot` (``ToySnapshot/format``).
    var format: Int = 1
    /// When the toy last changed, by the clock of the device that changed it.
    var changedAt: Date = Date.distantPast
    /// The kind of device of the toy's last change, as ``MadeOn`` writes it.
    var changedOn: String = ""
    /// The mark *Toy changed*.
    var isChanged: Bool = false
    /// The Toy record as this device last saw it, with its stamps (``ToySide/Base``), as JSON; nil when it saw none.
    var base: Data? = nil
    /// The last send (``ToySide/LastSend``), as JSON; nil when the toy here was never handed over.
    var lastSend: Data? = nil
    /// The stamps of the last sends, as JSON; empty when there were none.
    var ownStamps: Data = Data()
    /// The held toy, the record as it arrived (``CloudRecord``), as JSON; nil when none is held.
    var held: Data? = nil

    init() {}
}

/// The engine's saved state and the account the data last synced with. There is one in a store.
@Model
final class SyncNotes {
    /// The engine's state, as the engine handed it over; nil when there is none to start from.
    var engineState: Data? = nil
    /// The id of the iCloud account this data last synced with; nil before the first time.
    var account: String? = nil

    init() {}
}

extension FinishedPlay {
    /// Where the play stands with iCloud. A value this build does not know reads as unsent, which offers the play again.
    var sync: PlaySyncState {
        get { PlaySyncState(rawValue: syncState) ?? .unsent }
        set { syncState = newValue.rawValue }
    }

    /// The name of the play's record: its id.
    var recordName: String { playID.uuidString }

    /// An entry for a play known only by its id, whose content comes from a record.
    convenience init(id: UUID) {
        let placeholder = PlayRecord(
            playID: id, startedAt: .distantPast, finishedAt: .distantPast, startRings: .allOn, endRings: .allOff,
            moves: 0, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 0
        )
        self.init(placeholder, madeOn: .Mac, appVersion: "")
        madeOn = ""
    }

    /// Takes `record`'s content: its format and payload as they are, and the play's values when this build can read
    /// them. A payload this build cannot read leaves the values at their defaults and marks the entry as one this build
    /// does not understand, so that it is counted and not shown.
    func take(_ record: CloudRecord) {
        format = record.format ?? 0
        payload = record.payload ?? Data()
        if let read = FinishedPlayPayload(format: format, payload: payload, recordName: record.name) {
            let play = read.play
            finishedAt = play.finishedAt
            startedAt = play.startedAt
            startRings = play.startRings.description
            endRings = play.endRings.description
            moves = play.moves
            undos = play.undos
            movesPlayedForThePerson = play.movesPlayedForThePerson
            secondsSpent = play.secondsSpent
            madeOn = read.madeOn
            appVersion = read.appVersion
            rules = PlayRecord.rules
        } else {
            finishedAt = .distantPast
            startedAt = .distantPast
            startRings = ""
            endRings = ""
            moves = 0
            undos = 0
            movesPlayedForThePerson = 0
            secondsSpent = 0
            madeOn = ""
            appVersion = ""
            rules = PlayRecord.rules + 1
        }
    }

    /// The record to send for this play: its payload as kept, or, for a play recorded before payloads were kept, one
    /// written from its values. Nil for such a play this build cannot read.
    func recordToSend() throws -> RecordToSend? {
        if !payload.isEmpty {
            return RecordToSend(type: CloudRecord.finishedPlayType, name: recordName, systemFields: nil, format: format, payload: payload)
        }
        guard let play = record else { return nil }
        let written = try FinishedPlayPayload(play: play, madeOn: madeOn, appVersion: appVersion).encoded()
        return RecordToSend(
            type: CloudRecord.finishedPlayType, name: recordName, systemFields: nil, format: FinishedPlayPayload.format,
            payload: written
        )
    }
}

extension RecordStore {
    private var syncContext: ModelContext { container.mainContext }

    // MARK: The toy and its notes

    /// The store's `KeptToy`, or nil when it keeps none yet.
    private func keptToyRecord() throws -> KeptToy? {
        var descriptor = FetchDescriptor<KeptToy>()
        descriptor.fetchLimit = 1
        return try syncContext.fetch(descriptor).first
    }

    /// The toy and its notes, as the rules read them. A note that cannot be read counts as none.
    func toySide() throws -> ToySide {
        guard let kept = try keptToyRecord() else { return ToySide() }
        let decoder = JSONDecoder()
        var side = ToySide()
        if !kept.snapshot.isEmpty, let snapshot = ToySnapshot(data: kept.snapshot, format: kept.format) {
            side.toy = ToySide.Kept(snapshot: snapshot, changedAt: kept.changedAt, changedOn: kept.changedOn)
        }
        side.isChanged = kept.isChanged
        side.base = kept.base.flatMap { try? decoder.decode(ToySide.Base.self, from: $0) }
        side.lastSend = kept.lastSend.flatMap { try? decoder.decode(ToySide.LastSend.self, from: $0) }
        side.ownStamps = (try? decoder.decode([UUID].self, from: kept.ownStamps)) ?? []
        side.held = kept.held.flatMap { try? decoder.decode(CloudRecord.self, from: $0) }
        return side
    }

    /// Writes `side` into the store's `KeptToy`, making it when there is none. Nothing is saved yet.
    func write(_ side: ToySide) throws {
        let kept: KeptToy
        if let existing = try keptToyRecord() {
            kept = existing
        } else {
            kept = KeptToy()
            syncContext.insert(kept)
        }
        let encoder = JSONEncoder()
        if let toy = side.toy {
            kept.snapshot = try toy.snapshot.encoded()
            kept.format = ToySnapshot.format
            kept.changedAt = toy.changedAt
            kept.changedOn = toy.changedOn
        } else {
            kept.snapshot = Data()
        }
        kept.isChanged = side.isChanged
        kept.base = try side.base.map { try encoder.encode($0) }
        kept.lastSend = try side.lastSend.map { try encoder.encode($0) }
        kept.ownStamps = side.ownStamps.isEmpty ? Data() : try encoder.encode(side.ownStamps)
        kept.held = try side.held.map { try encoder.encode($0) }
    }

    /// The store's `SyncNotes`, made when there are none.
    func syncNotes() throws -> SyncNotes {
        if let notes = try existingSyncNotes() { return notes }
        let notes = SyncNotes()
        syncContext.insert(notes)
        return notes
    }

    /// The store's `SyncNotes`, or nil when it has none yet.
    func existingSyncNotes() throws -> SyncNotes? {
        var descriptor = FetchDescriptor<SyncNotes>()
        descriptor.fetchLimit = 1
        return try syncContext.fetch(descriptor).first
    }

    /// The toy the store kept the earlier way, as a `SavedToy`: the one changed last, when this build can read it.
    func savedToyLeftBefore() throws -> ToySnapshot? {
        var descriptor = FetchDescriptor<SavedToy>(sortBy: [SortDescriptor(\.changedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try syncContext.fetch(descriptor).first?.toy
    }

    // MARK: The finished plays

    /// The entries of the plays with `ids`, by id. Should the store hold two entries of one play, as the earlier way of
    /// syncing could leave, the one with the earlier finish is given.
    func entries(_ ids: some Collection<UUID>) throws -> [UUID: FinishedPlay] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let found = try syncContext.fetch(FetchDescriptor<FinishedPlay>(
            predicate: #Predicate { wanted.contains($0.playID) },
            sortBy: [SortDescriptor(\.finishedAt, order: .forward)]
        ))
        var byID: [UUID: FinishedPlay] = [:]
        for entry in found where byID[entry.playID] == nil { byID[entry.playID] = entry }
        return byID
    }

    /// Every entry in `state`.
    func entries(in state: PlaySyncState) throws -> [FinishedPlay] {
        let raw = state.rawValue
        return try syncContext.fetch(FetchDescriptor<FinishedPlay>(predicate: #Predicate { $0.syncState == raw }))
    }

    /// Every entry, each play once.
    func allEntries() throws -> [FinishedPlay] {
        try syncContext.fetch(FetchDescriptor<FinishedPlay>())
    }

    /// Adds an entry.
    func insert(_ entry: FinishedPlay) {
        syncContext.insert(entry)
    }

    /// Removes this one entry.
    func delete(_ entry: FinishedPlay) {
        syncContext.delete(entry)
    }

    /// Removes an entry, and any other entry of the same play.
    func remove(_ entry: FinishedPlay) throws {
        let id = entry.playID
        for copy in try syncContext.fetch(FetchDescriptor<FinishedPlay>(predicate: #Predicate { $0.playID == id })) {
            syncContext.delete(copy)
        }
    }

    /// Removes every finished play.
    func removeAllEntries() throws {
        for entry in try allEntries() { syncContext.delete(entry) }
    }

    // MARK: What iCloud has not yet received (principle 1)

    /// What the store marks as not yet received by iCloud: the names of the records to save (plays that are unsent or
    /// sent, and the toy when `toyIsDue`) and of the records to delete (plays that are cleared). It is read from the store
    /// alone.
    func notYetReceived(toyIsDue: Bool) throws -> (saves: [String], deletions: [String]) {
        var saves: [String] = toyIsDue ? [CloudRecord.toyName] : []
        var deletions: [String] = []
        var seen = Set<UUID>()
        let inICloud = PlaySyncState.inICloud.rawValue
        let marked = try syncContext.fetch(FetchDescriptor<FinishedPlay>(predicate: #Predicate { $0.syncState != inICloud }))
        for entry in marked where seen.insert(entry.playID).inserted {
            switch entry.sync {
            case .unsent, .sent: saves.append(entry.recordName)
            case .cleared: deletions.append(entry.recordName)
            case .inICloud: break
            }
        }
        return (saves, deletions)
    }

    // MARK: Saving

    /// Saves what the event changed, in one save. When the save fails, the store goes back to its last saved state and
    /// the error is thrown.
    func saveSync() throws {
        guard syncContext.hasChanges else { return }
        do {
            try syncContext.save()
        } catch {
            syncContext.rollback()
            throw error
        }
    }

    /// Forgets what an event changed and has not saved.
    func rollBackSync() {
        syncContext.rollback()
    }
}
