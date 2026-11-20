#if DEBUG
import CloudKit
import Foundation
import os

/// The probe's report: one line for each thing done or seen, with the seconds since the probe began, written to
/// standard output at once and to the log. Whoever launches the app decides where standard output goes; the app writes
/// no file. Every line passes through ``ProbeText/redacted(_:)`` first, so that no account's record name reaches it.
actor ProbeReport {
    private let start = ContinuousClock.now
    private static let log = Logger(subsystem: "com.chentianren.PlayNineRings", category: "CloudProbe")

    /// The time of `instant`, in seconds since the probe began.
    nonisolated func seconds(at instant: ContinuousClock.Instant) -> Double {
        let elapsed = instant - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// A line said by `who`: a device's name, or the probe's own `--`.
    func say(_ who: String, _ text: String, at instant: ContinuousClock.Instant = .now) {
        let number = ProbeText.decimal(seconds(at: instant), places: 3)
        let time = String(repeating: " ", count: max(0, 9 - number.count)) + number
        let name = who.padding(toLength: 3, withPad: " ", startingAt: 0)
        write("[\(time)] \(name) \(text)")
    }

    /// The heading of a question, with the time of day.
    func heading(_ text: String) {
        write("")
        write("=== \(text)  (\(Date.now.formatted(.iso8601)))")
    }

    /// What a question found, in one line, marked so that it can be picked out of the timeline.
    func result(_ question: String, _ text: String) {
        write("RESULT \(question): \(text)")
    }

    private func write(_ text: String) {
        let line = ProbeText.redacted(text)
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
        Self.log.notice("\(line, privacy: .public)")
    }
}

/// How the probe describes what CloudKit hands it. It reads only the fields the probe wrote and the system fields that
/// matter to the design, and it names an account's user record only by its kind, never by its value.
nonisolated enum ProbeText {
    /// A record: its type and name, change tag, dates, and the values of `format` and `payload` as read back through
    /// `encryptedValues`.
    static func record(_ record: CKRecord?) -> String {
        guard let record else { return "nil" }
        let format: Int? = record.encryptedValues["format"]
        let payload: Data? = record.encryptedValues["payload"]
        var parts = ["\(record.recordType) \(short(record.recordID))"]
        parts.append("tag=\(record.recordChangeTag ?? "none")")
        parts.append("created=\(time(record.creationDate))")
        parts.append("modified=\(time(record.modificationDate))")
        parts.append("format=\(format.map(String.init) ?? "none")")
        parts.append("payload=\(payload.map { "\"\(String(decoding: $0, as: UTF8.self))\"" } ?? "none")")
        return parts.joined(separator: " ")
    }

    /// What a record carries beyond its values: which keys it has, plain and encrypted, and who created and last
    /// changed it.
    static func recordDetails(_ record: CKRecord) -> String {
        var parts = ["plainKeys=\(record.allKeys().sorted())", "encryptedKeys=\(record.encryptedValues.allKeys().sorted())"]
        parts.append("changedKeys=\(record.changedKeys().sorted())")
        parts.append("creator=\(record.creatorUserRecordID.map { user($0) } ?? "nil")")
        parts.append("lastModifiedBy=\(record.lastModifiedUserRecordID.map { user($0) } ?? "nil")")
        parts.append("systemFieldsBytes=\(systemFields(of: record).count)")
        return parts.joined(separator: " ")
    }

    /// A record's name, short: a finished play's UUID by its first eight characters, and its zone by name when the zone
    /// is not the one the reader expects.
    static func short(_ id: CKRecord.ID) -> String {
        let name = id.recordName.count == 36 ? "\(id.recordName.prefix(8))…" : id.recordName
        return "\(name)@\(zone(id.zoneID))"
    }

    static func zone(_ id: CKRecordZone.ID) -> String {
        id.ownerName == CKCurrentUserDefaultName ? id.zoneName : "\(id.zoneName)(owner \(user(id.ownerName)))"
    }

    /// The kind of a user record id, not its value: CloudKit's stand-in for the current user, or an account's own name.
    static func user(_ id: CKRecord.ID) -> String {
        user(id.recordName)
    }

    static func user(_ name: String) -> String {
        if name == CKCurrentUserDefaultName { return "\"\(CKCurrentUserDefaultName)\" (CKCurrentUserDefaultName)" }
        return "an account's own record name (\(name.count) characters, starting with \"\(name.prefix(1))\")"
    }

    /// An error: its code, its message and the server's, and the three records CloudKit may attach.
    static func error(_ error: (any Error)?) -> String {
        guard let error else { return "nil" }
        guard let ck = error as? CKError else { return "\(type(of: error)): \(error.localizedDescription)" }
        var parts = ["CKError.\(name(ck.code)) (\(ck.code.rawValue)) \"\(ck.localizedDescription)\""]
        if let server = ck.userInfo["ServerErrorDescription"] as? String { parts.append("server=\"\(server)\"") }
        if let underlying = ck.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain) \(underlying.code) \"\(underlying.localizedDescription)\"")
        }
        parts.append("serverRecord=[\(record(ck.serverRecord))]")
        parts.append("clientRecord=[\(record(ck.clientRecord))]")
        parts.append("ancestorRecord=[\(record(ck.ancestorRecord))]")
        if let seconds = ck.retryAfterSeconds { parts.append("retryAfter=\(seconds)s") }
        if let partial = ck.partialErrorsByItemID {
            parts.append("partial=[\(partial.map { "\($0.key): \(self.error($0.value))" }.joined(separator: "; "))]")
        }
        parts.append("userInfoKeys=\(ck.userInfo.keys.sorted())")
        return parts.joined(separator: " ")
    }

    /// An event of the engine, with everything in it that the probe asks about.
    static func event(_ event: CKSyncEngine.Event) -> String {
        switch event {
        case .stateUpdate:
            return "stateUpdate"
        case .accountChange(let change):
            switch change.changeType {
            case .signIn(let current):
                return "accountChange signIn currentUser=\(user(current))"
            case .signOut(let previous):
                return "accountChange signOut previousUser=\(user(previous))"
            case .switchAccounts(let previous, let current):
                return "accountChange switchAccounts previousUser=\(user(previous)) currentUser=\(user(current))"
            @unknown default:
                return "accountChange (a kind this build does not know)"
            }
        case .fetchedDatabaseChanges(let changes):
            let modified = changes.modifications.map { zone($0.zoneID) }
            let deleted = changes.deletions.map { "\(zone($0.zoneID)) reason=\(reason($0.reason))" }
            return "fetchedDatabaseChanges modifiedZones=\(modified) deletedZones=\(deleted)"
        case .fetchedRecordZoneChanges(let changes):
            // Records of zones that are not the probe's are counted, never shown.
            let own = changes.modifications.filter { isProbeZone($0.record.recordID.zoneID) }
            let ownDeleted = changes.deletions.filter { isProbeZone($0.recordID.zoneID) }
            let modified = own.map { "[\(record($0.record))]" }
            let deleted = ownDeleted.map { "\($0.recordType) \(short($0.recordID))" }
            var text = "fetchedRecordZoneChanges modifications=\(modified.joined(separator: " ")) deletions=\(deleted)"
            let others = changes.modifications.count - own.count + changes.deletions.count - ownDeleted.count
            if others > 0 { text += " (and \(others) changes in zones that are not the probe's)" }
            return text
        case .sentDatabaseChanges(let sent):
            var parts = ["sentDatabaseChanges savedZones=\(sent.savedZones.map { zone($0.zoneID) })"]
            parts.append("failedZoneSaves=\(sent.failedZoneSaves.map { "\(zone($0.zone.zoneID)): \(error($0.error))" })")
            parts.append("deletedZones=\(sent.deletedZoneIDs.map { zone($0) })")
            parts.append("failedZoneDeletes=\(sent.failedZoneDeletes.map { "\(zone($0.key)): \(error($0.value))" })")
            return parts.joined(separator: " ")
        case .sentRecordZoneChanges(let sent):
            var parts = ["sentRecordZoneChanges saved=\(sent.savedRecords.map { "[\(record($0))]" }.joined(separator: " "))"]
            parts.append("failedSaves=\(sent.failedRecordSaves.map { "{record=[\(record($0.record))] error=\(error($0.error))}" }.joined(separator: " "))")
            parts.append("deleted=\(sent.deletedRecordIDs.map { short($0) })")
            parts.append("failedDeletes=\(sent.failedRecordDeletes.map { "{\(short($0.key)): \(error($0.value))}" }.joined(separator: " "))")
            return parts.joined(separator: " ")
        case .willFetchChanges(let will):
            return "willFetchChanges reason=\(will.context.reason)"
        case .willFetchRecordZoneChanges(let will):
            return "willFetchRecordZoneChanges zone=\(zone(will.zoneID))"
        case .didFetchRecordZoneChanges(let did):
            return "didFetchRecordZoneChanges zone=\(zone(did.zoneID)) error=\(error(did.error))"
        case .didFetchChanges(let did):
            return "didFetchChanges reason=\(did.context.reason)"
        case .willSendChanges(let will):
            return "willSendChanges reason=\(will.context.reason)"
        case .didSendChanges(let did):
            return "didSendChanges reason=\(did.context.reason)"
        @unknown default:
            return "an event this build does not know"
        }
    }

    /// Whether `id` names a zone of this probe.
    static func isProbeZone(_ id: CKRecordZone.ID) -> Bool {
        id.zoneName.hasPrefix(ProbeRun.zonePrefix)
    }

    /// A fetch's scope.
    static func scope(_ scope: CKSyncEngine.FetchChangesOptions.Scope) -> String {
        switch scope {
        case .all: "scope all zones"
        case .allExcluding(let ids): "scope all zones but \(ids.map { zone($0) })"
        case .zoneIDs(let ids): "scope \(ids.map { zone($0) })"
        @unknown default: "scope \(scope)"
        }
    }

    static func pending(_ changes: [CKSyncEngine.PendingRecordZoneChange]) -> String {
        "[" + changes.map { change in
            switch change {
            case .saveRecord(let id): "save \(short(id))"
            case .deleteRecord(let id): "delete \(short(id))"
            @unknown default: "\(change)"
            }
        }.joined(separator: ", ") + "]"
    }

    static func pending(_ changes: [CKSyncEngine.PendingDatabaseChange]) -> String {
        "[" + changes.map { change in
            switch change {
            case .saveZone(let zone): "save zone \(self.zone(zone.zoneID))"
            case .deleteZone(let id): "delete zone \(zone(id))"
            @unknown default: "\(change)"
            }
        }.joined(separator: ", ") + "]"
    }

    static func reason(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) -> String {
        switch reason {
        case .deleted: "deleted"
        case .purged: "purged"
        case .encryptedDataReset: "encryptedDataReset"
        @unknown default: "\(reason)"
        }
    }

    /// The system fields of `record`, archived as Apple's `encodeSystemFields(with:)` asks.
    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// A record holding only the system fields in `data`.
    static func record(systemFields data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    /// `value` with `places` decimals, written the same way in every locale.
    static func decimal(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    /// The time of day of `date`, in UTC, to the millisecond.
    static func clock(_ date: Date) -> String {
        date.formatted(.iso8601.time(includingFractionalSeconds: true))
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "none" }
        return date.formatted(.iso8601.time(includingFractionalSeconds: true))
    }

    /// `text` with every account's user record name taken out. CloudKit names an account's user record with an
    /// underscore and 32 hexadecimal digits; the report keeps none of them, wherever they turn up.
    static func redacted(_ text: String) -> String {
        text.replacing(/_[0-9a-fA-F]{32}/, with: "<an account's record name>")
    }

    static func name(_ code: CKError.Code) -> String {
        switch code {
        case .internalError: "internalError"
        case .partialFailure: "partialFailure"
        case .networkUnavailable: "networkUnavailable"
        case .networkFailure: "networkFailure"
        case .badContainer: "badContainer"
        case .serviceUnavailable: "serviceUnavailable"
        case .requestRateLimited: "requestRateLimited"
        case .missingEntitlement: "missingEntitlement"
        case .notAuthenticated: "notAuthenticated"
        case .permissionFailure: "permissionFailure"
        case .unknownItem: "unknownItem"
        case .invalidArguments: "invalidArguments"
        case .resultsTruncated: "resultsTruncated"
        case .serverRecordChanged: "serverRecordChanged"
        case .serverRejectedRequest: "serverRejectedRequest"
        case .assetFileNotFound: "assetFileNotFound"
        case .assetFileModified: "assetFileModified"
        case .incompatibleVersion: "incompatibleVersion"
        case .constraintViolation: "constraintViolation"
        case .operationCancelled: "operationCancelled"
        case .changeTokenExpired: "changeTokenExpired"
        case .batchRequestFailed: "batchRequestFailed"
        case .zoneBusy: "zoneBusy"
        case .badDatabase: "badDatabase"
        case .quotaExceeded: "quotaExceeded"
        case .zoneNotFound: "zoneNotFound"
        case .limitExceeded: "limitExceeded"
        case .userDeletedZone: "userDeletedZone"
        case .serverResponseLost: "serverResponseLost"
        case .accountTemporarilyUnavailable: "accountTemporarilyUnavailable"
        default: "code\(code.rawValue)"
        }
    }
}
#endif
