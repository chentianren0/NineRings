import Foundation
@testable import Records

/// A stand-in for CloudKit's private databases, one for each account, with the behaviour that docs/icloud.md's sources
/// and the probe of CloudKit's development environment (docs/icloud-probe.md) describe. The rules' tests run against it
/// in memory, since Apple gives no stand-in of its own (source 21).
///
/// What it does, as CloudKit did in the probe or as Apple documents:
/// - Zones are kept by name. Saving a zone that exists changes nothing (probe D). A zone's save under the name of a zone
///   that was deleted makes it again, and from then on its deletion is reported to no one (probes C.6 and E).
/// - Every record carries a change tag. Change tags are counters of the zone, and they start again when a zone is made
///   again under its name (probe 3).
/// - A save built on a tag that is not the record's is refused, with the record attached (probe 2). A first save under a
///   name that exists is refused in the same way (probe 1; open point 1: or without the record, by ``Choices``).
/// - A save on the system fields of a record that is not there is refused as unknown; a save without them makes the
///   record (probe 5). Deleting a record that is not there succeeds (probe 6).
/// - A save or a deletion into a zone that does not exist is refused: plainly missing, marked as an encryption reset,
///   or as deleted by the person, by how the zone went (probe C; source 34).
/// - A save is refused while the person's storage is full (source 13).
/// - A report of the database's zones names the zones changed since the token, or every zone for an engine with no
///   token, and the zones deleted since then whose names are not in use again, with the reason of their deletion
///   (probes A and B). A deletion's report can expire (open point 13).
/// - A fetch of a zone from a token brings every record changed since then, as it now is, and every record deleted since
///   then. A token from another making of the zone, or none, brings every record (probe E); with none, also the
///   deletions of records deleted in the zone, all of them or only those of records the fetching device made, by
///   ``Choices`` (open point 5).
///
/// Where Apple documents nothing and the probe did not see, it can do either, by ``Choices``.
@MainActor
final class StandInICloud {
    /// What the stand-in does where Apple's documentation is silent.
    struct Choices: Sendable, CustomStringConvertible {
        /// Whether a fetch from nothing brings the deletions of every record deleted earlier in the zone, as one developer
        /// and the probe saw; otherwise only of the records the fetching device made, as Apple's engineers describe it
        /// (source 50, open point 5).
        var fetchFromNothingBringsOldDeletions = true
        /// Whether a refusal because a record of that name exists carries iCloud's record (open point 1).
        var refusalCarriesRecord = true
        /// How often a device's own saves come back to it in its fetches, from 0 to 1 (source 17). A save whose answer the
        /// device never handled always comes back: an engine can leave out only what it knows it sent.
        var ownChangesComeBack = 1.0
        /// Whether a report names a zone whose only changes since the token are the fetching device's own (open
        /// point 17). A report from nothing names every zone.
        var reportsOwnZoneChanges = true
        /// Whether a purge or a reset of encrypted data is reported as a zone's deletion with its reason; otherwise the
        /// zone is named as changed, and its fetch ends with the error (open point 15). Saves meet the error either way.
        var lossesReportedAsDeletions = true

        var description: String {
            "old deletions from nothing: \(fetchFromNothingBringsOldDeletions), refusal carries record: \(refusalCarriesRecord), "
                + "own changes come back: \(ownChangesComeBack), own zone changes reported: \(reportsOwnZoneChanges), "
                + "losses reported as deletions: \(lossesReportedAsDeletions)"
        }
    }

    var choices: Choices
    /// Where a trace of every save and deletion goes, for a test that looks into one order of events.
    var trace: ((String) -> Void)?
    /// Told of every zone deleted with the reason *purged* or *deleted*: the person, or another copy of the app, deleted
    /// the app's data there.
    var zonePurged: (() -> Void)?
    /// Every request that reached iCloud, in order, whatever it came to: a record's save or deletion, or a zone's save,
    /// with the device that sent it. A round of settling that sends anything has not settled.
    private(set) var requests: [Request] = []

    struct Request: Equatable {
        var device: String?
        var zone: String
        /// The record's name; nil for a zone's own save.
        var name: String?
    }
    /// Draws for the choices given as a share.
    var random: SeededRandom

    init(choices: Choices = Choices(), seed: UInt64 = 1) {
        self.choices = choices
        random = SeededRandom(seed: seed ^ 0x5eed)
    }

    /// One account's private database.
    final class Database {
        /// The zones that exist, by name.
        var zones: [String: Zone] = [:]
        /// How each zone that does not exist went, by name: the reason of its deletion, or nil for a zone that went
        /// without a reason anyone is told.
        var gone: [String: ZoneDeletionReason?] = [:]
        /// The database's changes, in order: a zone made, changed or deleted.
        var log: [Change] = []
        var seq = 0
        /// Whether the person's iCloud storage is full.
        var isFull = false
        /// How many zones were made, to tell one making of a zone from another.
        var makings = 0

        struct Change {
            var seq: Int
            var zone: String
            /// The device that made the change; nil for a change the test made.
            var by: String?
            /// The reason of a deletion; nil for a zone made or changed.
            var deletion: ZoneDeletionReason?
            /// Whether a deletion is reported to engines: false once its report expired, or for a zone that went
            /// without a report.
            var reported = true
        }
    }

    /// One making of a zone.
    final class Zone {
        let name: String
        let making: Int
        /// The zone's counter, from which every change tag comes. A zone made again starts again.
        var counter = 0
        var records: [String: Stored] = [:]
        /// Every save and deletion, in order, with the device that made it and whether that device handled the answer.
        var changes: [(seq: Int, name: String, by: String?, answered: Bool)] = []
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

    /// Every account that has a database, for the tests' looking.
    var accounts: [String] { databases.keys.sorted() }

    // MARK: Zones

    /// What a zone's save came to.
    enum ZoneSaveOutcome: Equatable {
        case saved
        case storageFull
    }

    /// Saves the zone named `name`: makes it if it is missing, and changes nothing if it exists.
    @discardableResult
    func saveZone(_ name: String, account: String, device: String?) -> ZoneSaveOutcome {
        requests.append(Request(device: device, zone: name, name: nil))
        let database = database(account)
        guard database.zones[name] == nil else { return .saved }
        guard !database.isFull else { return .storageFull }
        database.makings += 1
        database.zones[name] = Zone(name: name, making: database.makings)
        database.gone[name] = nil
        logChange(zone: name, by: device, in: database)
        return .saved
    }

    /// Deletes the zone named `name`, with every record in it, for `reason`: as the person deleting the app's data from
    /// iCloud in Settings, or resetting their encrypted data, would; or another copy of the app.
    func deleteZone(_ name: String, account: String, reason: ZoneDeletionReason) {
        let database = database(account)
        guard database.zones.removeValue(forKey: name) != nil else { return }
        database.gone[name] = reason
        if reason != .encryptedDataReset { zonePurged?() }
        database.seq += 1
        let reported = reason == .deleted || choices.lossesReportedAsDeletions
        database.log.append(Database.Change(seq: database.seq, zone: name, by: nil, deletion: reason, reported: reported))
        if !reported {
            // The loss is not reported as a deletion: the zone is named as changed, and its fetch meets the error.
            database.seq += 1
            database.log.append(Database.Change(seq: database.seq, zone: name, by: nil, deletion: nil))
        }
    }

    /// Deletes every zone of the account: what the person deleting the app's data from iCloud does.
    func deleteEveryZone(account: String, reason: ZoneDeletionReason) {
        for name in database(account).zones.keys.sorted() { deleteZone(name, account: account, reason: reason) }
    }

    /// The zone named `name` goes without anyone being told why: a zone found missing (section 9).
    func loseZoneSilently(_ name: String, account: String) {
        let database = database(account)
        guard database.zones.removeValue(forKey: name) != nil else { return }
        database.gone[name] = .some(nil)
    }

    /// Every report of a zone's deletion expires (open point 13).
    func expireDeletionReports(account: String) {
        let database = database(account)
        for index in database.log.indices where database.log[index].deletion != nil {
            database.log[index].reported = false
        }
    }

    /// The report of the database's zones for a token, `since`, or for an engine with none, for the device `device`; and
    /// the token to fetch from next. A zone named as changed exists, or went with a loss that is reported only as an error.
    func databaseChanges(account: String, since token: Int?, device: String) -> (existing: [String], deleted: [ZoneDeletion], token: Int) {
        let database = database(account)
        var changed: [String] = []
        var deletions: [String: ZoneDeletionReason] = [:]
        if token == nil {
            changed = database.zones.keys.sorted()
            for change in database.log where change.reported {
                if let reason = change.deletion, database.zones[change.zone] == nil { deletions[change.zone] = reason }
            }
            // A zone that went with a loss reported only as an error is named, so that its fetch meets the error.
            changed += database.gone.keys.sorted().filter { isLossReportedOnlyAsError($0, in: database) }
        } else if let token {
            var seen = Set<String>()
            for change in database.log where change.seq > token {
                if let reason = change.deletion {
                    if change.reported, database.zones[change.zone] == nil { deletions[change.zone] = reason }
                } else if change.by != device || choices.reportsOwnZoneChanges, seen.insert(change.zone).inserted {
                    if database.zones[change.zone] != nil || isLossReportedOnlyAsError(change.zone, in: database) {
                        changed.append(change.zone)
                    }
                }
            }
        }
        let existing = changed.filter { deletions[$0] == nil }
        let deleted = deletions.keys.sorted().map { ZoneDeletion(zone: $0, reason: deletions[$0]!) }
        return (existing, deleted, database.seq)
    }

    /// Whether the zone named `name` went by a purge or a reset that is not reported as a deletion.
    private func isLossReportedOnlyAsError(_ name: String, in database: Database) -> Bool {
        guard database.zones[name] == nil, let reason = database.gone[name] ?? nil else { return false }
        return reason != .deleted && !choices.lossesReportedAsDeletions
    }

    /// Whether the zone exists.
    func hasZone(_ name: String, account: String) -> Bool {
        database(account).zones[name] != nil
    }

    /// The zones that exist, by name, for the tests' looking.
    func zoneNames(account: String) -> [String] {
        database(account).zones.keys.sorted()
    }

    /// The error that a save into, or a fetch of, the missing zone `name` meets.
    func zoneError(_ name: String, in database: Database) -> ZoneGone {
        switch database.gone[name] ?? nil {
        case .encryptedDataReset?: .encryptedDataReset
        case .purged?: .userDeletedZone
        case .deleted?, nil: .missing
        }
    }

    // MARK: Records

    /// What a save came to.
    enum SaveOutcome: Equatable {
        case saved(CloudRecord)
        case refused(CloudRecord?)
        case unknownItem
        case zoneGone(ZoneGone)
        case storageFull
    }

    /// Saves `record` for the device `device`. The save counts as answered once the device has handled its answer
    /// (``markAnswered(_:account:device:)``).
    func save(_ record: RecordToSend, account: String, device: String?) -> SaveOutcome {
        requests.append(Request(device: device, zone: record.zone, name: record.name))
        let database = database(account)
        guard let zone = database.zones[record.zone] else { return .zoneGone(zoneError(record.zone, in: database)) }
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
        if zone.records[record.name] == nil, let device { zone.madeBy[record.name] = device }
        zone.counter += 1
        let stored = Stored(type: record.type, name: record.name, format: record.format, payload: record.payload, tag: String(zone.counter, radix: 36))
        zone.records[record.name] = stored
        zone.seq += 1
        zone.changes.append((zone.seq, record.name, device, false))
        logChange(zone: zone.name, by: device, in: database)
        trace?("CLOUD \(device ?? "-") saved \(record.zone.prefix(14))/\(record.name.prefix(6)) seq \(zone.seq)")
        return .saved(cloudRecord(stored, zone: zone))
    }

    /// The device handled the answer to its save of the record `id`: its engine now knows the save was its own.
    func markAnswered(_ id: RecordID, account: String, device: String) {
        guard let zone = database(account).zones[id.zone],
              let index = zone.changes.lastIndex(where: { $0.name == id.name }), zone.changes[index].by == device else { return }
        zone.changes[index].answered = true
    }

    /// The device's engine goes back to a state from a backup, which knows none of the answers it handled since: from
    /// then on its own saves come back to it, as any save whose answer it never handled.
    func forgetAnswers(device: String) {
        for database in databases.values {
            for zone in database.zones.values {
                for index in zone.changes.indices where zone.changes[index].by == device { zone.changes[index].answered = false }
            }
        }
    }

    /// What a deletion came to.
    enum DeletionOutcome: Equatable {
        case deleted
        case zoneGone(ZoneGone)
    }

    /// Deletes the record `id`, for the device `device`. Deleting a record that is not there succeeds (probe 6).
    func delete(_ id: RecordID, account: String, device: String?) -> DeletionOutcome {
        requests.append(Request(device: device, zone: id.zone, name: id.name))
        let database = database(account)
        guard let zone = database.zones[id.zone] else { return .zoneGone(zoneError(id.zone, in: database)) }
        guard zone.records.removeValue(forKey: id.name) != nil else { return .deleted }
        zone.deleted.insert(id.name)
        zone.seq += 1
        zone.changes.append((zone.seq, id.name, device, true))
        logChange(zone: zone.name, by: device, in: database)
        trace?("CLOUD \(device ?? "-") deleted \(id.zone.prefix(14))/\(id.name.prefix(6)) seq \(zone.seq)")
        return .deleted
    }

    /// The zone's changes since `token`, for the device `device`; an error when the zone does not exist.
    func changes(zone name: String, account: String, since token: ZoneToken?, device: String) -> Result<(records: [CloudRecord], deletions: [DeletedRecord], token: ZoneToken), ZoneGoneError> {
        let database = database(account)
        guard let zone = database.zones[name] else { return .failure(ZoneGoneError(gone: zoneError(name, in: database))) }
        let next = ZoneToken(making: zone.making, seq: zone.seq)
        guard let token, token.making == zone.making else {
            let records = zone.records.values
                .sorted { lastChange(of: $0.name, in: zone) < lastChange(of: $1.name, in: zone) }
                .map { cloudRecord($0, zone: zone) }
            var deletions: [DeletedRecord] = []
            if token == nil {
                deletions = zone.deleted.sorted()
                    .filter { zone.records[$0] == nil && (choices.fetchFromNothingBringsOldDeletions || zone.madeBy[$0] == device) }
                    .map { DeletedRecord(id: RecordID(zone: name, name: $0)) }
            }
            return .success((records, deletions, next))
        }
        var records: [CloudRecord] = []
        var deletions: [DeletedRecord] = []
        var seen = Set<String>()
        for change in zone.changes.reversed() where change.seq > token.seq && seen.insert(change.name).inserted {
            if let stored = zone.records[change.name] {
                if change.by == device, change.answered, random.chance(1 - choices.ownChangesComeBack) { continue }
                records.append(cloudRecord(stored, zone: zone))
            } else {
                deletions.append(DeletedRecord(id: RecordID(zone: name, name: change.name)))
            }
        }
        return .success((records.reversed(), deletions.reversed(), next))
    }

    struct ZoneGoneError: Error {
        var gone: ZoneGone
    }

    /// The record `id` as iCloud now has it, for the tests' looking.
    func record(_ id: RecordID, account: String) -> CloudRecord? {
        guard let zone = database(account).zones[id.zone], let stored = zone.records[id.name] else { return nil }
        return cloudRecord(stored, zone: zone)
    }

    /// Every record in the zone named `name`, for the tests' looking.
    func records(zone name: String, account: String) -> [CloudRecord] {
        guard let zone = database(account).zones[name] else { return [] }
        return zone.records.values.sorted { $0.name < $1.name }.map { cloudRecord($0, zone: zone) }
    }

    // MARK: Inside

    private func logChange(zone: String, by device: String?, in database: Database) {
        database.seq += 1
        database.log.append(Database.Change(seq: database.seq, zone: zone, by: device, deletion: nil))
    }

    private func cloudRecord(_ stored: Stored, zone: Zone) -> CloudRecord {
        let fields = SystemFields(zone: zone.name, name: stored.name, tag: stored.tag)
        return CloudRecord(
            type: stored.type, zone: zone.name, name: stored.name, changeTag: stored.tag,
            systemFields: try? JSONEncoder().encode(fields), format: stored.format, payload: stored.payload
        )
    }

    private func lastChange(of name: String, in zone: Zone) -> Int {
        zone.changes.last { $0.name == name }?.seq ?? 0
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
