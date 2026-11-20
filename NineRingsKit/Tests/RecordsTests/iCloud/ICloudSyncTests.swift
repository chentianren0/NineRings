import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// The rules over the device's store, through the surface the app and its delegate call, one call at a time: the gate
/// and its conditions, the fetch that counts, the zone, the account, the moments of section 11, failures, batches, and
/// the store's side.
@MainActor
@Suite struct ICloudSyncTests {
    private let container: ModelContainer
    private var sync: ICloudSync

    init() throws {
        container = try RecordStore.deviceContainer(in: .memory)
        sync = ICloudSync(store: RecordStore(container: container), madeOn: .iPhone, appVersion: "2.0")
    }

    // MARK: Toys, plays, zones

    private let zone1 = ZoneName(number: 1, id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
    private let zone2 = ZoneName(number: 2, id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)
    private let zone2b = ZoneName(number: 2, id: UUID(uuidString: "F0000000-0000-4000-8000-000000000002")!)

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

    /// A finished play's record as iCloud hands it over, in `zone`.
    private func record(of play: PlayRecord, in zone: ZoneName? = nil, format: Int = 1, tag: String = "1") throws -> CloudRecord {
        CloudRecord(
            type: CloudRecord.finishedPlayType, zone: (zone ?? zone1).name, name: play.playID.uuidString, changeTag: tag,
            systemFields: Data(tag.utf8), format: format,
            payload: try FinishedPlayPayload(play: play, madeOn: "iPad", appVersion: "2.0").encoded()
        )
    }

    /// The toy's record as iCloud hands it over, in `zone`.
    private func toyRecord(_ snapshot: ToySnapshot, in zone: ZoneName? = nil, tag: String, stamps: [UUID] = [UUID()]) throws -> CloudRecord {
        let payload = ToyPayload(toy: snapshot, changedAt: .distantPast, changedOn: "iPad", appVersion: "2.0", stamps: stamps)
        return CloudRecord(
            type: CloudRecord.toyType, zone: (zone ?? zone1).name, name: CloudRecord.toyName, changeTag: tag,
            systemFields: Data(tag.utf8), format: 1, payload: try payload.encoded()
        )
    }

    private func playID(_ play: PlayRecord, in zone: ZoneName? = nil) -> RecordID {
        RecordID(zone: (zone ?? zone1).name, name: play.playID.uuidString)
    }

    // MARK: The delegate's part, by hand

    /// One request of the app's to fetch, answered by a fetch the engine began for it, which brings `report` and
    /// `changes`, ends the zones in `zoneErrors` with those errors, and returns `error`.
    @discardableResult
    private func fetch(
        _ report: DatabaseChanges? = nil, _ changes: FetchedChanges? = nil, zoneErrors: [String: ZoneFetchError] = [:],
        error: FetchRequestError? = nil, pendingZoneSaves: Set<String> = []
    ) throws -> SyncResult {
        var result = SyncResult()
        let request = sync.fetchWillBeRequested()
        sync.fetchBegan(manual: true)
        if let report { result.add(try sync.databaseChanged(report)) }
        if let changes { result.add(try sync.fetched(changes)) }
        for (zone, zoneError) in zoneErrors { result.add(try sync.zoneFetchEnded(zone: zone, error: zoneError)) }
        result.add(try sync.fetchEnded(manual: true))
        result.add(try sync.fetchRequestReturned(request, error: error, pendingZoneSaves: pendingZoneSaves))
        return result
    }

    /// Launched, with the account confirmed and joined to `zone`, past the join's fetch: the gate is open.
    @discardableResult
    private func joined(_ zone: ZoneName? = nil, account: String = "person") throws -> SyncResult {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account(account))
        try fetch(DatabaseChanges(existing: [(zone ?? zone1).name]))
        return try fetch()
    }

    /// The rules launched again over the same store, as at the next launch.
    private mutating func relaunch(fromNothing: Bool = false) throws -> SyncResult {
        sync = ICloudSync(store: RecordStore(container: container), madeOn: .iPhone, appVersion: "2.0")
        return try sync.launched(engineStartsFromNothing: fromNothing)
    }

    private var notes: SyncNotes { get throws { try sync.store.syncNotes() } }
    private var zoneNote: ZoneNote? { get throws { sync.zoneNote(try notes) } }

    private func state(of play: PlayRecord) throws -> PlaySyncState? {
        try sync.store.plays([play.playID])[play.playID]?.sync
    }

    // MARK: Launch and the gate (sections 8 and 11)

    @Test func aLaunchAsksForTheAccountAndAFetch() throws {
        let result = try sync.launched(engineStartsFromNothing: true)
        #expect(result.engine.asksForAccount && result.engine.fetches)
        #expect(result.engine.saves.isEmpty && result.engine.savesZone == nil)
    }

    /// Nothing is queued until the account is confirmed in this run and a fetch that counts has finished; then the gate
    /// queues everything the store marks, so that a crash between a change and its sending loses nothing.
    @Test mutating func nothingIsQueuedBeforeTheAccountAndTheFetch() throws {
        try joined()
        let finished = play()
        _ = try relaunch()
        #expect(try sync.finished(finished).engine.saves.isEmpty, "the account is not confirmed in this run")
        _ = try sync.accountAnswered(.account("person"))
        #expect(try sync.toyChanged().engine.saves.isEmpty, "no fetch has counted in this run")
        let opened = try fetch()
        #expect(opened.engine.saves == [playID(finished)], "the fetch counted, and a condition lifted")
    }

    /// Condition 4: the toy goes only while it is marked and no toy is held.
    @Test func noToyIsQueuedWhileOneIsHeld() throws {
        try joined()
        try sync.keep(toy([1]))
        #expect(try sync.toyChanged().engine.saves == [.toy(in: zone1.name)])
        _ = try sync.fetched(FetchedChanges(records: [try toyRecord(toy([3]), tag: "9")]))
        #expect(try sync.heldToy()?.kind == .offered)
        #expect(try sync.toyChanged().engine.saves.isEmpty)
        #expect(try sync.batch(for: [.save(.toy(in: zone1.name))]).withdrawn == [.save(.toy(in: zone1.name))])
    }

    /// Condition 5: a full storage holds saves back, not deletions, until the next return to the front. The line in the
    /// settings follows the store's note until a save is accepted.
    @Test func aFullStorageHoldsSavesBack() throws {
        try joined()
        let inICloud = play(finishedAt: 1)
        _ = try sync.fetched(FetchedChanges(records: [try record(of: inICloud)]))
        let finished = play(finishedAt: 2)
        _ = try sync.finished(finished)
        _ = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, id: playID(finished), reason: .storageFull)]))
        #expect(sync.storageIsFull && sync.run.storageFullThisRun)
        #expect(try state(of: finished) == .unsent)
        #expect(try sync.toyChanged().engine.saves.isEmpty)
        let cleared = try sync.clearHistory()
        #expect(cleared.engine.deletions == [playID(inICloud)] && cleared.engine.saves.isEmpty)
        #expect(try sync.cameToFront().engine.saves.isEmpty, "the unsent play was removed by the clearing")
        _ = try sync.finished(finished)
        _ = try sync.sent(SentChanges(saved: [try record(of: finished)]))
        #expect(!sync.storageIsFull)
    }

    /// Coming to the front forgets a full storage noted in this run, asks for a fetch, and asks the gate.
    @Test func comingToTheFrontForgetsAFullStorage() throws {
        try joined()
        let finished = play()
        _ = try sync.finished(finished)
        _ = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, id: playID(finished), reason: .storageFull)]))
        let front = try sync.cameToFront()
        #expect(front.engine.fetches && !front.engine.asksForAccount)
        #expect(front.engine.saves == [playID(finished)])
        #expect(sync.storageIsFull, "the line stays until a save is accepted")
    }

    /// On a new device, a toy that arrives before the first rest after the person's first move is offered, not taken up
    /// over the move; and every result in which the held toy appears or changes its kind says so.
    @Test func aFirstMoveOnANewDeviceIsNeverReplaced() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account("person"))
        try fetch(DatabaseChanges(existing: [zone1.name]))
        let arrived = try sync.fetched(FetchedChanges(records: [try toyRecord(toy([3]), tag: "4")]))
        #expect(try arrived.changesHeldToy && sync.heldToy()?.kind == .toTakeUp)
        let kept = try sync.keep(toy([1]))
        #expect(try kept.changesHeldToy && sync.heldToy()?.kind == .offered)
        #expect(try sync.takeUpHeldToy().replacedToy == nil)
        #expect(try sync.toy() == toy([1]))
    }

    /// The toy's moment asks the gate; keeping the toy at a rest asks nothing (section 11).
    @Test func keepingTheToyAsksNothing() throws {
        try joined()
        try sync.keep(toy([1]))
        #expect(try sync.store.toySide().isChanged)
        #expect(try sync.toyChanged().engine.saves == [.toy(in: zone1.name)])
    }

    // MARK: The fetch that counts (section 11)

    /// The engine's own fetches deliver changes but never open the gate; a request for which no fetch began is asked
    /// again once.
    @Test func onlyAFetchTheAppAskedForCounts() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account("person"))
        sync.fetchBegan(manual: false)
        _ = try sync.databaseChanged(DatabaseChanges(existing: [zone1.name]))
        _ = try sync.fetchEnded(manual: false)
        #expect(try sync.gateZone(notes) == nil, "the engine's own fetch joined, and does not count")
        let request = sync.fetchWillBeRequested()
        let none = try sync.fetchRequestReturned(request, error: nil, pendingZoneSaves: [])
        #expect(none.engine.fetches, "no fetch began for the request: it is asked again")
        let again = sync.fetchWillBeRequested()
        #expect(try !sync.fetchRequestReturned(again, error: nil, pendingZoneSaves: []).engine.fetches, "but only once")
        try fetch()
        #expect(try sync.gateZone(notes) == zone1.name)
    }

    @Test func noRequestIsAskedAgainWhileNoAccountIsKnown() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.noAccount)
        let request = sync.fetchWillBeRequested()
        #expect(try !sync.fetchRequestReturned(request, error: .whole, pendingZoneSaves: []).engine.fetches)
    }

    /// A fetch that began before the request, or ended after it returned, does not count.
    @Test func theFetchMustBeginAfterTheRequestAndEndBeforeItReturns() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account("person"))
        try fetch(DatabaseChanges(existing: [zone1.name]))
        sync.fetchBegan(manual: true)
        let late = sync.fetchWillBeRequested()
        _ = try sync.fetchEnded(manual: true)
        _ = try sync.fetchRequestReturned(late, error: nil, pendingZoneSaves: [])
        #expect(try sync.gateZone(notes) == nil, "the fetch began before the request")
        let early = sync.fetchWillBeRequested()
        sync.fetchBegan(manual: true)
        _ = try sync.fetchRequestReturned(early, error: nil, pendingZoneSaves: [])
        _ = try sync.fetchEnded(manual: true)
        #expect(try sync.gateZone(notes) == nil, "the fetch ended after the request returned")
    }

    /// A request that fails does not count, unless its error names only zones the device does not use, or the zone it
    /// uses with an error that says the zone is gone; an error at the end of the zone's fetch keeps it from counting.
    @Test func whichErrorsKeepAFetchFromCounting() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account("person"))
        try fetch(DatabaseChanges(existing: [zone1.name]))
        try fetch(error: .whole)
        #expect(try sync.gateZone(notes) == nil)
        try fetch(error: .zones([zone1.name: .other]))
        #expect(try sync.gateZone(notes) == nil)
        try fetch(zoneErrors: [zone1.name: .other])
        #expect(try sync.gateZone(notes) == nil)
        try fetch(error: .zones([zone2.name: .other]))
        #expect(try sync.gateZone(notes) == zone1.name, "the error names only a zone the device does not use")
    }

    // MARK: Creating a zone, and a zone not known to exist (section 9)

    /// A device that uses no zone and has something to send creates one once the account is confirmed and a fetch that
    /// counts has finished: the number after the highest it has heard of, a new random id, not known to exist; only the
    /// zone's save is queued. When iCloud confirms it, the device joins it.
    @Test func creatingAZone() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        try sync.keep(toy([1]))
        #expect(try sync.toyChanged().engine.savesZone == nil, "the account is not confirmed")
        _ = try sync.accountAnswered(.account("person"))
        let result = try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: zone2.name, reason: .purged)]))
        let created = try #require(result.engine.savesZone.flatMap(ZoneName.init))
        #expect(created.number == 3 && result.engine.saves.isEmpty)
        #expect(try zoneNote == ZoneNote(zone: created, knowledge: .notKnownToExist))
        #expect(try sync.toyChanged().engine.savesZone == nil, "the same name is never queued twice")
        let confirmed = try sync.zonesSent(SentZones(saved: [created.name]))
        #expect(try zoneNote == ZoneNote(zone: created, knowledge: .existing))
        #expect(confirmed.engine.fetches && confirmed.engine.withdrawsEverythingOutside == created.name)
        #expect(try fetch().engine.saves == [.toy(in: created.name)])
    }

    @Test func noZoneIsCreatedWithNothingToSend() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        try sync.keep(fresh)
        _ = try sync.accountAnswered(.account("person"))
        #expect(try fetch().engine.savesZone == nil)
    }

    /// A device that comes to use no zone creates one only after a fetch that counts and that began after that.
    @Test func creatingWaitsForAFetchAfterTheZoneWasLost() throws {
        try joined()
        try sync.keep(toy([1]))
        let request = sync.fetchWillBeRequested()
        sync.fetchBegan(manual: true)
        let reset = try sync.databaseChanged(DatabaseChanges(deleted: [ZoneDeletion(zone: zone1.name, reason: .encryptedDataReset)]))
        #expect(reset.engine.fetches, "the device asks at once for the fetch that creating a zone waits for")
        _ = try sync.fetchEnded(manual: true)
        let first = try sync.fetchRequestReturned(request, error: nil, pendingZoneSaves: [])
        #expect(first.engine.savesZone == nil, "the fetch began before the zone was lost")
        #expect(try fetch().engine.savesZone.flatMap(ZoneName.init)?.number == 2)
    }

    /// A zone not known to exist, still so when a fetch that counts and that began after has finished, is given up,
    /// unless the engine holds its save; at most once in a run.
    @Test mutating func aZoneNotKnownToExistIsGivenUp() throws {
        try joined()
        try sync.keep(toy([1]))
        _ = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.toyType, id: .toy(in: zone1.name), reason: .zoneGone(.missing))]))
        #expect(try zoneNote?.knowledge == .notKnownToExist)
        try fetch(pendingZoneSaves: [zone1.name])
        #expect(try zoneNote?.knowledge == .notKnownToExist, "the engine holds the zone's save")
        let given = try fetch()
        #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .deleted))
        #expect(given.engine.withdrawsEverything && given.engine.fetches)
        let created = try #require(try fetch().engine.savesZone.flatMap(ZoneName.init))
        #expect(created.number == 2)
        try fetch()
        #expect(try zoneNote?.knowledge == .notKnownToExist, "a second zone is not given up in the same run")
        _ = try relaunch()
        _ = try sync.accountAnswered(.account("person"))
        try fetch()
        #expect(try zoneNote?.knowledge == .deleted, "the next launch decides again")
    }

    // MARK: Reports of zones (section 9)

    /// A report that names a higher existing zone makes the device join it and bring everything it holds; lower ones are
    /// ignored, and so are names not of the design's form.
    @Test func aReportOfAHigherZoneIsJoined() throws {
        try joined()
        let finished = play()
        _ = try sync.fetched(FetchedChanges(records: [try record(of: finished)]))
        #expect(try state(of: finished) == .inICloud)
        let lower = try fetch(DatabaseChanges(existing: ["Plays", "NineRings-01-\(UUID().uuidString)"]))
        #expect(lower.engine.withdrawsEverythingOutside == nil)
        let higher = try fetch(DatabaseChanges(existing: [zone2.name, zone2b.name]))
        #expect(try zoneNote == ZoneNote(zone: zone2b, knowledge: .existing), "the highest named, by number and then id")
        #expect(higher.engine.withdrawsEverythingOutside == zone2b.name)
        #expect(try state(of: finished) == .sent, "its system fields were of the zone left")
        #expect(try notes.highestNumber == 2)
    }

    /// The highest number named is noted, from deleted zones too.
    @Test func theHighestNumberNamedIsNoted() throws {
        try joined()
        try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: ZoneName(number: 7, id: UUID()).name, reason: .deleted)]))
        #expect(try notes.highestNumber == 7)
    }

    /// A device that uses no zone joins the highest existing zone a report names, whatever its number.
    @Test func aDeviceThatUsesNoZoneJoinsWhateverIsNamed() throws {
        try joined(zone2)
        try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: zone2.name, reason: .encryptedDataReset)]))
        try fetch(DatabaseChanges(existing: [zone1.name]))
        #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .existing))
    }

    /// A deletion counts if the deleted zone is higher than the note's, or is the note's zone while not yet marked
    /// deleted. A device with no zone note counts none, and handling a deletion twice changes nothing.
    @Test func whenADeletionCounts() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account("person"))
        let finished = play()
        _ = try sync.finished(finished)
        try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: zone1.name, reason: .purged)]))
        #expect(try state(of: finished) == .unsent, "no zone note: no deletion counts")
        _ = try sync.zonesSent(SentZones(saved: [try #require(try zoneNote?.zone.name)]))
        let used = try #require(try zoneNote?.zone)
        try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: zone1.name, reason: .purged)]))
        #expect(try zoneNote?.zone == used && state(of: finished) == .unsent, "a lower zone's deletion does not count")
        try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: used.name, reason: .purged)]))
        #expect(try zoneNote == ZoneNote(zone: used, knowledge: .deleted) && state(of: finished) == nil)
        try sync.keep(toy([1]))
        let twice = try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: used.name, reason: .purged)]))
        #expect(!twice.changesHistory && twice.replacedToy == nil, "the second time changes nothing")
    }

    /// If several deletions count in one report, the highest becomes the note's zone, and if one of them is a purge or
    /// has the reason Deleted, the device removes its data as for a purge.
    @Test(arguments: [ZoneDeletionReason.purged, .deleted, .encryptedDataReset])
    func severalDeletionsInOneReport(second: ZoneDeletionReason) throws {
        try joined()
        let finished = play()
        _ = try sync.finished(finished)
        let result = try fetch(DatabaseChanges(deleted: [
            ZoneDeletion(zone: zone1.name, reason: .encryptedDataReset), ZoneDeletion(zone: zone2.name, reason: second),
        ]))
        #expect(try zoneNote == ZoneNote(zone: zone2, knowledge: .deleted))
        if second == .encryptedDataReset {
            #expect(try state(of: finished) == .unsent && result.replacedToy == nil)
        } else {
            #expect(try state(of: finished) == nil && result.replacedToy?.isUntouched == true)
            #expect(try notes.account == "person", "the account note stays")
        }
    }

    /// A purge removes the history, puts the toy back and empties its notes; the account note, the engine's state and
    /// the highest number stay, and what is queued is withdrawn.
    @Test func aPurge() throws {
        try joined()
        try sync.engineStateUpdated(Data("state".utf8))
        try sync.keep(toy([1]))
        _ = try sync.finished(play())
        let result = try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: zone1.name, reason: .purged)]))
        #expect(result.engine.withdrawsEverything && result.replacedToy?.isUntouched == true)
        #expect(try sync.history() == .empty)
        let side = try sync.store.toySide()
        #expect(!side.isChanged && side.base == nil && side.lastSend == nil && side.ownStamps.isEmpty && side.held == nil)
        #expect(try sync.engineState() == Data("state".utf8) && notes.highestNumber == 1 && notes.account == "person")
    }

    /// A reset keeps everything, leaves the zone: the base is emptied, the toy is marked, and every play in iCloud goes
    /// back to sent.
    @Test func aReset() throws {
        try joined()
        let arriving = play()
        _ = try sync.fetched(FetchedChanges(records: [try record(of: arriving), try toyRecord(toy([1]), tag: "4")]))
        _ = try sync.takeUpHeldToy()
        let result = try fetch(DatabaseChanges(deleted: [ZoneDeletion(zone: zone1.name, reason: .encryptedDataReset)]))
        #expect(result.engine.withdrawsEverything && result.engine.fetches)
        #expect(try state(of: arriving) == .sent)
        let side = try sync.store.toySide()
        #expect(side.base == nil && side.isChanged)
    }

    /// Leaving a zone sends back every play in iCloud that has no system fields of the zone the device now uses: also a
    /// play that became in iCloud through a refusal without the record, and has none.
    @Test func leavingTakesAlongAPlayInICloudWithoutSystemFields() throws {
        try joined()
        let finished = play()
        _ = try sync.finished(finished)
        _ = try sync.batch(for: [.save(playID(finished))])
        _ = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, id: playID(finished), reason: .refused(serverRecord: nil))]))
        #expect(try state(of: finished) == .inICloud)
        try fetch(DatabaseChanges(existing: [zone2.name]))
        #expect(try state(of: finished) == .sent)
        #expect(try fetch().engine.saves.contains(playID(finished, in: zone2)))
    }

    // MARK: The errors that say a zone is gone (section 9)

    @Test(arguments: [ZoneGone.missing, .encryptedDataReset, .userDeletedZone])
    func anErrorThatSaysTheZoneIsGoneInASave(gone: ZoneGone) throws {
        try joined()
        let finished = play()
        _ = try sync.finished(finished)
        _ = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, id: playID(finished), reason: .zoneGone(gone))]))
        switch gone {
        case .missing: #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .notKnownToExist))
        case .encryptedDataReset: #expect(try zoneNote?.knowledge == .deleted && state(of: finished) == .unsent)
        case .userDeletedZone: #expect(try zoneNote?.knowledge == .deleted && state(of: finished) == nil)
        }
    }

    /// At the end of the fetch of the zone the device uses, the same errors report that zone's end, and the fetch still
    /// counts; for another zone they mean nothing.
    @Test func anErrorThatSaysTheZoneIsGoneAtTheEndOfItsFetch() throws {
        try joined()
        try fetch(zoneErrors: [zone2.name: .zoneGone(.userDeletedZone)])
        #expect(try zoneNote?.knowledge == .existing)
        try fetch(zoneErrors: [zone1.name: .zoneGone(.missing)], error: .zones([zone1.name: .zoneGone(.missing)]))
        #expect(try zoneNote?.knowledge == .notKnownToExist)
        try fetch()
        #expect(try zoneNote?.knowledge == .deleted, "the fetch after it counted, and the zone was given up")
    }

    // MARK: Leaving a zone (section 9)

    @Test func answersAndRecordsOfAnotherZoneAreIgnored() throws {
        try joined()
        let finished = play()
        _ = try sync.finished(finished)
        _ = try sync.batch(for: [.save(playID(finished))])
        _ = try sync.sent(SentChanges(saved: [try record(of: finished, in: zone2)]))
        #expect(try state(of: finished) == .sent)
        _ = try sync.fetched(FetchedChanges(records: [try record(of: play(), in: zone2)]))
        #expect(try sync.history().plays.count == 1)
    }

    // MARK: The account (section 8)

    /// An account with none noted is noted, and what was made without iCloud goes into it; the same account changes
    /// nothing more; another account removes the toy, the history and the sync notes.
    @Test func theAccountTable() throws {
        _ = try sync.launched(engineStartsFromNothing: false)
        let made = play()
        _ = try sync.finished(made)
        _ = try sync.accountAnswered(.account("person"))
        #expect(try notes.account == "person" && state(of: made) == .unsent)
        #expect(try sync.accountAnswered(.account("person")).replacedToy == nil)
        try fetch(DatabaseChanges(existing: [zone1.name]))
        try sync.engineStateUpdated(Data("state".utf8))
        let other = try sync.accountChanged(.switchAccounts(from: "person", to: "other"))
        #expect(other.replacedToy?.isUntouched == true && other.engine.withdrawsEverything)
        #expect(try sync.history() == .empty && notes.account == "other" && zoneNote == nil && notes.highestNumber == 0)
    }

    /// A sign-out keeps everything, notes the account that signed out if none was noted, empties the zone note, and the
    /// account is not confirmed.
    @Test func aSignOut() throws {
        _ = try sync.launched(engineStartsFromNothing: false)
        _ = try sync.finished(play())
        _ = try sync.accountChanged(.signOut("person"))
        #expect(try notes.account == "person" && sync.history().plays.count == 1)
        try joined()
        _ = try sync.accountChanged(.signOut("person"))
        #expect(try zoneNote == nil && notes.highestNumber == 1 && !sync.run.accountConfirmed)
    }

    /// A start from nothing changes the store in two parts. When it begins: plays in iCloud go back to sent, a zone noted
    /// as existing becomes not known to exist. When the account is confirmed: the account's part, and the engine's state,
    /// saved for the first time then. A quit before that makes the next launch a start from nothing again.
    @Test mutating func aStartFromNothingInTwoParts() throws {
        try joined()
        let arriving = play()
        _ = try sync.fetched(FetchedChanges(records: [try record(of: arriving)]))
        try sync.engineStateUpdated(Data("before".utf8))
        _ = try sync.accountChanged(.signOut("person"))
        try fetch(DatabaseChanges(existing: [zone1.name]))
        _ = try relaunch()
        #expect(try zoneNote?.knowledge == .existing)
        _ = try sync.accountChanged(.signIn("person"))
        #expect(try state(of: arriving) == .sent && zoneNote?.knowledge == .notKnownToExist)
        #expect(sync.run.accountConfirmed, "the sign-in names the account")
        _ = try relaunch(fromNothing: true)
        try sync.engineStateUpdated(Data("held".utf8))
        #expect(try sync.engineState() == nil, "held until the account's part")
        _ = try relaunch(fromNothing: true)
        try sync.engineStateUpdated(Data("held again".utf8))
        _ = try sync.accountAnswered(.account("person"))
        #expect(try sync.engineState() == Data("held again".utf8))
    }

    /// The sign-in of an engine created without saved state belongs to the start from nothing that began at launch: a
    /// zone the device joined before the report stays known to exist.
    @Test func theSignInOfAnEngineFromNothingBelongsToItsStart() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        _ = try sync.accountAnswered(.account("person"))
        try fetch(DatabaseChanges(existing: [zone1.name]))
        _ = try sync.accountChanged(.signIn("person"))
        #expect(try zoneNote?.knowledge == .existing)
    }

    /// A sign-in that an engine with saved state reports, before or after its first report of the zones in this run: the
    /// device ends in its zone, which it knows to exist, either way. After a report that named the zone as existing, the
    /// first part of the start from nothing leaves the zone note as it is.
    @Test(arguments: [true, false])
    mutating func aSignInReportedBeforeOrAfterAReportOfTheZone(reportFirst: Bool) throws {
        try joined()
        _ = try sync.accountChanged(.signOut("person"))
        _ = try relaunch()
        if reportFirst {
            try fetch(DatabaseChanges(existing: [zone1.name]))
            #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .existing))
            _ = try sync.accountChanged(.signIn("person"))
            #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .existing), "named as existing in this run")
        } else {
            _ = try sync.accountChanged(.signIn("person"))
            try fetch(DatabaseChanges(existing: [zone1.name]))
        }
        try fetch()
        #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .existing), "the zone is not given up")
        #expect(sync.gateZone(try notes) == zone1.name)
    }

    /// A zone note from an earlier run is left alone too, when a report has named that zone again in this run.
    @Test mutating func aZoneNamedAgainBeforeASignInIsLeftAlone() throws {
        try joined()
        _ = try relaunch()
        try fetch(DatabaseChanges(existing: [zone1.name]))
        _ = try sync.accountChanged(.signIn("person"))
        #expect(try zoneNote == ZoneNote(zone: zone1, knowledge: .existing))
    }

    /// Both answers to the offer are sending moments: Play That One on a held toy without system fields marks the toy, and
    /// the gate lets it go at once.
    @Test func playThatOneIsASendingMoment() throws {
        try joined()
        try sync.keep(toy([1]))
        _ = try sync.fetched(FetchedChanges(records: [try toyRecord(toy([3]), tag: "9")]))
        try fetch(DatabaseChanges(existing: [zone2.name], deleted: [ZoneDeletion(zone: zone1.name, reason: .encryptedDataReset)]))
        try fetch()
        #expect(try sync.heldToy()?.kind == .offered)
        let played = try sync.playThatOne()
        #expect(played.replacedToy != nil && played.engine.saves == [.toy(in: zone2.name)])
    }

    // MARK: Leaving the front (section 11)

    /// Leaving the front asks the gate for the toy and the engine to send. While the gate waits for the account or for
    /// this run's fetch, the app keeps its background time, until a result ends it.
    @Test mutating func leavingTheFrontWaitsForTheGate() throws {
        try joined()
        _ = try relaunch()
        try sync.keep(toy([1]))
        let left = try sync.leftFront()
        #expect(left.engine.sendsNow && left.keepsBackgroundTime && left.engine.saves.isEmpty)
        #expect(try !sync.accountAnswered(.account("person")).endsBackgroundTime)
        let opened = try fetch()
        #expect(opened.endsBackgroundTime && opened.engine.sendsNow && opened.engine.saves == [.toy(in: zone1.name)])
        #expect(try !sync.leftFront().keepsBackgroundTime)
    }

    /// With no account signed in, nothing can confirm one: leaving the front keeps no background time.
    @Test func leavingTheFrontWithNoAccountKeepsNoTime() throws {
        _ = try sync.launched(engineStartsFromNothing: true)
        try sync.keep(toy([1]))
        #expect(try sync.leftFront().keepsBackgroundTime, "the account's answer may still come")
        _ = try sync.cameToFront()
        _ = try sync.accountAnswered(.noAccount)
        #expect(try !sync.leftFront().keepsBackgroundTime)
    }

    // MARK: Failures (section 10)

    @Test(arguments: [SaveFailure.answerLost, .temporary, .other])
    func otherFailuresKeepTheMarks(failure: SaveFailure) throws {
        try joined()
        let finished = play()
        _ = try sync.finished(finished)
        _ = try sync.batch(for: [.save(playID(finished))])
        let result = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.finishedPlayType, id: playID(finished), reason: failure)]))
        #expect(try state(of: finished) == .sent)
        #expect(result.engine.withdrawnSaves == (failure == .other ? [playID(finished)] : []))
        #expect(try sync.toyChanged().engine.saves == [playID(finished)], "it goes out again at the next sending moment")
    }

    @Test func aToyRefusedWithoutItsRecordFetches() throws {
        try joined()
        try sync.keep(toy([1]))
        let result = try sync.sent(SentChanges(failedSaves: [FailedSave(type: CloudRecord.toyType, id: .toy(in: zone1.name), reason: .refused(serverRecord: nil))]))
        #expect(try result.engine.fetches && sync.store.toySide().isChanged)
    }

    /// What one call changes reaches the store in one save: when that save fails, nothing of the call is kept.
    @Test func aFailedSaveLeavesTheStoreAsItWas() throws {
        let folder = URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let writable = ICloudSync(store: RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder))), madeOn: .Mac, appVersion: "2.0")
            try writable.keep(toy([1]))
            _ = try writable.launched(engineStartsFromNothing: false)
        }
        let readOnly = ModelConfiguration("Device", schema: RecordStore.deviceSchema, url: folder.appending(path: "Device.store"), allowsSave: false, cloudKitDatabase: .none)
        let store = RecordStore(container: try ModelContainer(for: RecordStore.deviceSchema, configurations: readOnly))
        let failing = ICloudSync(store: store, madeOn: .Mac, appVersion: "2.0")
        let before = try store.toySide()
        #expect(throws: (any Error).self) { try failing.keep(toy([1, 3])) }
        #expect(try store.toySide() == before)
        #expect(throws: (any Error).self) { try failing.finished(play()) }
        #expect(try store.allPlays().isEmpty)
        #expect(!store.container.mainContext.hasChanges)
    }

    /// Writing fetched changes fails: for the rest of the run nothing more is applied, nothing is sent, no fetch counts,
    /// and the engine's state is not saved again, so that the next launch fetches the same changes again.
    @Test func aFailedWriteOfFetchedChanges() throws {
        let folder = URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let writable = ICloudSync(store: RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder))), madeOn: .Mac, appVersion: "2.0")
            _ = try writable.launched(engineStartsFromNothing: true)
            _ = try writable.accountAnswered(.account("person"))
            try writable.engineStateUpdated(Data("first".utf8))
        }
        let readOnly = ModelConfiguration("Device", schema: RecordStore.deviceSchema, url: folder.appending(path: "Device.store"), allowsSave: false, cloudKitDatabase: .none)
        let failing = ICloudSync(store: RecordStore(container: try ModelContainer(for: RecordStore.deviceSchema, configurations: readOnly)), madeOn: .Mac, appVersion: "2.0")
        _ = try failing.launched(engineStartsFromNothing: false)
        let request = failing.fetchWillBeRequested()
        failing.fetchBegan(manual: true)
        #expect(throws: (any Error).self) { try failing.databaseChanged(DatabaseChanges(existing: [zone1.name])) }
        #expect(failing.run.writeFailed && !failing.run.savesEngineState)
        #expect(try failing.fetched(FetchedChanges(records: [record(of: play())])) == SyncResult(), "nothing more is applied")
        _ = try failing.fetchEnded(manual: true)
        _ = try failing.fetchRequestReturned(request, error: nil, pendingZoneSaves: [])
        #expect(failing.run.lastCountedFetchBegan == nil, "no fetch counts")
        try failing.engineStateUpdated(Data("second".utf8))
        #expect(try failing.engineState() == Data("first".utf8))
    }

    // MARK: Batches (sections 6, 7 and 11)

    /// What the records need is saved before they are handed over; a play iCloud has, a cleared one, a record of another
    /// zone, or anything while the gate is shut, is withdrawn; a deletion goes only for a cleared entry.
    @Test func aBatch() throws {
        try joined()
        try sync.keep(toy([1]))
        let unsent = play(finishedAt: 1)
        let inICloud = play(finishedAt: 2)
        _ = try sync.finished(unsent)
        _ = try sync.fetched(FetchedChanges(records: [try record(of: inICloud)]))
        let toy = RecordID.toy(in: zone1.name)
        let batch = try sync.batch(for: [.save(toy), .save(playID(unsent)), .save(playID(inICloud)), .save(playID(unsent, in: zone2)), .delete(playID(inICloud))])
        #expect(batch.records.map(\.id) == [toy, playID(unsent)])
        #expect(Set(batch.withdrawn) == [.save(playID(inICloud)), .save(playID(unsent, in: zone2)), .delete(playID(inICloud))])
        #expect(try state(of: unsent) == .sent)
        let side = try sync.store.toySide()
        #expect(side.lastSend != nil && side.ownStamps.count == 1)
        _ = try sync.clearHistory()
        #expect(try sync.batch(for: [.delete(playID(inICloud))]).deletions == [playID(inICloud)])
    }

    /// A play is recorded once; the history shows every entry that is not cleared, newest first, and counts what this build
    /// cannot read.
    @Test func theHistory() throws {
        try joined()
        let mine = play(finishedAt: 5)
        _ = try sync.finished(mine)
        _ = try sync.finished(mine)
        let newer = play(finishedAt: 9)
        _ = try sync.fetched(FetchedChanges(records: [try record(of: newer), try record(of: play(), format: 2)]))
        #expect(try sync.history() == PlayHistory(plays: [newer, mine], unreadable: 1))
        _ = try sync.clearHistory()
        #expect(try sync.history() == .empty)
        #expect(try sync.store.plays(in: .cleared).count == 2, "the plays this build cannot read are cleared too")
    }

    // MARK: The store

    /// The device's store keeps the rules' models; the store that syncs through SwiftData never has them.
    @Test func theDevicesStoreAloneKeepsTheRulesModels() {
        #expect(Set(RecordStore.deviceSchema.entities.map(\.name)) == ["FinishedPlay", "SavedToy", "KeptToy", "KeptPlay", "SyncNotes"])
        #expect(Set(RecordStore.schema.entities.map(\.name)) == ["FinishedPlay", "SavedToy"])
    }

    /// A device store written by the code before these rules opens without an error. Nothing it held is carried over.
    @Test func aStoreWrittenBeforeOpens() throws {
        let folder = URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let earlier = ModelConfiguration("Device", schema: RecordStore.schema, url: folder.appending(path: "Device.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: RecordStore.schema, configurations: earlier)
            let store = RecordStore(container: container)
            try store.record(play(), madeOn: .iPhone, appVersion: "1.0")
            _ = try store.keep(toy([1]), installation: "earlier", appVersion: "1.0")
        }
        let store = RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder)))
        #expect(try store.playHistory().plays.count == 1, "the earlier way still reads")
        let rules = ICloudSync(store: store, madeOn: .iPhone, appVersion: "2.0")
        #expect(try rules.toy() == nil && rules.history() == .empty)
        _ = try rules.launched(engineStartsFromNothing: true)
        _ = try rules.finished(play())
        #expect(try rules.history().plays.count == 1)
    }
}
