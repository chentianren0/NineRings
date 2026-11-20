import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// Every row of the table in docs/icloud.md section 17, as a test that reads like the row, with simulated devices against
/// the stand-in iCloud; and the orders of events that broke an earlier text of the design.
@MainActor
@Suite struct CasesTests {
    /// Two devices of the person, synced, with a few moves and a finished play behind them.
    private func twoSyncedDevices(_ world: World) throws -> (iPhone: SimulatedDevice, iPad: SimulatedDevice) {
        let iPhone = try world.device("iPhone")
        let iPad = try world.device("iPad", kind: .iPad)
        iPhone.move()
        iPhone.finishPlay()
        iPhone.move()
        iPhone.move()
        iPhone.putDown()
        world.settle()
        return (iPhone, iPad)
    }

    /// Whether the two toys are the same toy.
    private func same(_ a: ToySnapshot?, _ b: ToySnapshot?) -> Bool {
        guard let a, let b else { return false }
        return a.isSameToy(as: b)
    }

    // MARK: The rows

    /// The device has no iCloud account: the app works from its store. The engine is dormant.
    @Test func theDeviceHasNoICloudAccount() throws {
        let world = World()
        let device = try world.device("iPhone", account: nil)
        device.move()
        device.finishPlay()
        world.settle()
        #expect(device.history.plays.count == 1)
        #expect(device.hasMarks, "the store keeps what iCloud has not received")
        #expect(!device.engineSends() && !device.engineFetches(), "the engine is dormant")
        #expect(world.cloud.records(zone: World.zone, account: World.person).isEmpty)
    }

    /// A new device, and iCloud has data: the device joins. The history fills in and the toy is taken up.
    @Test func aNewDeviceJoins() throws {
        let world = World()
        let iPhone = try world.device("iPhone")
        iPhone.move()
        iPhone.finishPlay()
        iPhone.move()
        iPhone.putDown()
        world.settle()
        let mac = try world.device("Mac", kind: .Mac)
        world.settle()
        #expect(mac.history == iPhone.history && mac.history.plays.count == 1)
        #expect(same(mac.keptToy, iPhone.keptToy))
        #expect(!mac.isOffered && world.watcher.problems.isEmpty)
    }

    /// If the person played on the new device before the fetch came in, they are asked.
    @Test func aNewDevicePlayedBeforeTheFetchAsks() throws {
        let world = World()
        let iPhone = try world.device("iPhone")
        iPhone.move()
        iPhone.putDown()
        world.settle()
        let mac = try world.device("Mac", kind: .Mac)
        mac.move()
        world.settle()
        #expect(mac.isOffered)
        #expect(!same(mac.keptToy, iPhone.keptToy), "the Mac's toy stays until the person answers")
    }

    /// The app is deleted and installed again: the same as a new device.
    @Test func theAppIsInstalledAgain() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let history = iPhone.history
        let toy = iPhone.keptToy
        world.remove(iPhone)
        let again = try world.device("iPhone, installed again")
        world.settle()
        #expect(again.history == history)
        #expect(same(again.keptToy, toy))
    }

    /// The person plays on one device, then opens another: the first sends as it leaves the front, and the second fetches
    /// as it comes to the front and takes the toy up.
    @Test func thePersonGoesOnOnAnotherDevice() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.pickUp(moves: 3)
        iPhone.putDown()
        iPad.pickUp(moves: 0)
        #expect(same(iPad.keptToy, iPhone.keptToy))
        #expect(!iPad.isOffered && world.watcher.problems.isEmpty)
    }

    /// Two devices were played apart: the device that syncs second is refused, holds the other toy, and shows the offer.
    /// Keep This One sends its toy again with the tag of the record it was shown, and the other device takes it up; Play
    /// That One shows the other play and sends nothing.
    @Test(arguments: [true, false])
    func twoDevicesPlayedApart(keepThisOne: Bool) throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPad.move(ring: 1)
        iPad.move(ring: 1)
        iPhone.move(ring: 1)
        iPhone.putDown()
        iPad.isOnline = true
        iPad.putDown()
        #expect(iPad.isOffered)
        let theirs = iPhone.keptToy
        let mine = iPad.keptToy
        iPad.answerOffer(keepThisOne: keepThisOne)
        world.settle()
        let kept = keepThisOne ? mine : theirs
        #expect(same(iPad.keptToy, kept) && same(iPhone.keptToy, kept))
        #expect(same(world.toyInICloud()?.toy, kept))
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// The offer is never answered: that device's toy stays on that device, and the other devices go on sharing.
    @Test func theOfferIsNeverAnswered() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let mac = try world.device("Mac", kind: .Mac)
        world.settle()
        iPad.isOnline = false
        iPad.move(ring: 1)
        iPad.move(ring: 1)
        iPhone.move(ring: 1)
        iPhone.putDown()
        iPad.isOnline = true
        world.settle()
        #expect(iPad.isOffered)
        let iPadsToy = iPad.keptToy
        mac.pickUp(moves: 2)
        mac.putDown()
        iPhone.pickUp(moves: 1)
        iPhone.putDown()
        world.settle()
        #expect(same(mac.keptToy, iPhone.keptToy))
        #expect(same(iPad.keptToy, iPadsToy) && iPad.isOffered)
        #expect(!same(world.toyInICloud()?.toy, iPadsToy), "the iPad sends no toy while it holds one")
    }

    /// Three devices: the third takes up whichever toy is in iCloud.
    @Test func theThirdDeviceTakesUpWhicheverToyIsInICloud() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPad.move(ring: 1)
        iPad.move(ring: 1)
        iPhone.move(ring: 1)
        iPhone.putDown()
        iPad.isOnline = true
        iPad.putDown()
        iPad.answerOffer(keepThisOne: true)
        world.settle()
        let mac = try world.device("Mac", kind: .Mac)
        world.settle()
        #expect(same(mac.keptToy, world.toyInICloud()?.toy) && same(mac.keptToy, iPad.keptToy))
    }

    /// A device is restored from a backup, with the same account: the store and the engine state return as they were, the
    /// engine goes on from its tokens, and the toy is taken up, or the person is asked, by the usual rule.
    @Test(arguments: [false, true])
    func aDeviceIsRestoredFromABackup(changedInTheBackup: Bool) throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        if changedInTheBackup { iPhone.move() }
        let backup = try iPhone.backUp()
        iPhone.putDown()
        world.settle()
        iPad.pickUp(moves: 2)
        iPad.putDown()
        iPad.finishPlay()
        world.settle()
        try iPhone.restore(from: backup)
        world.settle()
        if changedInTheBackup {
            #expect(iPhone.isOffered, "both devices changed the toy after the backup's version")
        } else {
            #expect(same(iPhone.keptToy, iPad.keptToy), "taken up")
        }
        #expect(iPhone.history == iPad.history)
        #expect(world.watcher.problems.isEmpty)
    }

    /// A backup is restored on a device with another account: the engine reports a switch of account, the data is removed,
    /// and the device joins with nothing.
    @Test func aBackupIsRestoredUnderAnotherAccount() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let backup = try iPhone.backUp()
        let other = try world.device("Another person's iPhone", account: World.other, from: backup)
        world.settle()
        #expect(other.history.plays.isEmpty)
        #expect(other.keptToy?.isUntouched == true)
        #expect(world.cloud.records(zone: World.zone, account: World.other).isEmpty, "nothing of one person goes into another's iCloud")
    }

    /// Two devices are set up from one backup: two devices with the same starting point, which nothing confuses.
    @Test func twoDevicesFromOneBackup() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let backup = try iPhone.backUp()
        let first = try world.device("iPad A", kind: .iPad, from: backup)
        let second = try world.device("iPad B", kind: .iPad, from: backup)
        world.settle()
        first.pickUp(moves: 2)
        first.putDown()
        second.pickUp(moves: 0)
        #expect(same(second.keptToy, first.keptToy))
        second.move()
        second.finishPlay()
        second.putDown()
        first.pickUp(moves: 0)
        world.settle()
        #expect(same(first.keptToy, second.keptToy) && !first.isOffered && !second.isOffered)
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// The person signs out of iCloud, or turns iCloud off for the app: the data stays, and the app works from its store.
    @Test func aSignOutKeepsTheData() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let before = iPhone.history.plays.count
        iPhone.signIn(to: nil)
        iPhone.move()
        iPhone.finishPlay()
        world.settle()
        #expect(iPhone.history.plays.count == before + 1)
        #expect(world.historyInICloud().plays.count == before)
        #expect(iPhone.hasMarks)
    }

    /// The same account returns: the device joins, the histories unite, and the toy's rule decides.
    @Test func theSameAccountReturns() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.signIn(to: nil)
        // The play both devices had in progress, then one of the iPhone's own.
        iPhone.finishPlay()
        iPhone.finishPlay()
        iPhone.move()
        iPad.pickUp(moves: 1)
        iPad.finishPlay()
        iPad.putDown()
        world.settle()
        iPhone.signIn(to: World.person)
        world.settle()
        #expect(iPhone.history == iPad.history && iPhone.history.plays.count == 3)
        #expect(iPhone.isOffered, "both changed the toy: the person is asked")
    }

    /// Another account signs in: the previous data is removed, and the new account's data arrives.
    @Test func anotherAccountSignsIn() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let theirs = try world.device("Another person's iPad", kind: .iPad, account: World.other)
        theirs.move()
        theirs.finishPlay()
        theirs.finishPlay()
        theirs.move()
        theirs.putDown()
        world.settle()
        iPhone.signIn(to: World.other)
        world.settle()
        #expect(iPhone.history == theirs.history && iPhone.history.plays.count == 2)
        #expect(same(iPhone.keptToy, theirs.keptToy))
        #expect(world.historyInICloud(account: World.other).plays.count == 2, "nothing of the first account went into the other's")
    }

    /// The iCloud storage is full: saves are refused, the data stays, marked as not received, and is offered again at the
    /// next launch or return to the front. A line says so.
    @Test func theStorageIsFull() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        world.cloud.database(World.person).isFull = true
        iPhone.finishPlay()
        iPhone.putDown()
        world.settle()
        #expect(iPhone.sync.storageIsFull)
        #expect(iPhone.hasMarks)
        #expect(world.historyInICloud().plays.count == 1)
        world.cloud.database(World.person).isFull = false
        iPhone.cameToFront()
        world.settle()
        #expect(!iPhone.sync.storageIsFull && !iPhone.hasMarks)
        #expect(world.historyInICloud().plays.count == 2)
    }

    /// The device is offline: the engine waits, and the store keeps the marks.
    @Test func theDeviceIsOffline() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.isOnline = false
        iPhone.finishPlay()
        iPhone.putDown()
        world.settle()
        #expect(iPhone.hasMarks && iPad.history.plays.count == 1)
        iPhone.isOnline = true
        world.settle()
        #expect(iPad.history == iPhone.history && iPad.history.plays.count == 2)
    }

    /// The person deletes the app's data from iCloud in Settings: every device that hears of it removes the history and
    /// puts the toy back to its start. (Section 9 as the text stands; it is to change.)
    @Test func theAppsDataIsDeletedFromICloud() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        world.cloud.deleteZone(World.zone, account: World.person, reason: .purged)
        world.settle()
        for device in [iPhone, iPad] {
            #expect(device.history.plays.isEmpty)
            #expect(device.keptToy?.isUntouched == true)
        }
        #expect(world.cloud.records(zone: World.zone, account: World.person).isEmpty, "nothing is sent again")
        #expect(world.watcher.problems.isEmpty)
    }

    /// The person resets their encrypted data: every device that hears of it keeps its data and sends it again. The first
    /// toy to arrive becomes the record, and a device with a different toy shows the offer. (Section 9 as the text stands;
    /// it is to change.)
    @Test func theEncryptedDataIsReset() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPad.move()
        let plays = iPhone.history
        world.cloud.deleteZone(World.zone, account: World.person, reason: .encryptedDataReset)
        world.settle()
        iPad.isOnline = true
        world.settle()
        #expect(world.historyInICloud() == plays && iPad.history == plays && iPhone.history == plays)
        #expect(same(world.toyInICloud()?.toy, iPhone.keptToy))
        #expect(iPad.isOffered)
    }

    /// The history is cleared while another device is offline: that device removes those plays when it syncs, and plays it
    /// finished meanwhile stay.
    @Test func theHistoryIsClearedWhileAnotherDeviceIsOffline() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.finishPlay()
        world.settle()
        iPad.isOnline = false
        iPad.finishPlay()
        let meanwhile = try #require(iPad.history.plays.first)
        iPhone.clearHistory()
        world.settle()
        iPad.isOnline = true
        world.settle()
        #expect(iPad.history.plays == [meanwhile] && iPhone.history.plays == [meanwhile])
    }

    /// The history is cleared while another device is signed out: when that device returns, it removes the plays whose
    /// deletions iCloud still delivers, and brings the others back.
    @Test(arguments: [true, false])
    func theHistoryIsClearedWhileAnotherDeviceIsSignedOut(deletionsDelivered: Bool) throws {
        var choices = StandInICloud.Choices()
        choices.fetchFromNothingBringsOldDeletions = deletionsDelivered
        let world = World(cloud: choices)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.finishPlay()
        world.settle()
        let cleared = iPhone.history
        iPad.signIn(to: nil)
        iPhone.clearHistory()
        world.settle()
        iPad.signIn(to: World.person)
        world.settle()
        let expected = deletionsDelivered ? PlayHistory() : cleared
        #expect(iPad.history == expected && iPhone.history == expected)
    }

    /// The app is closed between a held toy and the person's answer: the toy stays held, nothing is sent at the next
    /// launch, and the offer shows again.
    @Test func theAppIsClosedWhileAToyIsHeld() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPad.move(ring: 1)
        iPad.move(ring: 1)
        iPhone.move(ring: 1)
        iPhone.putDown()
        iPad.isOnline = true
        iPad.putDown()
        #expect(iPad.isOffered)
        iPad.relaunch()
        #expect(iPad.isOffered)
        #expect(!iPad.engine.state.pending.contains(.save(CloudRecord.toyName)), "nothing is sent at the next launch")
        world.settle()
        #expect(iPad.isOffered && same(world.toyInICloud()?.toy, iPhone.keptToy))
    }

    /// The same play is finished on two devices: one entry, the record that arrived first.
    @Test func theSamePlayIsFinishedOnTwoDevices() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let id = try #require(iPhone.keptToy?.play?.id)
        #expect(iPad.keptToy?.play?.id == id)
        iPhone.isOnline = false
        iPad.isOnline = false
        iPhone.finishPlay()
        iPad.finishPlay()
        iPhone.isOnline = true
        iPhone.putDown()
        iPad.isOnline = true
        world.settle(answeringOffers: false)
        let first = try #require(iPhone.history.plays.first { $0.playID == id })
        #expect(iPad.history.plays.filter { $0.playID == id } == [first])
        #expect(world.historyInICloud().plays.filter { $0.playID == id } == [first])
    }

    /// The app crashes between a change and its sending: the store's marks queue the change again at the next launch.
    @Test func theAppCrashesBeforeSending() throws {
        var engine = StandInEngine.Choices()
        engine.stateUpdateAfterChange = 0
        let world = World(engine: engine)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.finishPlay()
        iPhone.move()
        iPhone.leftFront()
        iPhone.relaunch()
        #expect(iPhone.engine.state.pending.count == 2, "queued again from the store's marks")
        world.settle()
        #expect(iPad.history == iPhone.history && iPad.history.plays.count == 2)
        #expect(same(iPad.keptToy, iPhone.keptToy))
    }

    /// The answer to a save is lost: the record's stamp shows the device that the record in iCloud is its own. A finished
    /// play stays sent, so clearing still reaches it.
    @Test func theAnswerToASaveIsLost() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerLost = 1
        iPhone.engine.choices.landsWhenAnswerLost = 1
        iPhone.engine.choices.resendsLostAnswers = true
        iPhone.move()
        iPhone.finishPlay()
        iPhone.putDown()
        iPhone.engine.choices.answerLost = 0
        let lost = try #require(iPhone.history.plays.first)
        #expect(try iPhone.sync.store.entries([lost.playID])[lost.playID]?.sync == .sent)
        iPhone.engineSends()
        #expect(!iPhone.toySide.isChanged && !iPhone.isOffered, "its own toy, recognised by its stamp")
        iPad.engineFetches()
        iPhone.clearHistory()
        world.settle()
        #expect(world.historyInICloud().plays.isEmpty && iPad.history.plays.isEmpty)
    }

    /// A save lands, its answer is lost, and the person plays on elsewhere: the first device finds its own stamp among the
    /// arriving toy's earlier stamps and takes the toy up.
    @Test func aLostAnswerFollowedByPlayElsewhere() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerLost = 1
        iPhone.engine.choices.landsWhenAnswerLost = 1
        iPhone.engine.choices.resendsLostAnswers = false
        iPhone.move()
        iPhone.putDown()
        iPhone.engine.choices.answerLost = 0
        #expect(iPhone.toySide.isChanged, "no answer came")
        iPad.pickUp(moves: 2)
        iPad.putDown()
        iPhone.pickUp(moves: 0)
        #expect(!iPhone.isOffered)
        #expect(same(iPhone.keptToy, iPad.keptToy))
        #expect(world.watcher.problems.isEmpty)
    }

    /// An older version meets a newer format: a finished play is counted and not shown, and a toy is neither taken up nor
    /// replaced.
    @Test func anOlderVersionMeetsANewerFormat() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let base = try #require(world.cloud.record(CloudRecord.toyName, zone: World.zone, account: World.person))
        let newer = Data(#"{"aLaterShape":true}"#.utf8)
        _ = world.cloud.save(RecordToSend(type: CloudRecord.toyType, name: CloudRecord.toyName, systemFields: base.systemFields, format: 2, payload: newer), zone: World.zone, account: World.person, device: "a newer version")
        _ = world.cloud.save(RecordToSend(type: CloudRecord.finishedPlayType, name: UUID().uuidString, systemFields: nil, format: 2, payload: newer), zone: World.zone, account: World.person, device: "a newer version")
        iPhone.pickUp(moves: 1)
        let mine = iPhone.keptToy
        iPhone.putDown()
        world.settle()
        #expect(iPhone.history.unreadable == 1 && iPhone.history.plays.count == 1)
        #expect(try iPhone.sync.heldToy()?.kind == .needsNewerVersion)
        #expect(same(iPhone.keptToy, mine), "the toy here is neither taken up nor replaced by the one it cannot read")
        #expect(world.cloud.record(CloudRecord.toyName, zone: World.zone, account: World.person)?.format == 2, "and this device sends no toy")
    }

    /// A device's clock is wrong: only the order and the times shown in the history are affected.
    @Test func aDevicesClockIsWrong() throws {
        let world = World()
        let wrong = TestClock()
        wrong.offset = -10 * 365 * 86_400
        let iPhone = try world.device("iPhone")
        let iPad = try world.device("iPad", kind: .iPad, clock: wrong)
        world.settle()
        iPad.move()
        iPad.finishPlay()
        iPad.putDown()
        iPhone.pickUp(moves: 1)
        iPhone.finishPlay()
        iPhone.putDown()
        iPad.pickUp(moves: 0)
        world.settle()
        #expect(iPhone.history == iPad.history && iPhone.history.plays.count == 2)
        #expect(same(iPad.keptToy, iPhone.keptToy) && !iPad.isOffered)
        let oldest = try #require(iPhone.history.plays.last)
        #expect(oldest.finishedAt < Date(timeIntervalSinceReferenceDate: 800_000_000), "the iPad's play shows as the older, by its clock")
    }

    // MARK: Orders of events that broke an earlier text

    /// A device's own save is fetched before its answer comes: it is its own toy, and nothing is sent again.
    @Test func anOwnSaveFetchedBeforeItsAnswer() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerComesLate = 1
        iPhone.move()
        iPhone.putDown()
        iPhone.engine.choices.answerComesLate = 0
        let sentBefore = iPhone.engine.changesSent
        iPhone.engineFetches()
        world.settle()
        #expect(!iPhone.isOffered && !iPad.isOffered)
        #expect(iPhone.engine.changesSent == sentBefore, "the same toy is not sent again")
        #expect(same(iPad.keptToy, iPhone.keptToy))
    }

    /// The history is cleared while a save is unconfirmed: the play is sent, so its deletion is queued, and it leaves
    /// iCloud and every device.
    @Test(arguments: [true, false])
    func clearingWhileASaveIsUnconfirmed(answerLost: Bool) throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        if answerLost {
            iPhone.engine.choices.answerLost = 1
            iPhone.engine.choices.landsWhenAnswerLost = 1
            iPhone.engine.choices.resendsLostAnswers = false
        } else {
            iPhone.engine.choices.answerComesLate = 1
        }
        iPhone.finishPlay()
        iPhone.putDown()
        iPad.engineFetches()
        iPhone.engine.choices = StandInEngine.Choices()
        iPhone.clearHistory()
        world.settle()
        #expect(world.historyInICloud().plays.isEmpty)
        #expect(iPhone.history.plays.isEmpty && iPad.history.plays.isEmpty)
    }

    /// A purge, after which the zone is made again before another device fetched. CloudKit does not report the deletion of
    /// a zone that exists again, and its change tags start again (open point 13, as the probe saw it). By section 9 as the
    /// text stands, the device that was away never hears of the purge and keeps its copy, and the devices disagree. The
    /// rule for a deleted zone is to change; this records what the present one does.
    @Test func aPurgeAndAZoneMadeAgainBeforeAnotherDeviceFetched() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        world.cloud.deleteZone(World.zone, account: World.person, reason: .purged)
        iPhone.engineFetches()
        iPhone.pickUp(moves: 2)
        iPhone.finishPlay()
        world.settle()
        #expect(world.cloud.hasZone(World.zone, account: World.person), "the zone was made again")
        iPad.isOnline = true
        world.settle(answeringOffers: false)
        withKnownIssue("Section 9 is to change: a device that was away does not hear of a purge once the zone exists again") {
            #expect(iPad.history.plays.count == 1, "the purged play is gone, and the new one is here")
            #expect(world.disagreements().isEmpty)
        }
    }

    /// An engine with no state is told of a zone's earlier deletion while the zone does not exist (the probe). By section 9
    /// as the text stands, a device that joins then takes an old purge for its own and removes what it holds. The rule for
    /// a deleted zone is to change; this records what the present one does.
    @Test func aDeviceThatJoinsHearsOfAnEarlierPurge() throws {
        let world = World()
        _ = try twoSyncedDevices(world)
        world.cloud.deleteZone(World.zone, account: World.person, reason: .purged)
        world.settle()
        let mac = try world.device("Mac", kind: .Mac, account: nil)
        mac.move()
        mac.finishPlay()
        mac.signIn(to: World.person)
        mac.engineFetches()
        world.settle()
        withKnownIssue("Section 9 is to change: a device that joins takes an earlier purge for its own") {
            #expect(mac.history.plays.count == 1, "what was made on the Mac without iCloud goes into the account")
        }
    }

    /// A reset of encrypted data, followed by a device that was away while the others sent their copies again. That device
    /// does not hear of the reset once the zone exists again; its fetch brings the records sent again, and the devices
    /// agree. (Section 9 as the text stands; it is to change.)
    @Test func aResetFollowedByADeviceThatWasAway() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPad.finishPlay()
        world.cloud.deleteZone(World.zone, account: World.person, reason: .encryptedDataReset)
        iPhone.cameToFront()
        world.settle()
        iPad.isOnline = true
        world.settle(answeringOffers: false)
        #expect(world.disagreements().isEmpty)
        #expect(world.historyInICloud().plays.count == 2)
    }
}
