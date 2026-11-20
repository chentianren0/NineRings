import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// Every row of the table in docs/icloud.md section 17, as a test that reads like the row, with simulated devices against
/// the stand-in iCloud; and the orders of events that an earlier text of the design could not handle.
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

    /// Two devices that were played apart: the iPad offline, then the iPhone, which sends. The iPad is online again and
    /// has not synced.
    private func playApart(_ iPhone: SimulatedDevice, _ iPad: SimulatedDevice) {
        iPad.isOnline = false
        iPad.move(ring: 1)
        iPad.move(ring: 1)
        iPhone.move(ring: 1)
        iPhone.putDown()
        iPad.isOnline = true
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
        #expect(!device.engineSends() && device.engine.fetch(manual: true).error == .whole, "the engine is dormant")
        #expect(world.cloud.zoneNames(account: World.person).isEmpty)
    }

    /// A new device, and iCloud has data: the device joins when a report names the zone, and sends once the account is
    /// confirmed. The history fills in and the toy is taken up.
    @Test func aNewDeviceJoins() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        world.engineChoices.reportsSignInFromNothing = false
        let mac = try world.device("Mac", kind: .Mac)
        mac.accountQuestionFails = 1
        world.settle()
        #expect(mac.zoneNote == iPhone.zoneNote, "the report named the zone, and the Mac joined it")
        #expect(mac.history == iPhone.history && mac.history.plays.count == 1)
        #expect(same(mac.keptToy, iPhone.keptToy))
        mac.move()
        mac.finishPlay()
        world.settle()
        #expect(world.historyInICloud().plays.count == 1, "nothing is sent before the account is confirmed")
        mac.accountQuestionFails = 0
        world.settle()
        #expect(world.historyInICloud().plays.count == 2 && iPhone.history == mac.history)
        #expect(!mac.isOffered && world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// If the person played on the new device before the toy came in, they are asked.
    @Test func aNewDevicePlayedBeforeTheToyCameInAsks() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        world.engineChoices.reportsSignInFromNothing = false
        let mac = try world.device("Mac", kind: .Mac)
        mac.isOnline = false
        mac.move()
        mac.isOnline = true
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
        iPhone.pickUp(moves: 0)
        for _ in 0..<3 { iPhone.move() }
        #expect(!same(world.toyInICloud()?.toy, iPhone.keptToy), "the toy's moment has not come yet")
        iPhone.putDown()
        #expect(same(world.toyInICloud()?.toy, iPhone.keptToy), "leaving the front sent it")
        iPad.pickUp(moves: 0)
        #expect(same(iPad.keptToy, iPhone.keptToy))
        #expect(!iPad.isOffered && world.watcher.problems.isEmpty)
    }

    /// Two devices were played apart: the device that syncs second meets the other toy, through a fetch or a refused
    /// save, holds it, and shows the offer. Keep This One sends its toy again with the tag of the record it was shown, and
    /// the other device takes it up; Play That One shows the other play and sends nothing.
    @Test(arguments: [true, false], [true, false])
    func twoDevicesWerePlayedApart(throughAFetch: Bool, keepThisOne: Bool) throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        playApart(iPhone, iPad)
        if throughAFetch {
            iPad.cameToFront()
            iPad.syncFully()
        } else {
            iPad.toyChanged()
            iPad.engineSends()
            #expect(world.watcher.tally.counts["save refused as existing"] == 1)
        }
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
        playApart(iPhone, iPad)
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
        playApart(iPhone, iPad)
        iPad.putDown()
        iPad.answerOffer(keepThisOne: true)
        world.settle()
        let mac = try world.device("Mac", kind: .Mac)
        world.settle()
        #expect(same(mac.keptToy, world.toyInICloud()?.toy) && same(mac.keptToy, iPad.keptToy))
    }

    /// A device is restored from a backup, with the same account: the store and the engine state return as they were,
    /// the engine goes on from its tokens, and the toy is taken up, or the person is asked, by the usual rule.
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

    /// If the restored engine cannot go on, the next launch is a start from nothing, and CloudKit tells the device which
    /// of its plays are gone.
    @Test func aRestoredEngineThatCannotGoOnStartsFromNothing() throws {
        var choices = StandInICloud.Choices()
        choices.fetchFromNothingBringsOldDeletions = false
        let world = World(cloud: choices)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.finishPlay()
        iPad.putDown()
        world.settle()
        let backup = try iPhone.backUp()
        iPad.clearHistory()
        iPad.finishPlay()
        world.settle()
        try iPhone.restore(from: backup)
        iPhone.discardEngineState()
        world.settle()
        // The iPhone's own play's deletion comes with the fetch from nothing; the iPad's play is offered with its system
        // fields, and refused.
        #expect(world.watcher.tally.counts["save refused as unknown"] == 1, "the cleared play, offered with its system fields")
        #expect(iPhone.history == iPad.history && iPhone.history.plays.count == 1)
        #expect(world.disagreements().isEmpty)
    }

    /// A backup is restored on a device with another account: the engine reports a switch of account or a sign-in, and
    /// CloudKit names the account at launch. Either way the data is removed, and the device joins with nothing.
    @Test(arguments: ["a switch", "a sign-in", "nothing"])
    func aBackupIsRestoredUnderAnotherAccount(engineReports: String) throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let backup = try iPhone.backUp()
        switch engineReports {
        case "a sign-in":
            // The restored engine state names no account: the engine reports the account it finds as a sign-in.
            let notes = try #require(try backup.mainContext.fetch(FetchDescriptor<SyncNotes>()).first)
            var state = try JSONDecoder().decode(StandInEngine.State.self, from: try #require(notes.engineState))
            state.account = nil
            notes.engineState = try JSONEncoder().encode(state)
            try backup.mainContext.save()
        case "nothing":
            world.engineChoices.reportsChangeWhileNotRunning = false
        default:
            break
        }
        let theirs = try world.device("Another person's iPhone", account: World.other, from: backup)
        world.settle()
        #expect(theirs.history.plays.isEmpty)
        #expect(theirs.keptToy?.isUntouched == true)
        for zone in world.cloud.zoneNames(account: World.other) {
            #expect(world.cloud.records(zone: zone, account: World.other).isEmpty, "nothing of one person goes into another's iCloud")
        }
        #expect(world.watcher.problems.isEmpty)
    }

    /// Another account was signed in while the app was not running: at launch CloudKit names that account. It differs
    /// from the store's note, so the data is removed before anything is sent, and none of it reaches the other account's
    /// iCloud.
    @Test(arguments: [true, false])
    func anotherAccountWasSignedInWhileTheAppWasNotRunning(engineReportsFirst: Bool) throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        iPhone.move()
        iPhone.finishPlay()
        iPhone.engineChoices.accountReportComesFirst = engineReportsFirst
        iPhone.signInWhileNotRunning(to: World.other)
        world.settle()
        #expect(iPhone.history.plays.isEmpty && iPhone.keptToy?.isUntouched == true)
        #expect(iPhone.notedAccount == World.other)
        for zone in world.cloud.zoneNames(account: World.other) {
            #expect(world.cloud.records(zone: zone, account: World.other).isEmpty)
        }
        #expect(world.watcher.problems.isEmpty)
    }

    /// The same, when the engine does not report the change, as for a state restored from a backup (open point 4): the
    /// gate stays shut until CloudKit has named the account, even when the app fetches and the engine sends first.
    @Test func anotherAccountUnreportedByTheEngineIsConfirmedBeforeAnythingIsSent() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        iPhone.move()
        iPhone.finishPlay()
        iPhone.engineChoices.reportsChangeWhileNotRunning = false
        iPhone.signInWhileNotRunning(to: World.other)
        iPhone.requestFetch()
        iPhone.toyChanged()
        iPhone.engineSends()
        iPhone.requestFetch()
        iPhone.engineSends()
        for zone in world.cloud.zoneNames(account: World.other) {
            #expect(world.cloud.records(zone: zone, account: World.other).isEmpty, "nothing before the account is confirmed")
        }
        iPhone.answerAccountQuestion()
        #expect(iPhone.history.plays.isEmpty && iPhone.keptToy?.isUntouched == true)
        world.settle()
        #expect(world.watcher.problems.isEmpty)
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
    @Test(arguments: [true, false])
    func aSignOutKeepsTheData(reported: Bool) throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let before = iPhone.history.plays.count
        if reported {
            iPhone.signIn(to: nil)
        } else {
            // iCloud turned off for the app: the engine goes dormant without a report, and CloudKit names no account.
            iPhone.engineChoices.reportsChangeWhileNotRunning = false
            iPhone.signInWhileNotRunning(to: nil)
        }
        iPhone.move()
        iPhone.finishPlay()
        world.settle()
        #expect(iPhone.history.plays.count == before + 1)
        let zone = try #require(world.cloud.zoneNames(account: World.person).first)
        #expect(world.historyInICloud(zone: zone).plays.count == before)
        #expect(iPhone.hasMarks)
        #expect(reported ? iPhone.zoneNote == nil : iPhone.zoneNote?.knowledge == .existing, "a sign-out empties the zone note")
    }

    /// The same account returns: the device joins, the histories unite, plays cleared meanwhile are removed, and the toy's
    /// rule decides.
    @Test func theSameAccountReturns() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.finishPlay()
        iPad.putDown()
        world.settle()
        let cleared = Set(iPad.history.plays.map(\.playID))
        iPhone.signIn(to: nil)
        // The iPhone finishes the play in progress on both devices, then one of its own. The iPad clears the history,
        // and finishes the same play in progress.
        iPhone.finishPlay()
        iPhone.finishPlay()
        iPhone.move()
        iPad.clearHistory()
        iPad.pickUp(moves: 1)
        iPad.finishPlay()
        iPad.putDown()
        world.settle()
        iPhone.signIn(to: World.person)
        world.settle()
        #expect(iPhone.history == iPad.history && iPhone.history.plays.count == 2, "the histories united")
        #expect(cleared.isDisjoint(with: iPhone.history.plays.map(\.playID)), "the plays cleared meanwhile are removed")
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
        #expect(world.historyInICloud(account: World.other, zone: theirs.zoneNote?.zone.name).plays.count == 2, "nothing of the first account went into the other's")
        #expect(world.watcher.problems.isEmpty)
    }

    /// The iCloud storage is full: saves are refused. The data stays, marked as not received, and goes out again at the
    /// next launch or return to the front. A line says so until a save is accepted again.
    @Test func theStorageIsFull() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        world.cloud.database(World.person).isFull = true
        iPhone.finishPlay()
        iPhone.putDown()
        #expect(iPhone.sync.storageIsFull && iPhone.hasMarks)
        iPhone.finishPlay()
        iPhone.toyChanged()
        #expect(iPhone.engine.state.pending.isEmpty, "nothing is queued again in a loop")
        #expect(world.historyInICloud().plays.count == 1)
        world.cloud.database(World.person).isFull = false
        iPhone.cameToFront()
        iPhone.syncFully()
        #expect(!iPhone.sync.storageIsFull && !iPhone.hasMarks)
        #expect(world.historyInICloud().plays.count == 3)
    }

    /// The device is offline: the engine waits, and the store keeps the marks. Nothing is sent in a run before a fetch
    /// has finished.
    @Test func theDeviceIsOffline() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.isOnline = false
        iPhone.finishPlay()
        iPhone.putDown()
        iPhone.relaunch()
        #expect(iPhone.hasMarks && iPad.history.plays.count == 1)
        iPhone.isOnline = true
        iPhone.answerAccountQuestion()
        iPhone.toyChanged()
        iPhone.engineSends()
        #expect(world.historyInICloud().plays.count == 1, "the account is confirmed, and no fetch has finished in this run")
        #expect(iPhone.engine.state.pending.isEmpty, "the engine's pending saves were withdrawn as it asked for them")
        iPhone.requestFetch()
        #expect(!iPhone.engine.state.pending.isEmpty, "the fetch counted, and the gate opened")
        world.settle()
        #expect(iPad.history == iPhone.history && iPad.history.plays.count == 2)
    }

    /// The person deletes the app's data from iCloud in Settings: every device for which the deletion counts removes the
    /// history and puts the toy back to its start. What was removed is never sent again. When the person plays again,
    /// the devices go on in the next zone.
    @Test(arguments: [true, false])
    func theAppsDataIsDeletedFromICloud(reportedAsADeletion: Bool) throws {
        var choices = StandInICloud.Choices()
        choices.lossesReportedAsDeletions = reportedAsADeletion
        let world = World(cloud: choices)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let first = try #require(iPhone.zoneNote?.zone)
        world.cloud.deleteEveryZone(account: World.person, reason: .purged)
        world.settle()
        for device in [iPhone, iPad] {
            #expect(device.history.plays.isEmpty)
            #expect(device.keptToy?.isUntouched == true)
            #expect(device.zoneNote?.knowledge == .deleted)
        }
        #expect(world.cloud.zoneNames(account: World.person).isEmpty, "nothing is sent again")
        iPhone.pickUp(moves: 2)
        iPhone.putDown()
        world.settle()
        #expect(iPhone.zoneNote?.zone.number == first.number + 1 && iPad.zoneNote == iPhone.zoneNote)
        #expect(same(iPad.keptToy, iPhone.keptToy))
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// The person resets their encrypted data: every device for which the deletion counts, whether it is reported or met
    /// as an error, keeps its data, leaves the zone and goes on in the next zone, so that its copy goes to iCloud again.
    /// The first toy to arrive there becomes the record, and a device with a different toy shows the offer.
    @Test(arguments: [true, false])
    func theEncryptedDataIsReset(reportedAsADeletion: Bool) throws {
        var choices = StandInICloud.Choices()
        choices.lossesReportedAsDeletions = reportedAsADeletion
        let world = World(cloud: choices)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let first = try #require(iPhone.zoneNote?.zone)
        iPad.isOnline = false
        iPad.move()
        let plays = iPhone.history
        world.cloud.deleteEveryZone(account: World.person, reason: .encryptedDataReset)
        world.settle()
        iPad.isOnline = true
        world.settle()
        #expect(iPhone.zoneNote?.zone.number == first.number + 1 && iPad.zoneNote == iPhone.zoneNote)
        #expect(world.historyInICloud() == plays && iPad.history == plays && iPhone.history == plays)
        #expect(same(world.toyInICloud()?.toy, iPhone.keptToy))
        #expect(iPad.isOffered)
        #expect(world.watcher.problems.isEmpty)
    }

    /// A device was asleep while the app's data was deleted from iCloud, and another device played on: when it wakes, it
    /// is told of the deletion, removes its data, and joins the new zone.
    @Test func aDeviceAsleepThroughAPurgeWakes() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPad.finishPlay()
        world.cloud.deleteEveryZone(account: World.person, reason: .purged)
        iPhone.pickUp(moves: 2)
        iPhone.finishPlay()
        iPhone.putDown()
        world.settle()
        iPad.isOnline = true
        world.settle(answeringOffers: false)
        #expect(iPad.zoneNote == iPhone.zoneNote && iPad.history == iPhone.history && iPad.history.plays.count == 1)
        #expect(same(iPad.keptToy, iPhone.keptToy))
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// A device joins for the first time after an old deletion: it is told of the old deletion, and keeps what it holds:
    /// it has no zone note.
    @Test func aDeviceJoinsForTheFirstTimeAfterAnOldDeletion() throws {
        let world = World()
        _ = try twoSyncedDevices(world)
        let old = try #require(world.personsZone)
        world.cloud.deleteEveryZone(account: World.person, reason: .purged)
        world.settle()
        let mac = try world.device("Mac", kind: .Mac, account: nil)
        mac.move()
        mac.finishPlay()
        mac.signIn(to: World.person)
        world.settle()
        #expect(mac.zonesToldDeleted.contains(old), "it is told of the old deletion")
        #expect(mac.history.plays.count == 1, "what was made on the Mac without iCloud goes into the account")
        #expect(world.historyInICloud().plays.count == 1 && world.disagreements().isEmpty)
    }

    /// A device was away while its zone was reset and the next one was purged: it removes its data. Both deletions count
    /// for it, and one of them is a purge.
    @Test func aDeviceAwayThroughAResetAndAPurge() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        world.cloud.deleteEveryZone(account: World.person, reason: .encryptedDataReset)
        iPhone.pickUp(moves: 1)
        iPhone.putDown()
        world.settle()
        #expect(iPhone.zoneNote?.zone.number == 2)
        world.cloud.deleteEveryZone(account: World.person, reason: .purged)
        iPad.isOnline = true
        world.settle()
        #expect(iPad.history.plays.isEmpty && iPad.keptToy?.isUntouched == true)
        #expect(iPad.zoneNote?.zone.number == 2 && iPad.zoneNote?.knowledge == .deleted, "the highest that counts is the note's zone")
    }

    /// Two devices create the next zone at the same time: there are two zones with one number. The device in the lower
    /// one joins the higher one and brings everything, and the lower zone is left behind.
    @Test func twoDevicesCreateTheNextZoneAtTheSameTime() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        world.cloud.deleteEveryZone(account: World.person, reason: .purged)
        world.settle()
        iPhone.move()
        iPhone.finishPlay()
        iPad.move()
        iPad.finishPlay()
        iPhone.toyChanged()
        iPad.toyChanged()
        let created = [iPhone, iPad].compactMap(\.zoneNote).map(\.zone)
        #expect(created.count == 2 && created[0] != created[1] && created[0].number == created[1].number)
        iPhone.engineSends()
        iPad.engineSends()
        world.settle(answeringOffers: true)
        #expect(world.cloud.zoneNames(account: World.person).count == 2, "the lower zone is left behind")
        #expect(iPhone.zoneNote?.zone == created.max() && iPad.zoneNote?.zone == created.max())
        #expect(iPhone.history.plays.count == 2 && iPad.history == iPhone.history)
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// A toy written with broken content arrives: it becomes the base through its system fields, and the toy here goes out
    /// over it.
    @Test func aToyWithBrokenContentArrives() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let zone = try #require(world.personsZone)
        let base = try #require(world.cloud.record(.toy(in: zone), account: World.person))
        let broken = RecordToSend(type: CloudRecord.toyType, zone: zone, name: CloudRecord.toyName, systemFields: base.systemFields, format: 1, payload: Data("{".utf8))
        _ = world.cloud.save(broken, account: World.person, device: nil)
        let saved = try #require(world.cloud.record(.toy(in: zone), account: World.person))
        let mine = iPhone.keptToy
        iPhone.cameToFront()
        iPhone.requestFetch()
        let side = iPhone.toySide
        #expect(side.base?.systemFields == saved.systemFields && side.base?.stamps == [], "the base, through its system fields alone")
        #expect(side.isChanged && side.held == nil)
        iPhone.putDown()
        world.settle()
        #expect(same(world.toyInICloud()?.toy, mine), "the toy here went out over the broken one")
        #expect(same(iPad.keptToy, mine) && world.disagreements().isEmpty)
    }

    /// The history is cleared while another device is offline: the other device removes those plays when it syncs. Plays
    /// it finished meanwhile stay.
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

    /// The history is cleared while another device is signed out, or put away for months: when that device comes back to
    /// the same zone, it offers its plays with their system fields. CloudKit refuses the cleared ones as unknown, and the
    /// device removes them.
    @Test(arguments: [true, false])
    func theHistoryIsClearedWhileAnotherDeviceIsAway(signedOut: Bool) throws {
        var choices = StandInICloud.Choices()
        choices.fetchFromNothingBringsOldDeletions = false
        let world = World(cloud: choices)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.finishPlay()
        world.settle()
        if signedOut { iPad.signIn(to: nil) } else { iPad.isOnline = false }
        iPhone.clearHistory()
        world.settle()
        if signedOut {
            iPad.signIn(to: World.person)
        } else {
            // Months later, CloudKit no longer delivers the deletions, and the engine fetches again from nothing.
            iPad.isOnline = true
            iPad.discardEngineState()
        }
        world.settle()
        #expect(world.watcher.tally.counts["save refused as unknown"] == 2)
        #expect(iPad.history.plays.isEmpty && iPhone.history.plays.isEmpty && world.disagreements().isEmpty)
    }

    /// The app is closed between a held toy and the person's answer: the toy stays held. Nothing is sent at the next
    /// launch, and the offer shows again.
    @Test func theAppIsClosedWhileAToyIsHeld() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        playApart(iPhone, iPad)
        iPad.putDown()
        #expect(iPad.isOffered)
        iPad.relaunch()
        #expect(iPad.isOffered)
        world.settle()
        let zone = try #require(world.personsZone)
        #expect(!iPad.engine.state.pending.contains(.save(.toy(in: zone))), "nothing is sent")
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

    /// The app crashes between a change and its sending: the store's marks queue the change again once the next launch
    /// has confirmed the account and its fetch has finished.
    @Test func theAppCrashesBeforeSending() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.finishPlay()
        iPhone.move()
        iPhone.relaunch()
        #expect(iPhone.engine.state.pending.isEmpty)
        iPhone.syncFully()
        #expect(world.historyInICloud().plays.count == 2)
        world.settle()
        #expect(iPad.history == iPhone.history && iPad.history.plays.count == 2)
        #expect(same(iPad.keptToy, iPhone.keptToy))
    }

    /// Writing fetched changes fails: the device syncs nothing more in that run, and the next launch fetches the same
    /// changes again.
    @Test func writingFetchedChangesFails() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.finishPlay()
        iPad.putDown()
        let iPadsPlay = try #require(iPad.history.plays.first)
        iPhone.expectsAFailedWrite = true
        iPhone.sync.store.failsNextSyncSave = true
        iPhone.cameToFront()
        iPhone.requestFetch()
        #expect(iPhone.sync.run.writeFailed && !iPhone.history.plays.contains(iPadsPlay), "the write failed, and nothing was kept")
        iPhone.finishPlay()
        iPhone.move()
        iPhone.toyChanged()
        iPhone.leftFront()
        iPhone.engineSends()
        iPhone.requestFetch()
        iPhone.engineSends()
        #expect(iPhone.engine.state.pending.isEmpty, "nothing is queued for the rest of the run")
        #expect(world.historyInICloud().plays.count == 2, "and nothing is handed over")
        #expect(!iPhone.history.plays.contains(iPadsPlay), "nothing more is applied")
        iPhone.relaunch()
        world.settle(answeringOffers: false)
        #expect(iPhone.history.plays.contains(iPadsPlay), "the next launch fetched the same changes again")
        #expect(iPhone.history == iPad.history)
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// The answer to a save is lost: the record's stamp shows the device that the record in iCloud is its own. A finished
    /// play stays sent, so clearing still reaches it.
    @Test func theAnswerToASaveIsLost() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerLost = 1
        iPhone.engine.choices.landsWhenAnswerLost = 1
        iPhone.engine.choices.resendsLostAnswers = false
        iPhone.move()
        iPhone.finishPlay()
        iPhone.putDown()
        iPhone.engine.choices.answerLost = 0
        let lost = try #require(iPhone.history.plays.first)
        #expect(try iPhone.sync.store.plays([lost.playID])[lost.playID]?.sync == .sent)
        iPad.pickUp(moves: 0)
        #expect(iPad.history.plays.contains(lost), "the save landed, and another device shows the play")
        iPhone.clearHistory()
        world.settle()
        #expect(world.historyInICloud().plays.isEmpty && iPad.history.plays.isEmpty, "clearing reached the play that is sent")
        iPhone.toyChanged()
        iPhone.syncFully()
        #expect(!iPhone.toySide.isChanged && !iPhone.isOffered, "its own toy, recognised by its stamp")
    }

    /// A save lands, its answer is lost, and the person plays on elsewhere: the first device finds its own stamp among
    /// the arriving toy's earlier stamps and takes the toy up.
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
        #expect(world.watcher.tally.counts["toy held to take up although marked (case 6)"] == 1)
        #expect(!iPhone.isOffered && same(iPhone.keptToy, iPad.keptToy))
        #expect(world.watcher.problems.isEmpty)
    }

    /// An answer or a record arrives out of order: a version older than the one the device holds changes nothing. The
    /// base never goes back.
    @Test func anAnswerArrivesOutOfOrder() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerComesLate = 1
        iPhone.move()
        iPhone.putDown()
        iPhone.engine.choices.answerComesLate = 0
        iPad.pickUp(moves: 1)
        iPad.putDown()
        iPhone.cameToFront()
        iPhone.requestFetch()
        let newer = iPhone.toySide.held?.record.changeTag ?? iPhone.toySide.base?.changeTag
        #expect(newer == world.toyInICloud().flatMap { _ in world.cloud.record(.toy(in: world.personsZone!), account: World.person)?.changeTag })
        iPhone.calmMoment()
        let base = iPhone.toySide.base
        iPhone.deliverLateAnswers()
        #expect(iPhone.toySide.base == base, "the late answer is an earlier version, and the base stays")
        world.settle()
        #expect(same(iPhone.keptToy, iPad.keptToy) && world.disagreements().isEmpty)
    }

    /// A play's save lands after the play was cleared, here or on another device: the play stays cleared, and its deletion
    /// is sent.
    @Test(arguments: [true, false])
    func aPlaysSaveLandsAfterItWasCleared(here: Bool) throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerComesLate = 1
        iPhone.finishPlay()
        iPhone.putDown()
        iPhone.engine.choices.answerComesLate = 0
        if here {
            iPhone.clearHistory()
        } else {
            iPad.pickUp(moves: 0)
            iPad.clearHistory()
            iPad.putDown()
            iPhone.cameToFront()
            iPhone.requestFetch()
        }
        iPhone.deliverLateAnswers()
        world.settle()
        #expect(world.historyInICloud().plays.isEmpty && iPhone.history.plays.isEmpty && iPad.history.plays.isEmpty)
        #expect(world.disagreements().isEmpty)
    }

    /// An older version meets a newer format: a finished play is counted and not shown, and a toy is neither taken up nor
    /// replaced.
    @Test func anOlderVersionMeetsANewerFormat() throws {
        let world = World()
        let (iPhone, _) = try twoSyncedDevices(world)
        let zone = try #require(world.personsZone)
        let base = try #require(world.cloud.record(.toy(in: zone), account: World.person))
        let newer = Data(#"{"aLaterShape":true}"#.utf8)
        _ = world.cloud.save(RecordToSend(type: CloudRecord.toyType, zone: zone, name: CloudRecord.toyName, systemFields: base.systemFields, format: 2, payload: newer), account: World.person, device: nil)
        _ = world.cloud.save(RecordToSend(type: CloudRecord.finishedPlayType, zone: zone, name: UUID().uuidString, systemFields: nil, format: 2, payload: newer), account: World.person, device: nil)
        iPhone.pickUp(moves: 1)
        let mine = iPhone.keptToy
        iPhone.putDown()
        world.settle()
        #expect(iPhone.history.unreadable == 1 && iPhone.history.plays.count == 1)
        #expect(try iPhone.sync.heldToy()?.kind == .needsNewerVersion)
        #expect(same(iPhone.keptToy, mine), "the toy here is neither taken up nor replaced by the one it cannot read")
        #expect(world.cloud.record(.toy(in: zone), account: World.person)?.format == 2, "and this device sends no toy")
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

    /// A purge, after which another device plays on in the next zone before the device that was away fetched. The first
    /// text kept one zone name: CloudKit does not report the deletion of a zone that exists again, so the device that was
    /// away never heard of the purge. Under a new name, it does.
    @Test func aPurgeAndTheNextZoneBeforeAnotherDeviceFetched() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        world.cloud.deleteEveryZone(account: World.person, reason: .purged)
        iPhone.pickUp(moves: 2)
        iPhone.finishPlay()
        world.settle()
        #expect(!world.cloud.zoneNames(account: World.person).isEmpty, "the next zone exists")
        iPad.isOnline = true
        world.settle(answeringOffers: false)
        #expect(iPad.history.plays.count == 1, "the purged play is gone, and the new one is here")
        #expect(world.disagreements().isEmpty)
    }

    /// A device's own save is fetched before its answer comes: it is its own toy, and nothing is sent again.
    @Test func anOwnSaveFetchedBeforeItsAnswer() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPhone.engine.choices.answerComesLate = 1
        iPhone.move()
        iPhone.putDown()
        iPhone.engine.choices.answerComesLate = 0
        let sentBefore = iPhone.engine.changesSent
        iPhone.requestFetch()
        world.settle()
        #expect(!iPhone.isOffered && !iPad.isOffered)
        #expect(iPhone.engine.changesSent == sentBefore, "the same toy is not sent again")
        #expect(same(iPad.keptToy, iPhone.keptToy))
    }

    /// A play refused as existing without iCloud's record, whose record no fetch brings, is in iCloud without system
    /// fields; when the device moves to another zone, it is taken along like every other play (section 9, leaving a
    /// zone, step 3).
    @Test func aPlayInICloudWithoutSystemFieldsIsTakenAlong() throws {
        var choices = StandInICloud.Choices()
        choices.refusalCarriesRecord = false
        choices.ownChangesComeBack = 0
        choices.reportsOwnZoneChanges = false
        let world = World(cloud: choices)
        let (iPhone, iPad) = try twoSyncedDevices(world)
        iPad.isOnline = false
        iPhone.engine.choices.answerLost = 1
        iPhone.engine.choices.landsWhenAnswerLost = 1
        iPhone.engine.choices.resendsLostAnswers = false
        iPhone.finishPlay()
        iPhone.putDown()
        iPhone.engine.choices.answerLost = 0
        let play = try #require(iPhone.history.plays.first)
        iPhone.toyChanged()
        iPhone.syncFully()
        #expect(try iPhone.sync.store.plays([play.playID])[play.playID].map { ($0.sync, $0.systemFields) } ?? (.unsent, nil) == (.inICloud, nil))
        world.cloud.deleteEveryZone(account: World.person, reason: .encryptedDataReset)
        world.settle(answeringOffers: false)
        iPad.isOnline = true
        world.settle(answeringOffers: false)
        #expect(iPad.history.plays.contains(play) && world.historyInICloud().plays.contains(play))
        #expect(world.disagreements().isEmpty)
    }

    /// The person signs out with the app running, and back in while it is not: at the next launch the engine reports the
    /// sign-in, before or after its first report of the zones (open point 14). Either way the device goes on in its zone,
    /// and no device moves to a new one.
    @Test(arguments: [true, false])
    func aSignInReportedInEitherOrder(accountReportComesFirst: Bool) throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let zone = try #require(world.personsZone)
        iPhone.signIn(to: nil)
        iPhone.engineChoices.accountReportComesFirst = accountReportComesFirst
        iPhone.signInWhileNotRunning(to: World.person)
        world.settle()
        #expect(world.watcher.tally.counts["engine reported a sign-in"] ?? 0 > 0)
        #expect(world.cloud.zoneNames(account: World.person) == [zone], "no device moved to a new zone")
        #expect(iPhone.zoneNote?.zone.name == zone && iPad.zoneNote?.zone.name == zone)
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }

    /// A zone found missing, with no report of its deletion: the device gives it up, keeping its data, and the devices go
    /// on in the next zone.
    @Test func aZoneFoundMissing() throws {
        let world = World()
        let (iPhone, iPad) = try twoSyncedDevices(world)
        let first = try #require(world.personsZone)
        world.cloud.loseZoneSilently(first, account: World.person)
        iPhone.finishPlay()
        iPhone.putDown()
        world.settle(answeringOffers: false)
        #expect(world.watcher.tally.counts["save found the zone gone"] ?? 0 > 0)
        #expect(iPhone.zoneNote?.zone.number == 2 && iPad.zoneNote == iPhone.zoneNote)
        #expect(iPhone.history.plays.count == 2 && iPad.history == iPhone.history)
        #expect(world.watcher.problems.isEmpty && world.disagreements().isEmpty)
    }
}
