#if DEBUG
import CloudKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One run of the probe: the questions a launch asks, one after the other. Each question makes its own zones and its
/// own devices, from nothing unless the question is about a saved state, and deletes its zones at its end. A question's
/// `RESULT` lines say what it saw; the timeline above them shows every event.
///
/// The questions are in two files: `ProbeQuestions.swift` asks about records, accounts and scheduling (numbered), and
/// `ProbeZoneQuestions.swift` about zones that are deleted (lettered, A to G).
nonisolated struct ProbeRun: Sendable {
    /// The start of every zone name the probe makes. The probe deletes zones whose names begin with it, and no others.
    static let zonePrefix = "NineRingsProbeAgain_"

    let database: CKDatabase
    let report: ProbeReport
    /// A short id of this run, part of every zone's name.
    let run: String

    static let titles: [String: String] = [
        "1": "A first save under a record name that exists, from an engine that never fetched it",
        "2": "A save with stale system fields",
        "3": "What a saved record carries",
        "4": "An engine's own save coming back as a fetched change",
        "5": "A record deleted, then saved again under the same name",
        "6": "Deleting a record that is already gone",
        "7": "Saving into a zone that was never made",
        "8": "A fetch from nothing, in a zone where records were deleted",
        "9": "The account event of a new engine",
        "10": "Automatic syncing and pushes",
        "11": "Two engines from copies of one saved state",
        "12": "Records as the app writes them, against the imported schema",
        "13": "A fetch when the app comes to the front",
        "14": "A save and a deletion queued for one record",
        "15": "A save whose answer the app never stores: the first launch, which ends itself",
        "16": "A save whose answer the app never stores: the next start",
        "A": "A zone deleted, and the next one made under another name: what an engine that knew the first is told, and (B) a new engine",
        "B": "A zone deleted, and the next one made under another name: what an engine that knew the first is told, and (B) a new engine",
        "C": "Saving into a deleted zone, before the deletion has been fetched",
        "D": "Saving a zone that exists, and two engines saving the same new zone",
        "E": "A zone made again under its old name, and a token from far ahead",
        "F": "How long deletion reports live",
        "G": "A save on a stale base accepted in a zone made again: can the other engines read it",
    ]

    /// What `all` asks: every question but 15 and 16, which take two launches of their own. A answers B as well.
    static let askedByAll = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "A", "C", "D", "E", "F", "G"]
    /// What `zones` asks: the questions about deleted zones. A answers B as well.
    static let askedByZones = ["A", "C", "D", "E", "F", "G"]

    func ask(_ question: String) async {
        guard let title = Self.titles[question] else {
            return await report.say("--", "no question \(question)")
        }
        await report.heading("\(question). \(title)")
        switch question {
        case "1": await q1()
        case "2": await q2()
        case "3": await q3()
        case "4": await q4()
        case "5": await q5()
        case "6": await q6()
        case "7": await q7()
        case "8": await q8()
        case "9": await q9()
        case "10": await q10()
        case "11": await q11()
        case "12": await q12()
        case "13": await q13()
        case "14": await q14()
        case "15": await q15()
        case "16": await q16()
        case "A", "B": await qAB()
        case "C": await qC()
        case "D": await qD()
        case "E": await qE()
        case "F": await qF()
        case "G": await qG()
        default: break
        }
    }

    // MARK: Zones, records and devices

    /// A zone of this run, named `NineRingsProbeAgain_<run>_<suffix>`. No two zones of a run share a suffix.
    func zone(_ suffix: String) -> CKRecordZone {
        CKRecordZone(zoneName: "\(Self.zonePrefix)\(run)_\(suffix)")
    }

    func toyID(_ zone: CKRecordZone) -> CKRecord.ID {
        CKRecord.ID(recordName: "toy", zoneID: zone.zoneID)
    }

    func playID(_ zone: CKRecordZone) -> CKRecord.ID {
        CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
    }

    /// A device whose fetches read `scope`.
    func device(
        _ name: String, scope: CKSyncEngine.FetchChangesOptions.Scope, state: CKSyncEngine.State.Serialization? = nil, automatic: Bool = false
    ) async -> ProbeDevice {
        let device = ProbeDevice(name: name, database: database, scope: scope, report: report)
        await device.start(state: state, automaticallySync: automatic)
        return device
    }

    /// A device whose fetches read `zone` alone.
    func device(
        _ name: String, _ zone: CKRecordZone, state: CKSyncEngine.State.Serialization? = nil, automatic: Bool = false
    ) async -> ProbeDevice {
        await device(name, scope: .zoneIDs([zone.zoneID]), state: state, automatic: automatic)
    }

    /// Lets the devices go and deletes the question's zones.
    func finish(_ zones: [CKRecordZone], _ devices: [ProbeDevice]) async {
        for device in devices { await device.stop() }
        for zone in zones { await removeZone(zone.zoneID) }
    }

    /// Deletes a zone of the probe directly, not through an engine, so that no engine of the probe hears of it as its
    /// own act. It refuses any zone whose name does not begin with ``zonePrefix``.
    func removeZone(_ id: CKRecordZone.ID) async {
        guard ProbeText.isProbeZone(id) else {
            return await report.say("--", "REFUSED to delete zone \(id.zoneName): not a zone of this probe")
        }
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [id])
            await report.say("--", "zone \(id.zoneName) deleted at \(Date.now.formatted(.iso8601))")
        } catch {
            await report.say("--", "zone \(id.zoneName) not deleted: \(ProbeText.error(error))")
        }
    }

    /// Says, before the probe makes any engine, whether the app is registered for remote notifications, which
    /// subscriptions the database holds, and which zones it has.
    func describeStart() async {
        await report.say("--", "before any engine: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")
        do {
            let zones = try await database.allRecordZones().map(\.zoneID.zoneName).sorted()
            await report.say("--", "the private database has \(zones.count) zones: \(zones)")
        } catch {
            await report.say("--", "the zones could not be listed: \(ProbeText.error(error))")
        }
    }

    /// Deletes every zone of this probe still in the database: those of earlier runs that stopped part way, and this
    /// run's. The zone question 15 left for question 16 stays until question 16 deletes it.
    func removeProbeZones() async {
        do {
            let kept = Self.lostAnswerZone
            let zones = try await database.allRecordZones().filter { ProbeText.isProbeZone($0.zoneID) && $0.zoneID.zoneName != kept }
            guard !zones.isEmpty else { return await report.say("--", "no zones of this probe in the database") }
            _ = try await database.modifyRecordZones(saving: [], deleting: zones.map(\.zoneID))
            await report.say("--", "zones of this probe deleted at \(Date.now.formatted(.iso8601)): \(zones.map(\.zoneID.zoneName))")
        } catch {
            await report.say("--", "the zones of this probe could not be listed or deleted: \(ProbeText.error(error))")
        }
    }

    /// Whether the database has a zone of that name, read directly.
    func zoneExists(_ id: CKRecordZone.ID) async -> String {
        do {
            return try await database.allRecordZones().contains { $0.zoneID == id } ? "exists" : "does not exist"
        } catch {
            return "unknown: \(ProbeText.error(error))"
        }
    }

    /// Whether the server holds `id`, read directly from the database, not through an engine.
    func onServer(_ id: CKRecord.ID) async -> String {
        do {
            let record = try await database.record(for: id)
            return "on the server: [\(ProbeText.record(record))] \(ProbeText.recordDetails(record))"
        } catch let error as CKError where error.code == .unknownItem {
            return "not on the server"
        } catch {
            return "not read: \(ProbeText.error(error))"
        }
    }

    // MARK: Waiting and describing

    func waitFor(
        _ device: ProbeDevice, since mark: Int, seconds: Double, _ predicate: @escaping @Sendable (ProbeDevice.Logged) -> Bool
    ) async -> ProbeDevice.Logged? {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let found = await device.events(since: mark).first(where: predicate) { return found }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    func registeredForPushes() async -> Bool {
        await MainActor.run {
            #if os(macOS)
            NSApplication.shared.isRegisteredForRemoteNotifications
            #else
            UIApplication.shared.isRegisteredForRemoteNotifications
            #endif
        }
    }

    func subscriptionIDs() async -> String {
        do {
            return "\(try await database.allSubscriptions().map { "\($0.subscriptionID) (\(type(of: $0)))" })"
        } catch {
            return "not readable: \(ProbeText.error(error))"
        }
    }

    func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return "\(ProbeText.decimal(seconds, places: 1)) s"
    }

    /// What became of a save of `id` in `events`: accepted with the record that came back, or refused with the error.
    func outcome(of id: CKRecord.ID, in events: [ProbeDevice.Logged]) -> String {
        if let saved = savedRecords(events).last(where: { $0.recordID == id }) {
            return "accepted: [\(ProbeText.record(saved))]"
        }
        if let failure = failedSaves(events).last(where: { $0.record.recordID == id }) {
            return "refused: \(ProbeText.error(failure.error))"
        }
        return "neither accepted nor refused"
    }

    func deleteOutcome(of id: CKRecord.ID, in events: [ProbeDevice.Logged]) -> String {
        for logged in events.reversed() {
            guard case .sentRecordZoneChanges(let sent) = logged.event else { continue }
            if sent.deletedRecordIDs.contains(id) { return "reported as deleted" }
            if let error = sent.failedRecordDeletes[id] { return "refused: \(ProbeText.error(error))" }
        }
        return "neither reported deleted nor refused"
    }

    /// What became of a zone's save in `events`.
    func zoneSaveOutcome(of id: CKRecordZone.ID, in events: [ProbeDevice.Logged]) -> String {
        for logged in events.reversed() {
            guard case .sentDatabaseChanges(let sent) = logged.event else { continue }
            if sent.savedZones.contains(where: { $0.zoneID == id }) { return "saved" }
            if let failure = sent.failedZoneSaves.first(where: { $0.zone.zoneID == id }) { return "refused: \(ProbeText.error(failure.error))" }
        }
        return "neither saved nor refused"
    }

    /// The order in which zones and records went out.
    func order(_ events: [ProbeDevice.Logged]) -> String {
        events.compactMap { logged -> String? in
            switch logged.event {
            case .sentDatabaseChanges(let sent): "zones sent (saved \(sent.savedZones.count), failed \(sent.failedZoneSaves.count))"
            case .sentRecordZoneChanges(let sent): "records sent (saved \(sent.savedRecords.count), failed \(sent.failedRecordSaves.count))"
            default: nil
            }
        }.joined(separator: ", then ")
    }

    /// Everything a fetch told a device about the probe's zones, in the order it arrived: database changes (zones
    /// modified and deleted, with reasons), the zone fetches begun and ended (with any error), and the records and record
    /// deletions delivered. Zones that are not the probe's are counted.
    func told(_ events: [ProbeDevice.Logged]) -> String {
        let lines = events.compactMap { logged -> String? in
            switch logged.event {
            case .fetchedDatabaseChanges(let changes):
                let modified = changes.modifications.map(\.zoneID).filter(ProbeText.isProbeZone).map(\.zoneName)
                let deleted = changes.deletions.filter { ProbeText.isProbeZone($0.zoneID) }.map { "\($0.zoneID.zoneName) (\(ProbeText.reason($0.reason)))" }
                let others = changes.modifications.count - modified.count
                let otherDeletions = changes.deletions.count - deleted.count
                return "database changes: zones modified \(modified), zones deleted \(deleted); other zones: \(others) modified, \(otherDeletions) deleted"
            case .willFetchRecordZoneChanges(let will) where ProbeText.isProbeZone(will.zoneID):
                return "zone fetch begins: \(will.zoneID.zoneName)"
            case .didFetchRecordZoneChanges(let did) where ProbeText.isProbeZone(did.zoneID):
                return "zone fetch ends: \(did.zoneID.zoneName)\(did.error.map { ", error \(ProbeText.error($0))" } ?? "")"
            case .fetchedRecordZoneChanges(let changes):
                let records = changes.modifications.map(\.record).filter { ProbeText.isProbeZone($0.recordID.zoneID) }
                let deletions = changes.deletions.filter { ProbeText.isProbeZone($0.recordID.zoneID) }
                guard !records.isEmpty || !deletions.isEmpty else { return nil }
                return "records: \(records.map { "[\(ProbeText.record($0))]" }.joined(separator: " ")), record deletions \(deletions.map { ProbeText.short($0.recordID) })"
            default:
                return nil
            }
        }
        return lines.isEmpty ? "nothing" : lines.joined(separator: " | ")
    }

    func savedRecords(_ events: [ProbeDevice.Logged]) -> [CKRecord] {
        events.flatMap { logged -> [CKRecord] in
            if case .sentRecordZoneChanges(let sent) = logged.event { sent.savedRecords } else { [] }
        }
    }

    func failedSaves(_ events: [ProbeDevice.Logged]) -> [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave] {
        events.flatMap { logged -> [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave] in
            if case .sentRecordZoneChanges(let sent) = logged.event { sent.failedRecordSaves } else { [] }
        }
    }

    func fetchedRecords(_ events: [ProbeDevice.Logged]) -> [CKRecord] {
        events.flatMap { logged -> [CKRecord] in
            if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.modifications.map(\.record) } else { [] }
        }
    }

    func fetchedDeletions(_ events: [ProbeDevice.Logged]) -> [CKDatabase.RecordZoneChange.Deletion] {
        events.flatMap { logged -> [CKDatabase.RecordZoneChange.Deletion] in
            if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.deletions } else { [] }
        }
    }

    func zoneDeletions(_ events: [ProbeDevice.Logged]) -> [CKDatabase.DatabaseChange.Deletion] {
        events.flatMap { logged -> [CKDatabase.DatabaseChange.Deletion] in
            if case .fetchedDatabaseChanges(let changes) = logged.event { changes.deletions } else { [] }
        }
    }

    func zoneModifications(_ events: [ProbeDevice.Logged]) -> [CKRecordZone.ID] {
        events.flatMap { logged -> [CKRecordZone.ID] in
            if case .fetchedDatabaseChanges(let changes) = logged.event { changes.modifications.map(\.zoneID) } else { [] }
        }
    }

    /// The errors of zone fetches in `events`.
    func zoneFetchErrors(_ events: [ProbeDevice.Logged]) -> [String] {
        events.compactMap { logged -> String? in
            if case .didFetchRecordZoneChanges(let did) = logged.event, let error = did.error {
                "\(ProbeText.zone(did.zoneID)): \(ProbeText.error(error))"
            } else { nil }
        }
    }

    func accountChanges(_ events: [ProbeDevice.Logged]) -> [CKSyncEngine.Event.AccountChange] {
        events.compactMap { logged in
            if case .accountChange(let change) = logged.event { change } else { nil }
        }
    }
}
#endif
