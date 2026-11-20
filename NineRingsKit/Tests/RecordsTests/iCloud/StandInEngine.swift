import Foundation
@testable import Records

/// What a stand-in engine tells its delegate, and asks of it: what the app's `CKSyncEngine` delegate receives.
@MainActor
protocol StandInEngineDelegate: AnyObject {
    /// The account the device is signed in to; nil with none.
    var currentAccount: String? { get }
    func engine(_ engine: StandInEngine, handle event: StandInEngine.Event)
    /// The batch for the pending changes `pending`, as `nextRecordZoneChangeBatch` builds it.
    func engine(_ engine: StandInEngine, batchFor pending: [PendingChange]) -> Batch
}

/// A stand-in for `CKSyncEngine` on one device, against ``StandInICloud``.
///
/// It keeps a database token, a token for each zone, and a list of pending changes without duplicates (source 3), in a
/// state it hands to its delegate as data to save; a new engine starts from the state saved last, or from nothing. It
/// watches the account: an engine with no state reports a sign-in, and a change of account, also one made while the app
/// was not running, is reported as one event and resets the state, pending changes included (source 4). It sends
/// zones' saves before records (probe 7), asks the delegate for each batch as it sends, and keeps a change only after
/// an error it retries (source 56). A fetch reports its beginning and end with whether the app asked for it, the
/// database's zones in one report, and each zone's changes and end (source 55, probe A). Its events come one at a time
/// (source 11). The delegate fetches and sends by asking, and the test also lets it fetch and send by itself, as
/// automatic syncing does.
///
/// Where Apple documents nothing, it can do either, by ``Choices``.
@MainActor
final class StandInEngine {
    /// What the engine keeps between launches.
    struct State: Codable, Equatable {
        var account: String?
        var databaseToken: Int?
        var zoneTokens: [String: StandInICloud.ZoneToken] = [:]
        var pendingZoneSaves: [String] = []
        var pending: [Pending] = []
    }

    /// A pending change of a record.
    enum Pending: Codable, Hashable {
        case save(RecordID)
        case delete(RecordID)

        var change: PendingChange {
            switch self {
            case .save(let id): .save(id)
            case .delete(let id): .delete(id)
            }
        }

        var id: RecordID {
            switch self {
            case .save(let id), .delete(let id): id
            }
        }
    }

    /// What the engine reports.
    enum Event {
        case stateUpdate(Data)
        case accountChange(AccountChange)
        case willFetch(manual: Bool)
        case databaseChanged(DatabaseChanges)
        case fetched(FetchedChanges)
        case zoneFetchEnded(String, ZoneFetchError?)
        case didFetch(manual: Bool)
        case sentZones(SentZones)
        case sent(SentChanges)
    }

    /// What the engine does where Apple's documentation is silent.
    struct Choices: Sendable, CustomStringConvertible {
        /// Whether an engine that starts from nothing reports a sign-in (open point 14; the probe saw it always).
        var reportsSignInFromNothing = true
        /// Whether a report of the account comes before the first report of the database's zones, rather than after the
        /// first fetch's changes (open point 14).
        var accountReportComesFirst = true
        /// Whether the engine sends a save whose answer was lost again by itself (source 51).
        var resendsLostAnswers = true
        /// How often the answer to a record's save is lost, from 0 to 1.
        var answerLost = 0.0
        /// How often a save whose answer is lost has landed.
        var landsWhenAnswerLost = 0.5
        /// How often the answer to a send comes only after a later fetch (source 17).
        var answerComesLate = 0.0
        /// How often the answer to a zone's save is lost; it landed or not, by ``landsWhenAnswerLost``.
        var zoneAnswerLost = 0.0
        /// Whether the engine keeps a zone's save whose answer was lost, and sends it again.
        var keepsZoneSaveAfterLostAnswer = true
        /// How often a request of the app's to fetch finds a fetch under way and gets none of its own (source 55).
        var requestFindsFetchUnderWay = 0.0
        /// How often a zone's fetch fails with an error that is not one of the three that say a zone is gone.
        var zoneFetchFails = 0.0
        /// How often the engine hands over its state after the delegate changed its pending changes.
        var stateUpdateAfterChange = 0.5
        /// The most record changes in one send, and records in one fetched batch.
        var batchSize = 4

        var description: String {
            "sign-in from nothing: \(reportsSignInFromNothing), account first: \(accountReportComesFirst), "
                + "resends lost answers: \(resendsLostAnswers), answer lost: \(answerLost), answer late: \(answerComesLate), "
                + "zone answer lost: \(zoneAnswerLost), request finds fetch: \(requestFindsFetchUnderWay), "
                + "zone fetch fails: \(zoneFetchFails), batch: \(batchSize)"
        }
    }

    /// What a fetch the app asked for came to, for the delegate to tell the rules.
    struct RequestOutcome {
        var error: FetchRequestError?
    }

    let cloud: StandInICloud
    let device: String
    var choices: Choices
    private var random: SeededRandom
    private(set) var state: State
    /// A change of account the engine has noticed and not yet reported.
    private var unreportedAccountChange: AccountChange?
    /// The answers that come only after a later fetch.
    private(set) var lateAnswers: [SentChanges] = []
    var isOnline = true
    /// How many record changes this engine has sent, answered or not.
    private(set) var changesSent = 0
    weak var delegate: (any StandInEngineDelegate)?
    /// Whether the engine was made without a saved state.
    let startedFromNothing: Bool

    init(cloud: StandInICloud, device: String, savedState: Data?, account: String?, choices: Choices, seed: UInt64) {
        self.cloud = cloud
        self.device = device
        self.choices = choices
        random = SeededRandom(seed: seed)
        let saved = savedState.flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        startedFromNothing = saved == nil
        state = saved ?? State()
        if startedFromNothing {
            state.account = account
            if let account, choices.reportsSignInFromNothing { unreportedAccountChange = .signIn(account) }
        } else if state.account != account {
            noticeChange(to: account)
        }
    }

    // MARK: The account

    /// The device's account may have changed while the app runs: if it did, the engine resets its state and reports the
    /// change at once.
    func accountMayHaveChanged() {
        noticeChange(to: delegate?.currentAccount)
        reportAccountChange()
    }

    /// The engine notices that the account is `account`: if it is another, it resets its state and keeps the change to
    /// report. Several changes come as one, from the last known account to the current one.
    private func noticeChange(to account: String?) {
        let known = state.account
        guard account != known else { return }
        let change: AccountChange? = switch (known, account) {
        case (nil, let now?): .signIn(now)
        case (let before?, nil): .signOut(before)
        case (let before?, let now?): .switchAccounts(from: before, to: now)
        case (nil, nil): nil
        }
        state = State(account: account)
        lateAnswers = []
        if let change {
            if case .signOut = change, case .signIn? = unreportedAccountChange {
                unreportedAccountChange = nil
            } else {
                unreportedAccountChange = change
            }
        }
    }

    private func reportAccountChange() {
        guard let change = unreportedAccountChange else { return }
        unreportedAccountChange = nil
        delegate?.engine(self, handle: .accountChange(change))
        handOverState()
    }

    /// The account the engine reaches iCloud for now, or nil while it is dormant or offline. It notices a change of
    /// account first, and reports it at once when `reportsAtOnce`, or when it has no account any more.
    private func activeAccount(reportsAtOnce: Bool) -> String? {
        noticeChange(to: delegate?.currentAccount)
        if reportsAtOnce || state.account == nil { reportAccountChange() }
        guard isOnline, let account = state.account else { return nil }
        return account
    }

    // MARK: Pending changes

    /// Applies what the rules asked, as ``EngineRequests`` describes. Fetching and sending are left to the caller.
    func apply(_ requests: EngineRequests) {
        guard !requests.isEmpty else { return }
        if requests.withdrawsEverything {
            state.pending = []
            state.pendingZoneSaves = []
        } else if let zone = requests.withdrawsEverythingOutside {
            state.pending.removeAll { $0.id.zone != zone }
            state.pendingZoneSaves.removeAll { $0 != zone }
        }
        state.pending.removeAll { change in
            switch change {
            case .save(let id): requests.withdrawnSaves.contains(id)
            case .delete(let id): requests.withdrawnDeletions.contains(id)
            }
        }
        if let zone = requests.savesZone, !state.pendingZoneSaves.contains(zone) { state.pendingZoneSaves.append(zone) }
        for id in requests.saves { add(.save(id)) }
        for id in requests.deletions { add(.delete(id)) }
        if random.chance(choices.stateUpdateAfterChange) { handOverState() }
    }

    /// Of a save and a deletion queued for one record, the engine keeps the later (probe 14).
    private func add(_ change: Pending) {
        state.pending.removeAll { $0.id == change.id && $0 != change }
        if !state.pending.contains(change) { state.pending.append(change) }
    }

    /// Whether anything waits to be sent.
    var hasPendingChanges: Bool { !state.pendingZoneSaves.isEmpty || !state.pending.isEmpty }

    // MARK: Sending

    /// Sends the zones' pending saves and one batch of record changes. With `crashesBeforeTheAnswer`, the changes reach
    /// iCloud and the process ends before any answer is handled: the caller relaunches. Returns whether anything went
    /// to iCloud.
    @discardableResult
    func send(crashesBeforeTheAnswer: Bool = false) -> Bool {
        guard let account = activeAccount(reportsAtOnce: true) else { return false }
        var sentSomething = false
        if !state.pendingZoneSaves.isEmpty {
            var answer = SentZones()
            var kept: [String] = []
            for zone in state.pendingZoneSaves {
                sentSomething = true
                if random.chance(choices.zoneAnswerLost) {
                    if random.chance(choices.landsWhenAnswerLost) { cloud.saveZone(zone, account: account, device: device) }
                    if choices.keepsZoneSaveAfterLostAnswer { kept.append(zone) }
                    continue
                }
                switch cloud.saveZone(zone, account: account, device: device) {
                case .saved: answer.saved.append(zone)
                case .storageFull: answer.failed.append(FailedZoneSave(zone: zone, storageFull: true))
                }
            }
            state.pendingZoneSaves = kept
            if crashesBeforeTheAnswer { return true }
            if !answer.saved.isEmpty || !answer.failed.isEmpty { delegate?.engine(self, handle: .sentZones(answer)) }
        }
        let offered = Array(state.pending.prefix(choices.batchSize))
        guard !offered.isEmpty else {
            handOverState()
            return sentSomething
        }
        let batch = delegate?.engine(self, batchFor: offered.map(\.change)) ?? Batch()
        let withdrawn = Set(batch.withdrawn)
        state.pending.removeAll { withdrawn.contains($0.change) }
        var answer = SentChanges()
        var kept: [Pending] = []
        for record in batch.records {
            changesSent += 1
            sentSomething = true
            let change = Pending.save(record.id)
            if random.chance(choices.answerLost) {
                if random.chance(choices.landsWhenAnswerLost) { _ = cloud.save(record, account: account, device: device) }
                answer.failedSaves.append(FailedSave(type: record.type, id: record.id, reason: .answerLost))
                if choices.resendsLostAnswers { kept.append(change) }
                continue
            }
            switch cloud.save(record, account: account, device: device) {
            case .saved(let saved): answer.saved.append(saved)
            case .refused(let server): answer.failedSaves.append(FailedSave(type: record.type, id: record.id, reason: .refused(serverRecord: server)))
            case .unknownItem: answer.failedSaves.append(FailedSave(type: record.type, id: record.id, reason: .unknownItem))
            case .zoneGone(let gone): answer.failedSaves.append(FailedSave(type: record.type, id: record.id, reason: .zoneGone(gone)))
            case .storageFull: answer.failedSaves.append(FailedSave(type: record.type, id: record.id, reason: .storageFull))
            }
        }
        for id in batch.deletions {
            changesSent += 1
            sentSomething = true
            switch cloud.delete(id, account: account, device: device) {
            case .deleted: answer.deleted.append(id)
            case .zoneGone(let gone): answer.failedDeletions.append(FailedDeletion(id: id, reason: .zoneGone(gone)))
            }
        }
        if crashesBeforeTheAnswer { return true }
        // A change leaves the list once sent, unless it is to be sent again.
        let sent = Set(batch.records.map { Pending.save($0.id) } + batch.deletions.map { Pending.delete($0) })
        state.pending.removeAll { sent.contains($0) && !kept.contains($0) }
        if random.chance(choices.answerComesLate) {
            lateAnswers.append(answer)
        } else {
            deliver(answer)
        }
        handOverState()
        return sentSomething
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
            for record in answer.saved { cloud.markAnswered(RecordID(zone: record.zone ?? "", name: record.name), account: account, device: device) }
        }
        delegate?.engine(self, handle: .sent(answer))
    }

    // MARK: Fetching

    /// Fetches: by the app's request when `manual`, or by itself. Returns what the app's request came to: with no
    /// account or no network it fails as a whole, and it may find a fetch under way and begin none of its own.
    @discardableResult
    func fetch(manual: Bool) -> RequestOutcome {
        guard let account = activeAccount(reportsAtOnce: choices.accountReportComesFirst) else { return RequestOutcome(error: .whole) }
        if manual, random.chance(choices.requestFindsFetchUnderWay) { return RequestOutcome(error: nil) }
        delegate?.engine(self, handle: .willFetch(manual: manual))
        var failedZones: [String: ZoneFetchError] = [:]
        let report = cloud.databaseChanges(account: account, since: state.databaseToken, device: device)
        state.databaseToken = report.token
        if !report.existing.isEmpty || !report.deleted.isEmpty {
            delegate?.engine(self, handle: .databaseChanged(DatabaseChanges(existing: report.existing, deleted: report.deleted)))
        }
        for deletion in report.deleted { state.zoneTokens[deletion.zone] = nil }
        if !choices.accountReportComesFirst { reportAccountChange() }
        for zone in report.existing {
            guard state.account == account else { break }
            if random.chance(choices.zoneFetchFails) {
                failedZones[zone] = .other
                delegate?.engine(self, handle: .zoneFetchEnded(zone, .other))
                continue
            }
            switch cloud.changes(zone: zone, account: account, since: state.zoneTokens[zone], device: device) {
            case .failure(let error):
                state.zoneTokens[zone] = nil
                failedZones[zone] = .zoneGone(error.gone)
                delegate?.engine(self, handle: .zoneFetchEnded(zone, .zoneGone(error.gone)))
            case .success(let changes):
                var records = changes.records[...]
                var deletions = changes.deletions[...]
                while !records.isEmpty || !deletions.isEmpty {
                    let batch = FetchedChanges(records: Array(records.prefix(choices.batchSize)), deletions: Array(deletions.prefix(choices.batchSize)))
                    records = records.dropFirst(choices.batchSize)
                    deletions = deletions.dropFirst(choices.batchSize)
                    delegate?.engine(self, handle: .fetched(batch))
                }
                state.zoneTokens[zone] = changes.token
                delegate?.engine(self, handle: .zoneFetchEnded(zone, nil))
            }
        }
        handOverState()
        deliverLateAnswers()
        delegate?.engine(self, handle: .didFetch(manual: manual))
        return RequestOutcome(error: failedZones.isEmpty ? nil : .zones(failedZones))
    }

    // MARK: State

    /// The state, as the engine hands it over.
    var serializedState: Data { (try? JSONEncoder().encode(state)) ?? Data() }

    private func handOverState() {
        delegate?.engine(self, handle: .stateUpdate(serializedState))
    }
}
