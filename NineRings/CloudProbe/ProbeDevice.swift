#if DEBUG
import CloudKit
import Foundation

/// One device of the probe: a `CKSyncEngine` on the private database, with its own state and its own small store in
/// memory. The probe decides what it sends: for each record it queues, it says which system fields go with it (none, or
/// those of a record seen before) and which values. The device hands the engine exactly that, never anything it decides
/// by itself, and it never queues anything again after a refusal: the probe does, when a question asks for it.
///
/// It also never calls the engine's fetch or send from inside a callback, which Apple forbids: only the probe's
/// questions call ``send(_:)`` and ``fetch(_:)``.
actor ProbeDevice: CKSyncEngineDelegate {
    /// One event, as the engine delivered it, and when.
    struct Logged: Sendable {
        let at: ContinuousClock.Instant
        let event: CKSyncEngine.Event
    }

    /// A record to hand to the engine when it sends.
    struct Outgoing: Sendable, Codable {
        var recordType: CKRecord.RecordType
        /// The system fields to build the record on, archived; nil for a record built without any.
        var systemFields: Data?
        var format: Int
        var payload: String
    }

    nonisolated let name: String
    nonisolated let zone: CKRecordZone
    private let database: CKDatabase
    private let report: ProbeReport
    private var engine: CKSyncEngine?
    /// The engine's state as it last handed it over.
    private(set) var serialization: CKSyncEngine.State.Serialization?
    private var outgoing: [CKRecord.ID: Outgoing] = [:]
    /// The last record handed to the engine for each id.
    private(set) var handed: [CKRecord.ID: CKRecord] = [:]
    /// What the device knows of each record: the last one the server returned, after a save or in a fetch.
    private(set) var known: [CKRecord.ID: CKRecord] = [:]
    /// Every event, in order.
    private(set) var log: [Logged] = []
    /// Where the device keeps its state and its records at every state update, as the app would; nil for none.
    private var keptIn: URL?
    /// Whether the device ends the process when a save's confirmation arrives, before it stores anything of it.
    private var endsOnConfirmation = false
    /// Whether the device's fetches read its own zone only, as they do unless a question says otherwise.
    private var fetchesOwnZoneOnly = true

    init(name: String, database: CKDatabase, zone: CKRecordZone, report: ProbeReport) {
        self.name = name
        self.database = database
        self.zone = zone
        self.report = report
    }

    /// Makes the engine, from `state` or from nothing.
    func start(state: CKSyncEngine.State.Serialization?, automaticallySync: Bool) async {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self)
        configuration.automaticallySync = automaticallySync
        serialization = state
        engine = CKSyncEngine(configuration)
        await report.say(name, "engine made, \(state == nil ? "with no state" : "from a saved state"), automatic syncing \(automaticallySync ? "on" : "off")")
    }

    /// Lets the engine go, after cancelling whatever it is doing.
    func stop() async {
        await engine?.cancelOperations()
        engine = nil
        await report.say(name, "engine let go")
    }

    /// Takes on `other`'s store: what it knows and what it would send, as a device restored from its backup would.
    func copyStore(from other: ProbeDevice) async {
        known = await other.known
        outgoing = await other.outgoingRecords
        await report.say(name, "store copied from \(other.name): \(known.count) records known, \(outgoing.count) to send")
    }

    var outgoingRecords: [CKRecord.ID: Outgoing] { outgoing }

    /// From now on, keeps the engine's state and the device's records in `file` at every state update.
    func keep(in file: URL) {
        keptIn = file
    }

    /// From now on, ends the process as soon as a save's confirmation arrives: an app that crashed, or was ended,
    /// between the send and storing its answer.
    func endOnConfirmation() {
        endsOnConfirmation = true
    }

    /// What the device keeps: the engine's state and its records, as ``keep(in:)`` writes them.
    struct Kept: Codable {
        var zoneName: String
        var state: CKSyncEngine.State.Serialization?
        /// The records the device knows, archived whole, by record name.
        var known: [String: Data]
        var outgoing: [String: Outgoing]
    }

    /// Takes on the records of `kept`.
    func restore(_ kept: Kept) async {
        known = kept.known.reduce(into: [:]) { known, entry in
            let record = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: entry.value)
            known[CKRecord.ID(recordName: entry.key, zoneID: zone.zoneID)] = record
        }
        outgoing = kept.outgoing.reduce(into: [:]) { $0[CKRecord.ID(recordName: $1.key, zoneID: zone.zoneID)] = $1.value }
        await report.say(name, "store restored: \(known.count) records known, \(outgoing.count) to send")
    }

    private func writeKept() {
        guard let keptIn else { return }
        let kept = Kept(
            zoneName: zone.zoneID.zoneName,
            state: serialization,
            known: known.reduce(into: [:]) { known, entry in
                known[entry.key.recordName] = try? NSKeyedArchiver.archivedData(withRootObject: entry.value, requiringSecureCoding: true)
            },
            outgoing: outgoing.reduce(into: [:]) { $0[$1.key.recordName] = $1.value }
        )
        try? JSONEncoder().encode(kept).write(to: keptIn, options: .atomic)
    }

    // MARK: What the probe asks of it

    /// Queues the save of the device's zone, or of `other`.
    func queueZoneSave(_ other: CKRecordZone? = nil) async {
        let zone = other ?? zone
        engine?.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        await report.say(name, "queues the save of zone \(zone.zoneID.zoneName)")
    }

    /// From now on, fetches every zone of the database, not only the device's own.
    func fetchEveryZone() {
        fetchesOwnZoneOnly = false
    }

    /// The zones the engine knows to have changes it has not fetched.
    var zonesWithUnfetchedChanges: [CKRecordZone.ID] { engine?.state.zoneIDsWithUnfetchedServerChanges ?? [] }

    func queueZoneDelete() async {
        engine?.state.add(pendingDatabaseChanges: [.deleteZone(zone.zoneID)])
        await report.say(name, "queues the zone's deletion")
    }

    /// Queues a save of `id`, built on the system fields of `base` (none when nil), with `payload` as its payload.
    func queueSave(_ id: CKRecord.ID, type: CKRecord.RecordType, base: CKRecord?, payload: String, format: Int = 1) async {
        outgoing[id] = Outgoing(recordType: type, systemFields: base.map(ProbeText.systemFields(of:)), format: format, payload: payload)
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        let fields = base.map { "the system fields of tag \($0.recordChangeTag ?? "none")" } ?? "no system fields"
        await report.say(name, "queues a save of \(type) \(ProbeText.short(id)) with \(fields), payload \"\(payload)\"")
    }

    func queueDelete(_ id: CKRecord.ID) async {
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
        await report.say(name, "queues a deletion of \(ProbeText.short(id))")
    }

    /// Asks the engine to send everything pending, and says what is pending before and after.
    func send(_ note: String = "") async {
        guard let engine else { return }
        await report.say(name, "sendChanges\(note.isEmpty ? "" : " (\(note))"): pending \(pendingText)")
        let outcome = await Self.run(on: engine) { try await engine.sendChanges() }
        await report.say(name, "sendChanges returned \(outcome); pending \(pendingText)")
    }

    /// Asks the engine to fetch, in the probe's zone only, so that no other zone of the database is read.
    func fetch(_ note: String = "") async {
        guard let engine else { return }
        await report.say(name, "fetchChanges\(note.isEmpty ? "" : " (\(note))"), \(fetchesOwnZoneOnly ? "its own zone only" : "every zone")")
        let options = CKSyncEngine.FetchChangesOptions(scope: fetchesOwnZoneOnly ? .zoneIDs([zone.zoneID]) : .all)
        let outcome = await Self.run(on: engine) { try await engine.fetchChanges(options) }
        await report.say(name, "fetchChanges returned \(outcome)")
    }

    var pendingRecordChanges: [CKSyncEngine.PendingRecordZoneChange] { engine?.state.pendingRecordZoneChanges ?? [] }

    var pendingText: String {
        guard let engine else { return "(no engine)" }
        return "records \(ProbeText.pending(engine.state.pendingRecordZoneChanges)), zones \(ProbeText.pending(engine.state.pendingDatabaseChanges))"
    }

    /// The number of events so far: a mark to read the later ones from.
    var mark: Int { log.count }

    func events(since mark: Int) -> [Logged] {
        Array(log[min(mark, log.count)...])
    }

    /// Runs `work` against `engine`, and cancels the engine's operations if it has not finished within 90 seconds.
    private static func run(on engine: CKSyncEngine, _ work: @escaping @Sendable () async throws -> Void) async -> String {
        let task = Task { try await work() }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(90))
            await engine.cancelOperations()
        }
        defer { watchdog.cancel() }
        switch await task.result {
        case .success: return "normally"
        case .failure(let error): return "with an error: \(ProbeText.error(error))"
        }
    }

    // MARK: The engine's delegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let now = ContinuousClock.now
        log.append(Logged(at: now, event: event))
        await report.say(name, ProbeText.event(event), at: now)
        if endsOnConfirmation, case .sentRecordZoneChanges(let sent) = event, !sent.savedRecords.isEmpty {
            await report.say(name, "ENDS THE PROCESS NOW, before storing this answer or any later state")
            exit(0)
        }
        switch event {
        case .stateUpdate(let update):
            serialization = update.stateSerialization
            writeKept()
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { known[record.recordID] = record }
            for id in sent.deletedRecordIDs { known[id] = nil }
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications { known[modification.record.recordID] = modification.record }
            for deletion in changes.deletions { known[deletion.recordID] = nil }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        await report.say(name, "nextRecordZoneChangeBatch (reason \(context.reason)): pending \(ProbeText.pending(pending)), zones \(ProbeText.pending(syncEngine.state.pendingDatabaseChanges))")
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await self.recordToSend(id)
        }
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        // Scheduled fetches too read the probe's zone only, unless the device fetches every zone.
        var options = context.options
        if fetchesOwnZoneOnly { options.scope = .zoneIDs([zone.zoneID]) }
        return options
    }

    /// The record to send for `id`, as the probe queued it; nil when it queued none.
    private func recordToSend(_ id: CKRecord.ID) -> CKRecord? {
        guard let plan = outgoing[id] else { return nil }
        let record = plan.systemFields.flatMap(ProbeText.record(systemFields:)) ?? CKRecord(recordType: plan.recordType, recordID: id)
        record.encryptedValues["format"] = plan.format
        record.encryptedValues["payload"] = Data(plan.payload.utf8)
        handed[id] = record
        return record
    }
}
#endif
