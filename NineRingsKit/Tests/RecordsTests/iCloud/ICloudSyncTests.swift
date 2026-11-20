import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// The rules over the device's store, through the surface the app's delegate calls: what one event changes reaches the
/// store in one save, the store alone says what iCloud has not yet received, and each event's answer is what
/// docs/icloud.md sections 6 to 10 say.
@MainActor
@Suite struct ICloudSyncTests {
    private let container: ModelContainer
    private let sync: ICloudSync

    init() throws {
        container = try RecordStore.deviceContainer(in: .memory)
        sync = ICloudSync(store: RecordStore(container: container), madeOn: .iPhone, appVersion: "2.0")
    }

    /// The untouched toy every toy of a test starts from: each fresh toy has a play of its own.
    private let fresh = PlayState().snapshot

    private func toy(_ rings: [Int]) -> ToySnapshot {
        var state = PlayState(fresh)!
        for ring in rings {
            state.tap(ring)
            while state.toy.isPlaying { state.advance(by: 10) }
        }
        return state.snapshot
    }

    private func play(finishedAt seconds: TimeInterval = 1_000) -> PlayRecord {
        let finished = Date(timeIntervalSinceReferenceDate: seconds)
        return PlayRecord(
            playID: UUID(), startedAt: finished.addingTimeInterval(-600), finishedAt: finished, startRings: .allOn,
            endRings: .allOff, moves: 341, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 512
        )
    }

    /// A finished play's record as iCloud hands it over.
    private func record(of play: PlayRecord, format: Int = 1, tag: String = "1") throws -> CloudRecord {
        CloudRecord(
            type: CloudRecord.finishedPlayType, name: play.playID.uuidString, changeTag: tag, systemFields: Data(tag.utf8),
            format: format, payload: try FinishedPlayPayload(play: play, madeOn: "iPad", appVersion: "2.0").encoded()
        )
    }

    /// The toy's record as iCloud hands it over.
    private func toyRecord(_ snapshot: ToySnapshot, tag: String, stamps: [UUID] = [UUID()]) throws -> CloudRecord {
        let payload = ToyPayload(toy: snapshot, changedAt: .distantPast, changedOn: "iPad", appVersion: "2.0", stamps: stamps)
        return CloudRecord(
            type: CloudRecord.toyType, name: CloudRecord.toyName, changeTag: tag, systemFields: Data(tag.utf8), format: 1,
            payload: try payload.encoded()
        )
    }

    /// The rules signed in to `account`, joined, and past the join's fetch.
    private func joined(_ account: String = "person") throws {
        _ = try sync.start(engineStartsFromNothing: true)
        _ = try sync.accountChanged(.signIn(account))
        _ = try sync.fetchFinished()
    }

    private func state(of play: PlayRecord) throws -> PlaySyncState? {
        try sync.store.entries([play.playID])[play.playID]?.sync
    }

    // MARK: Launch

    /// With a saved state, launch queues again whatever the store marks, and asks the engine to fetch.
    @Test func aLaunchWithASavedStateQueuesTheMarks() throws {
        try joined()
        let unsent = play()
        _ = try sync.record(unsent)
        try sync.keep(toy([1]))
        let relaunched = ICloudSync(store: RecordStore(container: container), madeOn: .iPhone, appVersion: "2.0")
        let result = try relaunched.start(engineStartsFromNothing: false)
        #expect(Set(result.engine.saves) == [unsent.playID.uuidString, CloudRecord.toyName])
        #expect(result.engine.fetches)
    }

    /// From nothing, nothing is queued and no record is built until the account is named; then the device joins.
    @Test func aLaunchFromNothingWaitsForTheAccount() throws {
        try sync.keep(toy([1]))
        let unsent = play()
        _ = try sync.record(unsent)
        let start = try sync.start(engineStartsFromNothing: true)
        #expect(start.engine.saves.isEmpty && start.engine.deletions.isEmpty && !start.engine.savesZone)
        #expect(start.engine.fetches)
        #expect(sync.waitsForAccount)
        #expect(try sync.recordsToSend(named: [CloudRecord.toyName, unsent.playID.uuidString]).isEmpty)
        #expect(try sync.queueToy().isEmpty)
        #expect(try sync.notYetReceived().isEmpty)
        let signIn = try sync.accountChanged(.signIn("person"))
        #expect(!sync.waitsForAccount)
        #expect(signIn.engine.savesZone && signIn.engine.fetches)
        #expect(signIn.engine.saves.isEmpty, "what is marked is queued once the join's fetch is done")
        let fetched = try sync.fetchFinished()
        #expect(Set(fetched.engine.saves) == [unsent.playID.uuidString, CloudRecord.toyName])
        #expect(try sync.account() == "person")
    }

    // MARK: The store's side (principle 1)

    /// The list of what iCloud has not yet received is read from the store alone: plays unsent or sent, deletions of
    /// cleared plays, and the toy when it is marked and no toy is held.
    @Test func whatIsNotYetReceivedComesFromTheStoreAlone() throws {
        try joined()
        let plays = (0..<4).map { play(finishedAt: 1_000 + Double($0)) }
        for each in plays { _ = try sync.record(each) }
        _ = try sync.recordsToSend(named: [plays[1].playID.uuidString, plays[2].playID.uuidString, plays[3].playID.uuidString])
        _ = try sync.sent(SentChanges(saved: [try record(of: plays[2]), try record(of: plays[3])]))
        _ = try sync.clearHistoryOf(plays[3])
        try sync.keep(toy([1]))
        let relaunched = ICloudSync(store: RecordStore(container: container), madeOn: .iPhone, appVersion: "2.0")
        let marked = try relaunched.notYetReceived()
        #expect(Set(marked.saves) == [plays[0].playID.uuidString, plays[1].playID.uuidString, CloudRecord.toyName])
        #expect(marked.deletions == [plays[3].playID.uuidString])
        #expect(try state(of: plays[0]) == .unsent)
        #expect(try state(of: plays[1]) == .sent)
        #expect(try state(of: plays[2]) == .inICloud)
    }

    /// While a toy is held, the device sends no toy: none is queued and none is built, at launch as at any other time.
    @Test func noToyIsQueuedOrBuiltWhileOneIsHeld() throws {
        try joined()
        try sync.keep(toy([1]))
        _ = try sync.fetched(FetchedChanges(records: [try toyRecord(toy([2]), tag: "5")]))
        #expect(try sync.heldToy()?.kind == .offered)
        #expect(try sync.queueToy().isEmpty)
        #expect(try !sync.notYetReceived().saves.contains(CloudRecord.toyName))
        #expect(try sync.recordsToSend(named: [CloudRecord.toyName]).isEmpty)
        let relaunched = ICloudSync(store: RecordStore(container: container), madeOn: .iPhone, appVersion: "2.0")
        #expect(try relaunched.start(engineStartsFromNothing: false).engine.saves.isEmpty)
        #expect(try relaunched.heldToy()?.kind == .offered, "the offer shows again")
    }

    /// The record is built when the engine asks for it: the stamp and the state sent are saved before it is handed over,
    /// and the mark, the held toy and the entry's state are looked at again then.
    @Test func whatARecordNeedsIsSavedBeforeItIsHandedOver() throws {
        try joined()
        try sync.keep(toy([1]))
        let finished = play()
        _ = try sync.record(finished)
        let records = try sync.recordsToSend(named: [CloudRecord.toyName, finished.playID.uuidString])
        #expect(records.count == 2)
        let toyRecord = try #require(records[CloudRecord.toyName])
        let stamp = try #require(ToyPayload(format: 1, payload: toyRecord.payload)?.stamp)
        let saved = try sync.store.toySide()
        #expect(saved.lastSend?.stamp == stamp && saved.ownStamps == [stamp])
        #expect(try state(of: finished) == .sent)
        let again = try sync.recordsToSend(named: [CloudRecord.toyName])
        let retried = try #require(again[CloudRecord.toyName])
        #expect(ToyPayload(format: 1, payload: retried.payload)?.stamp == stamp, "a retry keeps the stamp")
        _ = try sync.sent(SentChanges(saved: [try record(of: finished)]))
        #expect(try sync.recordsToSend(named: [finished.playID.uuidString]).isEmpty, "a play iCloud has is not sent again")
    }

    /// What one event changes reaches the store in one save: when that save fails, nothing of the event is kept.
    @Test func aFailedSaveLeavesTheStoreAsItWas() throws {
        let folder = URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let kept = toy([1])
        do {
            let writable = ICloudSync(store: RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder))), madeOn: .Mac, appVersion: "2.0")
            try writable.keep(kept)
            _ = try writable.start(engineStartsFromNothing: true)
            _ = try writable.accountChanged(.signIn("person"))
        }
        let readOnly = ModelConfiguration(
            "Device", schema: RecordStore.deviceSchema, url: folder.appending(path: "Device.store"), allowsSave: false, cloudKitDatabase: .none
        )
        let store = RecordStore(container: try ModelContainer(for: RecordStore.deviceSchema, configurations: readOnly))
        let failing = ICloudSync(store: store, madeOn: .Mac, appVersion: "2.0")
        let before = try store.toySide()
        #expect(throws: (any Error).self) { try failing.keep(toy([1, 3])) }
        #expect(try store.toySide() == before)
        #expect(throws: (any Error).self) { try failing.record(play()) }
        #expect(try store.allEntries().isEmpty)
        #expect(!store.container.mainContext.hasChanges)
    }

    /// Writing fetched changes fails: the engine's state is no longer saved in this run, so that the next launch fetches
    /// the same changes again.
    @Test func aFailedWriteOfFetchedChangesStopsSavingTheEngineState() throws {
        let folder = URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let writable = ICloudSync(store: RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder))), madeOn: .Mac, appVersion: "2.0")
            try writable.engineStateUpdated(Data("first".utf8))
        }
        let readOnly = ModelConfiguration(
            "Device", schema: RecordStore.deviceSchema, url: folder.appending(path: "Device.store"), allowsSave: false, cloudKitDatabase: .none
        )
        let failing = ICloudSync(store: RecordStore(container: try ModelContainer(for: RecordStore.deviceSchema, configurations: readOnly)), madeOn: .Mac, appVersion: "2.0")
        #expect(failing.savesEngineState)
        #expect(throws: (any Error).self) { try failing.fetched(FetchedChanges(records: [try record(of: play())])) }
        #expect(!failing.savesEngineState)
        try failing.engineStateUpdated(Data("second".utf8))
        #expect(try failing.engineState() == Data("first".utf8))
    }

    /// Applying a change twice gives the same result as applying it once.
    @Test func applyingFetchedChangesTwiceIsApplyingThemOnce() throws {
        try joined()
        let arriving = play()
        let changes = FetchedChanges(records: [try record(of: arriving), try toyRecord(toy([1, 3]), tag: "4")])
        _ = try sync.fetched(changes)
        let once = (try sync.history(), try sync.store.toySide())
        _ = try sync.fetched(changes)
        #expect(try sync.history() == once.0)
        #expect(try sync.store.toySide() == once.1)
    }

    // MARK: The history

    /// The history on screen is every entry that is not cleared; a play in a format this version does not know is
    /// counted and not shown, and kept as it is.
    @Test func theHistoryShowsWhatIsNotClearedAndCountsWhatItCannotRead() throws {
        try joined()
        let shown = play(finishedAt: 2_000)
        let newer = play(finishedAt: 3_000)
        let cleared = play(finishedAt: 1_000)
        _ = try sync.fetched(FetchedChanges(records: [try record(of: shown), try record(of: newer, format: 2), try record(of: cleared)]))
        _ = try sync.clearHistoryOf(cleared)
        let history = try sync.history()
        #expect(history.plays == [shown])
        #expect(history.unreadable == 1)
        let kept = try #require(try sync.store.entries([newer.playID])[newer.playID])
        let arrived = try record(of: newer, format: 2)
        #expect(kept.format == 2 && kept.payload == arrived.payload, "kept as it is")
    }

    /// A play is recorded once on a device: finishing under an id the store already holds changes nothing.
    @Test func aPlayIsRecordedOnce() throws {
        try joined()
        let finished = play()
        _ = try sync.fetched(FetchedChanges(records: [try record(of: finished)]))
        #expect(try sync.record(finished).saves.isEmpty)
        #expect(try state(of: finished) == .inICloud)
        let mine = play()
        let requests = try sync.record(mine)
        #expect(requests.saves == [mine.playID.uuidString])
        #expect(try sync.record(mine).isEmpty)
    }

    /// Clearing: unsent entries go at once, every other becomes cleared, and its deletion is queued; an answered deletion
    /// removes it for good.
    @Test func clearingQueuesTheDeletionsOfWhatICloudMayHave() throws {
        try joined()
        let unsent = play(finishedAt: 1)
        let sent = play(finishedAt: 2)
        let inICloud = play(finishedAt: 3)
        _ = try sync.record(unsent)
        _ = try sync.record(sent)
        _ = try sync.recordsToSend(named: [sent.playID.uuidString])
        _ = try sync.fetched(FetchedChanges(records: [try record(of: inICloud)]))
        let requests = try sync.clearHistory()
        #expect(Set(requests.deletions) == [sent.playID.uuidString, inICloud.playID.uuidString])
        #expect(try state(of: unsent) == nil)
        #expect(try sync.history().plays.isEmpty)
        _ = try sync.sent(SentChanges(deleted: [inICloud.playID.uuidString], failedDeletions: [FailedDeletion(name: sent.playID.uuidString, reason: .alreadyGone)]))
        #expect(try sync.store.allEntries().isEmpty)
    }

    // MARK: The account (section 8)

    @Test func aSignInWithNoAccountNotedKeepsWhatWasMadeWithoutICloud() throws {
        let finished = play()
        _ = try sync.record(finished)
        try joined()
        #expect(try sync.account() == "person")
        #expect(try state(of: finished) == .unsent)
    }

    @Test func aSignInToTheSameAccountJoins() throws {
        try joined()
        let arrived = play()
        _ = try sync.fetched(FetchedChanges(records: [try record(of: arrived)]))
        _ = try sync.accountChanged(.signOut("person"))
        let result = try sync.accountChanged(.signIn("person"))
        #expect(result.replacedToy == nil)
        #expect(try state(of: arrived) == .sent, "a play in iCloud goes back to sent")
        #expect(result.engine.savesZone && result.engine.fetches)
    }

    @Test(arguments: [true, false])
    func anotherAccountRemovesTheDataAndJoinsWithNothing(asSwitch: Bool) throws {
        try joined()
        try sync.keep(toy([1, 3]))
        _ = try sync.record(play())
        try sync.engineStateUpdated(Data("state".utf8))
        let change: AccountChange = asSwitch ? .switchAccounts(from: "person", to: "other") : .signIn("other")
        let result = try sync.accountChanged(change)
        let fresh = try #require(result.replacedToy)
        #expect(fresh.isUntouched)
        #expect(try sync.toy() == fresh)
        #expect(try sync.store.allEntries().isEmpty)
        #expect(try sync.account() == "other")
        #expect(try sync.engineState() == nil)
        #expect(try sync.store.toySide() == ToySide(toy: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: "iPhone")))
        #expect(result.engine.savesZone)
    }

    @Test func aSignOutKeepsEverythingAndNotesAnEmptyAccount() throws {
        try sync.keep(toy([1]))
        let finished = play()
        _ = try sync.record(finished)
        let result = try sync.accountChanged(.signOut("person"))
        #expect(result.engine.isEmpty && result.replacedToy == nil)
        #expect(try sync.account() == "person")
        #expect(try state(of: finished) == .unsent)
        #expect(try sync.toy() == toy([1]))
    }

    // MARK: A deleted zone (section 9, as the text stands; it is to change)

    @Test func aPurgeRemovesTheDataAndKeepsTheAccountAndState() throws {
        try joined()
        try sync.keep(toy([1, 3]))
        _ = try sync.record(play())
        try sync.engineStateUpdated(Data("state".utf8))
        let result = try sync.zoneDeleted(.purged)
        #expect(result.replacedToy?.isUntouched == true)
        #expect(result.engine.dropsEveryPendingChange)
        #expect(try sync.store.allEntries().isEmpty)
        #expect(try sync.account() == "person")
        #expect(try sync.engineState() == Data("state".utf8))
        #expect(try sync.notYetReceived().isEmpty, "nothing is sent again")
    }

    @Test func aResetOfEncryptedDataKeepsEverythingAndOffersItAgain() throws {
        try joined()
        try sync.keep(toy([1, 3]))
        _ = try sync.fetched(FetchedChanges(records: [try record(of: play())]))
        let result = try sync.zoneDeleted(.encryptedDataReset)
        #expect(result.replacedToy == nil)
        #expect(result.engine.savesZone && result.engine.fetches)
        let marked = try sync.fetchFinished().engine
        #expect(marked.saves.count == 2, "the play and the toy go to iCloud again")
    }

    // MARK: When something fails (section 10)

    /// A save finds the zone missing: the device fetches first. If the fetch reports no deletion, the zone and the save
    /// are queued again; if it does, the deletion decides.
    @Test(arguments: [false, true])
    func aMissingZoneIsFetchedBeforeItIsMade(deletionReported: Bool) throws {
        try joined()
        let finished = play()
        _ = try sync.record(finished)
        let failed = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, name: finished.playID.uuidString, reason: .zoneMissing(encryptedDataReset: false))]))
        #expect(failed.engine.fetches && !failed.engine.savesZone && failed.engine.saves.isEmpty)
        if deletionReported { _ = try sync.zoneDeleted(.purged) }
        let after = try sync.fetchFinished()
        #expect(after.engine.savesZone == !deletionReported)
        #expect(after.engine.saves.contains(finished.playID.uuidString) == !deletionReported)
    }

    @Test func aMissingZoneMarkedAsAResetIsAReset() throws {
        try joined()
        try sync.keep(toy([1]))
        let result = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.toyType, name: CloudRecord.toyName, reason: .zoneMissing(encryptedDataReset: true))]))
        #expect(result.engine.savesZone)
        let side = try sync.store.toySide()
        #expect(side.base == nil && side.isChanged)
    }

    @Test func aFullStorageIsSaidUntilASaveIsAccepted() throws {
        try joined()
        let finished = play()
        _ = try sync.record(finished)
        _ = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, name: finished.playID.uuidString, reason: .storageFull)]))
        #expect(sync.storageIsFull)
        #expect(try state(of: finished) == .unsent, "the data stays, marked as not received")
        #expect(try sync.notYetReceived().saves == [finished.playID.uuidString], "and goes again as the app comes to the front")
        _ = try sync.sent(SentChanges(saved: [try record(of: finished)]))
        #expect(!sync.storageIsFull)
    }

    @Test func aRecordICloudNoLongerKnowsIsSentAsNew() throws {
        try joined()
        try sync.keep(toy([1]))
        _ = try sync.fetched(FetchedChanges(records: [try toyRecord(toy([1]), tag: "3")]))
        try sync.keep(toy([1, 3]))
        let result = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.toyType, name: CloudRecord.toyName, reason: .unknownItem)]))
        #expect(result.engine.saves == [CloudRecord.toyName])
        #expect(try sync.recordsToSend(named: [CloudRecord.toyName])[CloudRecord.toyName]?.systemFields == nil)
    }

    @Test func aToyRefusedWithoutTheRecordIsFetched() throws {
        try joined()
        try sync.keep(toy([1]))
        let result = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.toyType, name: CloudRecord.toyName, reason: .refused(serverRecord: nil))]))
        #expect(result.engine.fetches)
        #expect(try sync.store.toySide().isChanged)
    }

    @Test(arguments: [SaveFailure.answerLost, .temporary, .other])
    func otherFailuresKeepTheMarks(failure: SaveFailure) throws {
        try joined()
        let finished = play()
        _ = try sync.record(finished)
        _ = try sync.recordsToSend(named: [finished.playID.uuidString])
        let result = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, name: finished.playID.uuidString, reason: failure)]))
        #expect(result.engine.isEmpty)
        #expect(try state(of: finished) == .sent)
    }

    // MARK: The toy, through the surface

    @Test func keepThisOneSendsAtOnce() throws {
        try joined()
        try sync.keep(toy([1]))
        _ = try sync.fetched(FetchedChanges(records: [try toyRecord(toy([2]), tag: "5")]))
        let requests = try sync.keepThisOne()
        #expect(requests.saves == [CloudRecord.toyName] && requests.sendsNow)
        #expect(try sync.heldToy() == nil)
    }

    @Test func theToyKeptTheEarlierWayCarriesOver() throws {
        let left = toy([1, 3])
        try sync.store.keep(left, installation: "an earlier installation", appVersion: "1.4")
        #expect(try sync.toy() == left)
        try sync.keep(left)
        #expect(try sync.store.toySide().isChanged, "what was made without these rules goes to iCloud")
    }
}

extension ICloudSync {
    /// Clears one play, as if the history held only it, for tests that need one cleared entry among others.
    func clearHistoryOf(_ play: PlayRecord) throws -> EngineRequests {
        let entry = try #require(try store.entries([play.playID])[play.playID])
        let step = PlayRules.step(.clearing, from: entry.sync)
        if case .state(let state) = step.change { entry.sync = state }
        if case .remove = step.change { store.delete(entry) }
        try store.saveSync()
        var requests = EngineRequests()
        if step.queuesDeletion { requests.deletions = [entry.recordName] }
        return requests
    }
}
