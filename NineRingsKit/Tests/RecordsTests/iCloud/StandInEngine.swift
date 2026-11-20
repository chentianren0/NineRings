import Foundation
@testable import Records

/// What a stand-in engine tells its delegate, and asks of it: what the app's `CKSyncEngine` delegate receives.
@MainActor
protocol StandInEngineDelegate: AnyObject {
    /// The account the device is signed in to; nil with none.
    var currentAccount: String? { get }
    func engine(_ engine: StandInEngine, handle event: StandInEngine.Event)
    /// The records for the pending saves `names`, as `nextRecordZoneChangeBatch` builds them.
    func engine(_ engine: StandInEngine, recordsToSend names: [String]) -> [String: RecordToSend]
}

/// A stand-in for `CKSyncEngine` on one device, against ``StandInICloud``.
///
/// It keeps the change tokens and a list of pending changes without duplicates [3], in a state it hands to its delegate
/// as data to save; a new engine starts from the state saved last, or from nothing. It reports a change of account and
/// then resets its state, pending changes included [4]. Saving zones before records [10], it asks the delegate for each
/// record as it sends, and drops a change that failed for good. Its events come one at a time [11]. The delegate fetches
/// and sends by asking, as a test does with automatic syncing off [21].
///
/// Where Apple documents nothing, it can do either, by ``Choices``: whether a start from nothing reports a sign-in, how
/// often the answer to a save is lost (and whether the save landed), whether the engine sends such a save again by
/// itself, and how often the answer to a send comes only after a later fetch.
@MainActor
final class StandInEngine {
    /// What the engine keeps between launches.
    struct State: Codable, Equatable {
        var account: String?
        var databaseToken: Int?
        var zoneToken: StandInICloud.ZoneToken?
        var savesZone = false
        var pending: [Pending] = []
    }

    /// A pending change of a record.
    enum Pending: Codable, Hashable {
        case save(String)
        case delete(String)
    }

    /// What the engine reports.
    enum Event {
        case stateUpdate(Data)
        case accountChange(AccountChange)
        case zoneDeleted(ZoneDeletionReason)
        case fetched(FetchedChanges)
        case sent(SentChanges)
        case fetchFinished
    }

    /// What the engine does where Apple's documentation is silent.
    struct Choices: Sendable, CustomStringConvertible {
        /// Whether an engine that starts from nothing reports a sign-in (open point 14).
        var reportsSignInFromNothing = true
        /// Whether the engine sends a save whose answer was lost again by itself [51].
        var resendsLostAnswers = true
        /// How often the answer to a save is lost, from 0 to 1.
        var answerLost = 0.0
        /// How often a save whose answer is lost has landed.
        var landsWhenAnswerLost = 0.5
        /// How often the answer to a send comes only after a later fetch [17].
        var answerComesLate = 0.0
        /// How often the engine hands over its state after the delegate changed its pending changes.
        var stateUpdateAfterChange = 0.5
        /// The most record changes in one send, and records in one fetched batch.
        var batchSize = 4

        var description: String {
            "sign-in from nothing: \(reportsSignInFromNothing), resends lost answers: \(resendsLostAnswers), answer lost: \(answerLost), "
                + "answer late: \(answerComesLate), batch: \(batchSize)"
        }
    }

    let cloud: StandInICloud
    let zone: String
    let device: String
    var choices: Choices
    private var random: SeededRandom
    private(set) var state: State
    /// The answers that come only after a later fetch.
    private(set) var lateAnswers: [SentChanges] = []
    var isOnline = true
    /// How many record changes this engine has sent, answered or not.
    private(set) var changesSent = 0
    weak var delegate: (any StandInEngineDelegate)?
    /// Whether the engine was made without a saved state.
    let startedFromNothing: Bool

    init(cloud: StandInICloud, zone: String, device: String, savedState: Data?, choices: Choices, seed: UInt64) {
        self.cloud = cloud
        self.zone = zone
        self.device = device
        self.choices = choices
        random = SeededRandom(seed: seed)
        let saved = savedState.flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        state = saved ?? State()
        startedFromNothing = saved == nil
    }

    /// The engine begins to watch the account: it reports what changed since its saved state. Returns whether it reported
    /// a sign-in.
    @discardableResult
    func start() -> Bool {
        let current = delegate?.currentAccount
        if startedFromNothing {
            state.account = current
            defer { handOverState() }
            if let current, choices.reportsSignInFromNothing {
                delegate?.engine(self, handle: .accountChange(.signIn(current)))
                return true
            }
            return false
        }
        return accountMayHaveChanged()
    }

    /// The device's account may have changed: if it did, the engine resets its state and reports the change. Returns
    /// whether it reported a sign-in or a switch.
    @discardableResult
    func accountMayHaveChanged() -> Bool {
        let current = delegate?.currentAccount
        guard current != state.account else { return false }
        let change: AccountChange
        switch (state.account, current) {
        case (nil, let now?): change = .signIn(now)
        case (let before?, nil): change = .signOut(before)
        case (let before?, let now?): change = .switchAccounts(from: before, to: now)
        case (nil, nil): return false
        }
        state = State(account: current)
        lateAnswers = []
        delegate?.engine(self, handle: .accountChange(change))
        handOverState()
        if case .signOut = change { return false }
        return true
    }

    // MARK: Pending changes

    /// Applies what the rules asked, as ``EngineRequests`` describes. Fetching and sending are left to the caller.
    func apply(_ requests: EngineRequests) {
        guard !requests.isEmpty else { return }
        if requests.dropsEveryPendingChange {
            state.pending = []
            state.savesZone = false
        }
        state.pending.removeAll { change in
            switch change {
            case .save(let name): requests.withdrawnSaves.contains(name)
            case .delete(let name): requests.withdrawnDeletions.contains(name)
            }
        }
        if requests.savesZone { state.savesZone = true }
        for name in requests.saves { add(.save(name)) }
        for name in requests.deletions { add(.delete(name)) }
        if random.chance(choices.stateUpdateAfterChange) { handOverState() }
    }

    private func add(_ change: Pending) {
        if !state.pending.contains(change) { state.pending.append(change) }
    }

    /// Whether anything waits to be sent.
    var hasPendingChanges: Bool { state.savesZone || !state.pending.isEmpty }

    // MARK: Sending

    /// Sends the zone, when it is pending, and one batch of record changes. Returns whether anything went to iCloud.
    @discardableResult
    func send() -> Bool {
        guard isOnline, let account = state.account, delegate?.currentAccount == account else { return false }
        if state.savesZone {
            cloud.saveZone(zone, account: account)
            state.savesZone = false
        }
        let batch = Array(state.pending.prefix(choices.batchSize))
        guard !batch.isEmpty else {
            handOverState()
            return false
        }
        let names = batch.compactMap { if case .save(let name) = $0 { name } else { nil } }
        let records = names.isEmpty ? [:] : (delegate?.engine(self, recordsToSend: names) ?? [:])
        var answer = SentChanges()
        var kept: [Pending] = []
        for change in batch {
            if case .save(let name) = change, records[name] == nil { continue }
            changesSent += 1
            switch change {
            case .save(let name):
                guard let record = records[name] else { continue }
                if random.chance(choices.answerLost) {
                    if random.chance(choices.landsWhenAnswerLost) {
                        _ = cloud.save(record, zone: zone, account: account, device: device)
                    }
                    answer.failedSaves.append(FailedSave(type: record.type, name: name, reason: .answerLost))
                    if choices.resendsLostAnswers { kept.append(change) }
                    continue
                }
                switch cloud.save(record, zone: zone, account: account, device: device) {
                case .saved(let saved): answer.saved.append(saved)
                case .refused(let server): answer.failedSaves.append(FailedSave(type: record.type, name: name, reason: .refused(serverRecord: server)))
                case .unknownItem: answer.failedSaves.append(FailedSave(type: record.type, name: name, reason: .unknownItem))
                case .zoneMissing(let reset): answer.failedSaves.append(FailedSave(type: record.type, name: name, reason: .zoneMissing(encryptedDataReset: reset)))
                case .storageFull: answer.failedSaves.append(FailedSave(type: record.type, name: name, reason: .storageFull))
                }
            case .delete(let name):
                switch cloud.delete(name, zone: zone, account: account, device: device) {
                case .deleted: answer.deleted.append(name)
                case .alreadyGone: answer.failedDeletions.append(FailedDeletion(name: name, reason: .alreadyGone))
                case .zoneMissing(let reset): answer.failedDeletions.append(FailedDeletion(name: name, reason: .zoneMissing(encryptedDataReset: reset)))
                }
            }
        }
        // A change leaves the list once sent, unless it is to be sent again; one the delegate gave no record for, too.
        state.pending.removeAll { batch.contains($0) && !kept.contains($0) }
        if random.chance(choices.answerComesLate) {
            lateAnswers.append(answer)
        } else {
            deliver(answer)
        }
        handOverState()
        return true
    }

    /// Delivers the answers held back.
    func deliverLateAnswers() {
        let answers = lateAnswers
        lateAnswers = []
        for answer in answers { deliver(answer) }
    }

    /// Hands an answer to the delegate; from then on the engine knows the saves in it were its own.
    private func deliver(_ answer: SentChanges) {
        if let account = state.account {
            for record in answer.saved { cloud.markAnswered(record.name, zone: zone, account: account, device: device) }
        }
        delegate?.engine(self, handle: .sent(answer))
    }

    // MARK: Fetching

    /// Fetches the database's changes, then the zone's, and delivers them; then the answers held back, which thus come
    /// after this fetch. Returns whether it brought anything.
    @discardableResult
    func fetch() -> Bool {
        guard isOnline, let account = state.account, delegate?.currentAccount == account else { return false }
        var brought = false
        let database = cloud.zoneDeletions(account: account, since: state.databaseToken)
        state.databaseToken = database.token
        for deletion in database.deletions where deletion.zone == zone {
            state.zoneToken = nil
            brought = true
            delegate?.engine(self, handle: .zoneDeleted(deletion.reason))
        }
        if let changes = cloud.changes(zone: zone, account: account, since: state.zoneToken, device: device) {
            var records = changes.records[...]
            var deletions = changes.deletions[...]
            while !records.isEmpty || !deletions.isEmpty {
                let batch = FetchedChanges(records: Array(records.prefix(choices.batchSize)), deletions: Array(deletions.prefix(choices.batchSize)))
                records = records.dropFirst(choices.batchSize)
                deletions = deletions.dropFirst(choices.batchSize)
                brought = true
                delegate?.engine(self, handle: .fetched(batch))
            }
            state.zoneToken = changes.token
        }
        handOverState()
        deliverLateAnswers()
        delegate?.engine(self, handle: .fetchFinished)
        return brought
    }

    // MARK: State

    /// The state, as the engine hands it over.
    var serializedState: Data { (try? JSONEncoder().encode(state)) ?? Data() }

    private func handOverState() {
        delegate?.engine(self, handle: .stateUpdate(serializedState))
    }
}
