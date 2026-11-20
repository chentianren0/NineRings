import Foundation
@testable import Records

/// A stand-in for CloudKit's private databases, one for each account, with the behaviour the design's sources and the
/// probe of CloudKit's development environment describe. The rules' tests run against it in memory, since Apple gives
/// no stand-in of its own (docs/icloud.md, source 21).
///
/// What it does, as CloudKit does:
/// - Every record carries a change tag that changes with each save. Change tags are counters of the zone, and they start
///   again when a zone is made again under the same name (the probe).
/// - A save built on a tag that is not the record's is refused, with the record attached [9]. A first save under a name
///   that exists is refused in the same way [49] (open point 1: or, as an older report has it, without the record).
/// - A save built on a record that is no longer there fails as unknown [52]. A save without a tag makes a new record.
/// - A save or deletion in a zone that is missing fails as such, marked as a reset of encrypted data when the zone was
///   lost that way [34].
/// - A fetch brings every record changed since the token, as it now is, and every record deleted since then that is not
///   there now. A fetch from nothing brings every record, and the deletions of records the fetching device made [50].
/// - The deletion of a zone is reported, with its reason [6], to every fetch of the database's changes that comes after
///   it, also to an engine with no state, as long as the zone does not exist at the fetch. A zone that exists again is
///   not reported as deleted, and a fetch with a token from before shows its new records (the probe).
///
/// Where Apple documents nothing, it can do either, by ``Choices``.
@MainActor
final class StandInICloud {
    /// What the stand-in does where Apple's documentation is silent.
    struct Choices: Sendable, CustomStringConvertible {
        /// Whether a fetch from nothing brings the deletions of every record deleted earlier in the zone, as one developer
        /// saw [17]; otherwise only of the records the fetching device made, as Apple's engineers describe it [50].
        var fetchFromNothingBringsOldDeletions = false
        /// Whether a first save under a name that exists is refused with iCloud's record attached (open point 1).
        var refusalCarriesRecord = true
        /// How often a device's own saves come back to it in its fetches, from 0 to 1 [17]. A save whose answer the device
        /// never handled always comes back: an engine can leave out only what it knows it sent.
        var ownChangesComeBack = 1.0
        /// Whether deleting a record that is not there is confirmed, rather than answered as already gone.
        var deletingAMissingRecordIsConfirmed = false

        var description: String {
            "old deletions from nothing: \(fetchFromNothingBringsOldDeletions), refusal carries record: \(refusalCarriesRecord), "
                + "own changes come back: \(ownChangesComeBack), missing deletion confirmed: \(deletingAMissingRecordIsConfirmed)"
        }
    }

    var choices: Choices
    /// Draws for the choices given as a share.
    var random: SeededRandom

    init(choices: Choices = Choices(), seed: UInt64 = 1) {
        self.choices = choices
        random = SeededRandom(seed: seed ^ 0x5eed)
    }

    /// One account's private database.
    final class Database {
        var zones: [String: Zone] = [:]
        /// Every zone made and deleted, in order: the database's changes.
        var changes: [(seq: Int, zone: String, deletion: ZoneDeletionReason?)] = []
        var seq = 0
        /// Whether the person's iCloud storage is full.
        var isFull = false
        /// How many zones were made, to tell one making of a zone from another.
        var zonesMade = 0
    }

    /// One making of a zone.
    final class Zone {
        let name: String
        let making: Int
        /// The zone's counter, from which every change tag comes. A zone made again starts again.
        var counter = 0
        var records: [String: Stored] = [:]
        /// Every save and deletion, in order, with the device that made it and whether that device handled the answer.
        var changes: [(seq: Int, name: String, by: String, answered: Bool)] = []
        var seq = 0
        /// The names of records deleted in this zone.
        var deleted: Set<String> = []
        /// The device that made each record that was made in this zone.
        var madeBy: [String: String] = [:]

        init(name: String, making: Int) {
            self.name = name
            self.making = making
        }
    }

    /// A record as the stand-in keeps it.
    struct Stored: Equatable {
        var type: String
        var name: String
        var format: Int
        var payload: Data
        var tag: String
    }

    /// Where a fetch of a zone's changes stopped.
    struct ZoneToken: Codable, Equatable {
        var making: Int
        var seq: Int
    }

    /// The system fields the stand-in hands out: what a later save needs to name the version it was built on.
    struct SystemFields: Codable, Equatable {
        var zone: String
        var name: String
        var tag: String
    }

    private var databases: [String: Database] = [:]

    func database(_ account: String) -> Database {
        if let database = databases[account] { return database }
        let database = Database()
        databases[account] = database
        return database
    }

    // MARK: Zones

    /// Makes the zone if it is missing; saving a zone that exists changes nothing.
    func saveZone(_ name: String, account: String) {
        let database = database(account)
        guard database.zones[name] == nil else { return }
        database.zonesMade += 1
        database.zones[name] = Zone(name: name, making: database.zonesMade)
        database.seq += 1
        database.changes.append((database.seq, name, nil))
    }

    /// Deletes the zone, with every record in it, for `reason`: as the person deleting the app's data from iCloud in
    /// Settings, or resetting their encrypted data, would.
    func deleteZone(_ name: String, account: String, reason: ZoneDeletionReason) {
        let database = database(account)
        guard database.zones.removeValue(forKey: name) != nil else { return }
        database.seq += 1
        database.changes.append((database.seq, name, reason))
    }

    /// The zones deleted since `token`, or ever when it is nil, that do not exist now, each with the reason of its last
    /// deletion; and the token to fetch from next.
    func zoneDeletions(account: String, since token: Int?) -> (deletions: [(zone: String, reason: ZoneDeletionReason)], token: Int) {
        let database = database(account)
        var last: [String: ZoneDeletionReason] = [:]
        var order: [String] = []
        for change in database.changes where change.seq > (token ?? 0) {
            guard let reason = change.deletion else { continue }
            if last[change.zone] == nil { order.append(change.zone) }
            last[change.zone] = reason
        }
        let deletions = order.filter { database.zones[$0] == nil }.map { ($0, last[$0]!) }
        return (deletions, database.seq)
    }

    // MARK: Records

    /// What a save came to.
    enum SaveOutcome: Equatable {
        case saved(CloudRecord)
        case refused(CloudRecord?)
        case unknownItem
        case zoneMissing(encryptedDataReset: Bool)
        case storageFull
    }

    /// Saves `record` in zone `zoneName`, for the device `device`. The save counts as answered once the device has
    /// handled its answer (``markAnswered(_:zone:account:device:)``).
    func save(_ record: RecordToSend, zone zoneName: String, account: String, device: String) -> SaveOutcome {
        let database = database(account)
        guard let zone = database.zones[zoneName] else {
            return .zoneMissing(encryptedDataReset: lastDeletion(of: zoneName, in: database) == .encryptedDataReset)
        }
        guard !database.isFull else { return .storageFull }
        let base = record.systemFields.flatMap { try? JSONDecoder().decode(SystemFields.self, from: $0) }
        if let stored = zone.records[record.name] {
            guard let base, base.tag == stored.tag else {
                if base == nil, !choices.refusalCarriesRecord { return .refused(nil) }
                return .refused(cloudRecord(stored, zone: zone))
            }
        } else if base != nil {
            return .unknownItem
        }
        if zone.records[record.name] == nil { zone.madeBy[record.name] = device }
        zone.counter += 1
        let stored = Stored(type: record.type, name: record.name, format: record.format, payload: record.payload, tag: String(zone.counter))
        zone.records[record.name] = stored
        zone.seq += 1
        zone.changes.append((zone.seq, record.name, device, false))
        return .saved(cloudRecord(stored, zone: zone))
    }

    /// The device handled the answer to its save of the record named `name`: its engine now knows the save was its own.
    func markAnswered(_ name: String, zone zoneName: String, account: String, device: String) {
        guard let zone = database(account).zones[zoneName],
              let index = zone.changes.lastIndex(where: { $0.name == name }), zone.changes[index].by == device else { return }
        zone.changes[index].answered = true
    }

    /// What a deletion came to.
    enum DeletionOutcome: Equatable {
        case deleted
        case alreadyGone
        case zoneMissing(encryptedDataReset: Bool)
    }

    /// Deletes the record named `name` in zone `zoneName`, for the device `device`.
    func delete(_ name: String, zone zoneName: String, account: String, device: String) -> DeletionOutcome {
        let database = database(account)
        guard let zone = database.zones[zoneName] else {
            return .zoneMissing(encryptedDataReset: lastDeletion(of: zoneName, in: database) == .encryptedDataReset)
        }
        guard zone.records.removeValue(forKey: name) != nil else {
            return choices.deletingAMissingRecordIsConfirmed ? .deleted : .alreadyGone
        }
        zone.deleted.insert(name)
        zone.seq += 1
        zone.changes.append((zone.seq, name, device, true))
        return .deleted
    }

    /// The zone's changes since `token`, for the device `device`: nil when the zone is missing. A token from another
    /// making of the zone, or none, brings every record as it now is.
    func changes(zone zoneName: String, account: String, since token: ZoneToken?, device: String) -> (records: [CloudRecord], deletions: [DeletedRecord], token: ZoneToken)? {
        let database = database(account)
        guard let zone = database.zones[zoneName] else { return nil }
        let next = ZoneToken(making: zone.making, seq: zone.seq)
        guard let token, token.making == zone.making else {
            let records = zone.records.values
                .sorted { lastChange(of: $0.name, in: zone) < lastChange(of: $1.name, in: zone) }
                .map { cloudRecord($0, zone: zone) }
            var deletions: [DeletedRecord] = []
            if token == nil {
                deletions = zone.deleted.sorted()
                    .filter { zone.records[$0] == nil && (choices.fetchFromNothingBringsOldDeletions || zone.madeBy[$0] == device) }
                    .map { DeletedRecord(type: type(of: $0), name: $0) }
            }
            return (records, deletions, next)
        }
        var records: [CloudRecord] = []
        var deletions: [DeletedRecord] = []
        var seen = Set<String>()
        for change in zone.changes.reversed() where change.seq > token.seq && seen.insert(change.name).inserted {
            if let stored = zone.records[change.name] {
                if change.by == device, change.answered, random.chance(1 - choices.ownChangesComeBack) { continue }
                records.append(cloudRecord(stored, zone: zone))
            } else {
                deletions.append(DeletedRecord(type: type(of: change.name), name: change.name))
            }
        }
        return (records.reversed(), deletions.reversed(), next)
    }

    /// The record of `name` in zone `zoneName` as iCloud now has it, for the tests' looking.
    func record(_ name: String, zone zoneName: String, account: String) -> CloudRecord? {
        guard let zone = database(account).zones[zoneName], let stored = zone.records[name] else { return nil }
        return cloudRecord(stored, zone: zone)
    }

    /// Every record in zone `zoneName`, for the tests' looking.
    func records(zone zoneName: String, account: String) -> [CloudRecord] {
        guard let zone = database(account).zones[zoneName] else { return [] }
        return zone.records.values.sorted { $0.name < $1.name }.map { cloudRecord($0, zone: zone) }
    }

    /// Whether the zone exists.
    func hasZone(_ name: String, account: String) -> Bool {
        database(account).zones[name] != nil
    }

    // MARK: Inside

    private func cloudRecord(_ stored: Stored, zone: Zone) -> CloudRecord {
        let fields = SystemFields(zone: zone.name, name: stored.name, tag: stored.tag)
        return CloudRecord(
            type: stored.type, name: stored.name, changeTag: stored.tag, systemFields: try? JSONEncoder().encode(fields),
            format: stored.format, payload: stored.payload
        )
    }

    private func lastChange(of name: String, in zone: Zone) -> Int {
        zone.changes.last { $0.name == name }?.seq ?? 0
    }

    private func lastDeletion(of zoneName: String, in database: Database) -> ZoneDeletionReason? {
        database.changes.last { $0.zone == zoneName && $0.deletion != nil }?.deletion
    }

    /// The type of a record by its name: the toy's, or a finished play's.
    private func type(of name: String) -> String {
        name == CloudRecord.toyName ? CloudRecord.toyType : CloudRecord.finishedPlayType
    }
}

/// A random generator that a seed fixes, so that a failing order of events can be replayed (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// True with probability `p`.
    mutating func chance(_ p: Double) -> Bool {
        p >= 1 || (p > 0 && Double.random(in: 0..<1, using: &self) < p)
    }

    /// A UUID made of drawn bits.
    mutating func uuid() -> UUID {
        let a = next()
        let b = next()
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: a), UInt8(truncatingIfNeeded: a >> 8), UInt8(truncatingIfNeeded: a >> 16),
            UInt8(truncatingIfNeeded: a >> 24), UInt8(truncatingIfNeeded: a >> 32), UInt8(truncatingIfNeeded: a >> 40),
            UInt8(truncatingIfNeeded: a >> 48) & 0x0F | 0x40, UInt8(truncatingIfNeeded: a >> 56),
            UInt8(truncatingIfNeeded: b) & 0x3F | 0x80, UInt8(truncatingIfNeeded: b >> 8), UInt8(truncatingIfNeeded: b >> 16),
            UInt8(truncatingIfNeeded: b >> 24), UInt8(truncatingIfNeeded: b >> 32), UInt8(truncatingIfNeeded: b >> 40),
            UInt8(truncatingIfNeeded: b >> 48), UInt8(truncatingIfNeeded: b >> 56)
        ))
    }
}
