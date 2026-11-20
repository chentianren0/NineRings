import Foundation
import Puzzle
import Session
import SwiftData

// The store's side of the iCloud design (docs/icloud.md, section 5): the device's store keeps, next to the data, what
// iCloud has not yet received, so that the engine's list of pending changes can always be rebuilt from the store alone.
//
// Three models hold it, all in the device's own store, which never syncs through SwiftData:
// - `KeptToy`, one for the store: the person's toy and its notes about iCloud;
// - `KeptPlay`, one for each finished play: the play's record as kept, its system fields and its state;
// - `SyncNotes`, one for the store: the engine's state, the zone note, the highest number, the account and the note of
//   a full storage.
// They are models of their own, apart from the earlier way's `SavedToy` and `FinishedPlay`: nothing kept the earlier way
// is carried over (docs/icloud.md, section 2). `ICloudSync` changes them and saves once for each call, so that a crash
// cannot leave the data and its marks disagreeing.

/// The person's toy on this device, with its notes about iCloud. There is one in a store.
@Model
final class KeptToy {
    /// The toy, a ``ToySnapshot`` encoded as JSON. Empty when no toy is kept yet.
    var snapshot: Data = Data()
    /// The format of `snapshot` (``ToySnapshot/format``).
    var format: Int = 1
    /// When the toy last changed, by the clock of the device that changed it.
    var changedAt: Date = Date.distantPast
    /// The kind of device of the toy's last change, as ``MadeOn`` writes it.
    var changedOn: String = ""
    /// The mark *Toy changed*: the toy has to be sent.
    var isChanged: Bool = false
    /// The toy's base (``ToySide/Base``), as JSON; nil when the device has seen no Toy record.
    var base: Data? = nil
    /// The last send (``ToySide/LastSend``), as JSON; nil when the toy here was never handed over.
    var lastSend: Data? = nil
    /// The stamps of the last sends, as JSON; empty when there were none.
    var ownStamps: Data = Data()
    /// The held toy (``ToySide/Held``), as JSON; nil when none is held.
    var held: Data? = nil

    init() {}
}

/// One finished play, as the iCloud rules keep it.
@Model
final class KeptPlay {
    /// The play's id, which is its record's name.
    var playID: UUID = UUID()
    /// When it was finished, by the clock of the device that finished it, for the order of the history. Distant past
    /// for a play this build cannot read.
    var finishedAt: Date = Date.distantPast
    /// Where it stands with iCloud, a ``PlaySyncState``.
    var state: Int = 0
    /// The format of `payload`.
    var format: Int = 0
    /// The record's payload, kept as it is: a play in a format this build cannot read goes back unchanged should the
    /// device offer it again. Empty for an entry that came back as cleared without its record.
    var payload: Data = Data()
    /// CloudKit's system fields of its record, from the answer that accepted it or from its arrival; nil when it has
    /// none.
    var systemFields: Data? = nil
    /// The zone those system fields belong to.
    var systemFieldsZone: String? = nil

    init(id: UUID) {
        playID = id
    }
}

/// The notes of section 5 that are not the toy's: the engine's state, the zone note, the highest number, the account and
/// the note of a full storage. There is one in a store.
@Model
final class SyncNotes {
    /// The engine's state, as the engine handed it over; nil when there is none to start from.
    var engineState: Data? = nil
    /// The name of the zone this device uses or last used; nil before the first join and after a sign-out.
    var zoneName: String? = nil
    /// What the device knows of that zone, a ``ZoneKnowledge``.
    var zoneKnowledge: Int = 0
    /// The highest zone number this device has heard of; 0 when none.
    var highestNumber: Int = 0
    /// The id of the iCloud account this data belongs to; nil before the first time.
    var account: String? = nil
    /// Whether iCloud last refused a save because the person's iCloud storage is full.
    var storageFull: Bool = false

    init() {}
}

/// What the device knows of the zone in its zone note (docs/icloud.md, section 9).
enum ZoneKnowledge: Int, Sendable {
    case notKnownToExist = 0
    case existing = 1
    case deleted = 2
}

/// The zone note: one zone's name, with what the device knows of it.
struct ZoneNote: Equatable, Sendable {
    var zone: ZoneName
    var knowledge: ZoneKnowledge
}

extension KeptPlay {
    /// Where the play stands with iCloud. A value this build does not know reads as sent, which offers the play again.
    var sync: PlaySyncState {
        get { PlaySyncState(rawValue: state) ?? .sent }
        set { state = newValue.rawValue }
    }

    /// The play, when this build can read its payload.
    var record: PlayRecord? {
        FinishedPlayPayload(format: format, payload: payload, recordName: playID.uuidString)?.play
    }

    /// Takes the content of `record`: its format and payload, as they are.
    func takeContent(of record: CloudRecord) {
        format = record.format ?? 0
        payload = record.payload ?? Data()
        finishedAt = FinishedPlayPayload(format: format, payload: payload, recordName: playID.uuidString)?.play.finishedAt
            ?? .distantPast
    }

    /// Takes the system fields of `record`, with the zone they belong to.
    func takeSystemFields(of record: CloudRecord) {
        systemFields = record.systemFields
        systemFieldsZone = record.systemFields == nil ? nil : record.zone
    }

    /// The record to send for this play into `zone`: its payload as kept, with its system fields when they belong to
    /// `zone`, and as a new record otherwise.
    func recordToSend(in zone: String) -> RecordToSend {
        RecordToSend(
            type: CloudRecord.finishedPlayType, zone: zone, name: playID.uuidString,
            systemFields: systemFieldsZone == zone ? systemFields : nil, format: format, payload: payload
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
        side.held = kept.held.flatMap { try? decoder.decode(ToySide.Held.self, from: $0) }
        return side
    }

    /// Writes `side` into the store's `KeptToy`, making it when there is none, unless the store already keeps it. Nothing
    /// is saved yet.
    func write(_ side: ToySide) throws {
        guard try toySide() != side else { return }
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

    // MARK: The notes

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

    // MARK: The finished plays

    /// The entries of the plays with `ids`, by id.
    func plays(_ ids: some Collection<UUID>) throws -> [UUID: KeptPlay] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let found = try syncContext.fetch(FetchDescriptor<KeptPlay>(predicate: #Predicate { wanted.contains($0.playID) }))
        var byID: [UUID: KeptPlay] = [:]
        for entry in found where byID[entry.playID] == nil { byID[entry.playID] = entry }
        return byID
    }

    /// Every entry in `state`.
    func plays(in state: PlaySyncState) throws -> [KeptPlay] {
        let raw = state.rawValue
        return try syncContext.fetch(FetchDescriptor<KeptPlay>(predicate: #Predicate { $0.state == raw }))
    }

    /// Every entry that is not in iCloud: unsent, sent or cleared, the oldest first.
    func playsNotInICloud() throws -> [KeptPlay] {
        let inICloud = PlaySyncState.inICloud.rawValue
        return try syncContext.fetch(FetchDescriptor<KeptPlay>(
            predicate: #Predicate { $0.state != inICloud },
            sortBy: [SortDescriptor(\.finishedAt), SortDescriptor(\.playID)]
        ))
    }

    /// Every entry with system fields of a zone other than `zone`, or of any zone when `zone` is nil.
    func plays(withSystemFieldsOutside zone: String?) throws -> [KeptPlay] {
        if let zone {
            return try syncContext.fetch(FetchDescriptor<KeptPlay>(predicate: #Predicate {
                $0.systemFieldsZone != nil && $0.systemFieldsZone != zone
            }))
        }
        return try syncContext.fetch(FetchDescriptor<KeptPlay>(predicate: #Predicate { $0.systemFieldsZone != nil }))
    }

    /// Every entry, the oldest first.
    func allPlays() throws -> [KeptPlay] {
        try syncContext.fetch(FetchDescriptor<KeptPlay>(sortBy: [SortDescriptor(\.finishedAt), SortDescriptor(\.playID)]))
    }

    /// Every entry that is not cleared, newest first.
    func playsShown() throws -> [KeptPlay] {
        let cleared = PlaySyncState.cleared.rawValue
        return try syncContext.fetch(FetchDescriptor<KeptPlay>(
            predicate: #Predicate { $0.state != cleared },
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse), SortDescriptor(\.playID)]
        ))
    }

    /// Adds an entry.
    func insert(_ entry: KeptPlay) {
        syncContext.insert(entry)
    }

    /// Removes an entry.
    func delete(_ entry: KeptPlay) {
        syncContext.delete(entry)
    }

    /// Removes every finished play.
    func removeAllPlays() throws {
        for entry in try allPlays() { syncContext.delete(entry) }
    }

    // MARK: Saving

    /// Saves what the call changed, in one save. When the save fails, the store goes back to its last saved state and
    /// the error is thrown.
    func saveSync() throws {
        guard syncContext.hasChanges else { return }
        do {
            if failsNextSyncSave {
                failsNextSyncSave = false
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try syncContext.save()
        } catch {
            syncContext.rollback()
            throw error
        }
    }

    /// Forgets what a call changed and has not saved.
    func rollBackSync() {
        syncContext.rollback()
    }
}
