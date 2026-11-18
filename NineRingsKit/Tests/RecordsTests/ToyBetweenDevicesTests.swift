import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// The toy between installations of the app: which toy is the later, told by what each was made knowing, and the three
/// cases that follow. Each installation has its own device's store; one stand-in for the iCloud store plays the part of
/// every device's iCloud store once sync has brought each record there. An installation's toy reaches it only when that
/// installation writes it there.
@MainActor
@Suite struct ToyBetweenDevicesTests {
    private let cloud: RecordStore

    init() throws {
        cloud = RecordStore(container: try RecordStore.cloudContainer(in: .memory, environment: .development))
    }

    /// One installation of the app: its device's store, and its toy as the screen plays it.
    @MainActor
    final class Installation {
        let id: String
        let store: RecordStore
        var play = PlayState()
        /// The clock of this device: only `changedAt` reads it.
        var now = Date(timeIntervalSince1970: 1_000)

        init(_ id: String) throws {
            self.id = id
            store = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
            try keep()
        }

        /// Keeps the toy in the device's store, as the app does whenever it comes to rest.
        func keep() throws {
            try store.keep(play.snapshot, installation: id, appVersion: "1.4", at: now)
        }

        /// Moves `rings` one after another and keeps the toy, a minute later on this device's clock.
        func move(_ rings: Int...) throws {
            for ring in rings {
                play.tap(ring)
                while play.toy.isPlaying { play.advance(by: 10) }
            }
            now += 60
            try keep()
        }

        /// Writes the toy to the iCloud store, as the app does at calm moments.
        @discardableResult
        func send(to cloud: RecordStore) throws -> Bool {
            try cloud.copyToy(of: id, from: store)
        }

        var lineage: Lineage { get throws { try store.lineage(installation: id) } }

        /// What it makes of the other installations' toys in the iCloud store.
        func look(at cloud: RecordStore) throws -> ToyDecision {
            ToyDecision(mine: try lineage, others: try cloud.otherToys(than: id))
        }

        /// Looks at the iCloud store and takes up a later toy by itself, as the app does at a calm moment. Returns the
        /// toy offered, the play having parted, if any.
        @discardableResult
        func follow(_ cloud: RecordStore) throws -> OtherToy? {
            let decision = try look(at: cloud)
            if let later = decision.takeUp { try takeUp(later, lineage: decision.lineage) }
            return decision.offer
        }

        func takeUp(_ other: OtherToy, lineage: Lineage? = nil) throws {
            let lineage = try lineage ?? self.lineage.takingUp(other.lineage)
            try store.takeUp(other, lineage: lineage, installation: id, appVersion: "1.4")
            play.takeUp(other.snapshot)
            try keep()
        }

        func keepOwn(over other: OtherToy) throws {
            try store.keepOwnToy(over: other, installation: id)
        }

        var state: PuzzleState { play.own.state }
    }

    private let start = PuzzleState.allOn

    // MARK: The lineage

    @Test func aToyNobodyChangedIsKnownToEveryToy() {
        let untouched = Lineage()
        let changed = Lineage().changed(by: "A")
        #expect(changed.knows(untouched))
        #expect(untouched.knows(untouched))
        #expect(!untouched.knows(changed))
        #expect(untouched.compare(with: changed) == .otherIsLater)
        #expect(changed.compare(with: untouched) == .thisIsLater)
        #expect(untouched.compare(with: Lineage()) == .same)
    }

    @Test func aChangeIsKnownToTheChangesMadeAfterIt() {
        let first = Lineage().changed(by: "A")
        let second = first.changed(by: "A")
        #expect(second.head == Lineage.Change(installation: "A", count: 2))
        #expect(second.knows(first) && !first.knows(second))
        #expect(first.compare(with: second) == .otherIsLater)
        #expect(second.compare(with: first) == .thisIsLater)
    }

    @Test func twoChangesMadeApartHaveParted() {
        let base = Lineage().changed(by: "A")
        let a = base.changed(by: "A")
        let b = base.changed(by: "B")
        #expect(a.compare(with: b) == .parted)
        #expect(b.compare(with: a) == .parted)
    }

    /// Taking up makes the two toys the same toy, and knows all either knew.
    @Test func takingUpMakesTheSameToy() {
        let base = Lineage().changed(by: "A")
        let a = base.changed(by: "A")
        let b = base.changed(by: "B").changed(by: "B")
        let taken = a.takingUp(b)
        #expect(taken.compare(with: b) == .same)
        #expect(taken.knows(a) && taken.knows(b))
        #expect(taken.knows == ["A": 2, "B": 2])
    }

    /// Keeping one's own toy is a change made knowing the other, so the other follows it.
    @Test func keepingIsAChangeTheOtherFollows() {
        let base = Lineage().changed(by: "A")
        let a = base.changed(by: "A")
        let b = base.changed(by: "B")
        let kept = a.keeping(over: b, by: "A")
        #expect(kept.head == Lineage.Change(installation: "A", count: 3))
        #expect(b.compare(with: kept) == .otherIsLater)
        #expect(kept.compare(with: b) == .thisIsLater)
    }

    /// An installation's count never goes back, even after it takes up another's toy, so a change is never named twice.
    @Test func aChangeIsNeverNamedTwice() {
        let a = Lineage().changed(by: "A").changed(by: "A").changed(by: "A")
        let b = Lineage().changed(by: "B")
        let next = a.takingUp(b).changed(by: "A")
        #expect(next.head == Lineage.Change(installation: "A", count: 4))
    }

    @Test func aLineageIsKeptAsJSON() throws {
        let lineage = Lineage().changed(by: "A").takingUp(Lineage().changed(by: "B")).changed(by: "A")
        #expect(Lineage(data: try lineage.encoded()) == lineage)
        #expect(Lineage(data: Data()) == Lineage(), "a toy saved before lineages: nobody changed it")
        #expect(Lineage(data: Data("not a lineage".utf8)) == nil)
    }

    // MARK: The device's own toy

    /// A change of the toy is a change of the installation; time spent looking at it is not.
    @Test func onlyAChangeOfTheToyCountsInItsLineage() throws {
        let a = try Installation("A")
        #expect(try a.lineage == Lineage(), "nobody has touched the first toy")
        try a.move(1)
        #expect(try a.lineage.head == Lineage.Change(installation: "A", count: 1))
        a.play.spend(30)
        try a.keep()
        #expect(try a.lineage.head == Lineage.Change(installation: "A", count: 1))
        try a.move(3)
        #expect(try a.lineage.head == Lineage.Change(installation: "A", count: 2))
    }

    /// The first toy kept is a change unless nobody has touched it.
    @Test func aFirstToyKeptWithMovesIsAChange() throws {
        let store = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
        var play = PlayState()
        play.tap(1)
        while play.toy.isPlaying { play.advance(by: 10) }
        try store.keep(play.snapshot, installation: "A", appVersion: "1.4")
        #expect(try store.lineage(installation: "A").head == Lineage.Change(installation: "A", count: 1))
    }

    // MARK: Two installations

    /// The other toy was made knowing this one: it is the later, and replaces this one by itself. A toy nobody has
    /// changed is known to every other, so a new device takes up the play.
    @Test func aLaterToyReplacesThisOneByItself() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        try mac.move(1, 3, 1)
        try mac.send(to: cloud)
        try iPad.send(to: cloud)

        let decision = try iPad.look(at: cloud)
        #expect(decision.takeUp?.installation == "A")
        #expect(decision.offer == nil)
        try iPad.follow(cloud)
        #expect(iPad.state == mac.state)
        #expect(iPad.play.snapshot.isSameToy(as: mac.play.snapshot))

        // The two now have the same toy: nothing more happens on either side.
        try iPad.send(to: cloud)
        let onMac = try mac.look(at: cloud)
        #expect(onMac.takeUp == nil && onMac.offer == nil)
        #expect(mac.state == start.moving(1).moving(3).moving(1))
        #expect(try iPad.look(at: cloud).takeUp == nil)
    }

    /// This toy was made knowing the other: nothing happens here, and the other follows.
    @Test func anEarlierToyChangesNothing() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        try mac.move(1)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        try iPad.move(3)
        try iPad.send(to: cloud)

        let onIPad = try iPad.look(at: cloud)
        #expect(onIPad.takeUp == nil && onIPad.offer == nil)
        try mac.follow(cloud)
        #expect(mac.state == start.moving(1).moving(3))
    }

    /// Neither was made knowing the other: the play has parted in two. Nothing is replaced on either device, and each
    /// offers the other's play. While the person does neither, the offer stays and both toys stay.
    @Test func aPlayPartedInTwoReplacesNothingAndIsOffered() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        try mac.move(1)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        // Each moves on before the other's toy arrives.
        try mac.move(3)
        try iPad.move(1)
        try mac.send(to: cloud)
        try iPad.send(to: cloud)

        for _ in 0..<2 {
            #expect(try mac.follow(cloud)?.installation == "B")
            #expect(try iPad.follow(cloud)?.installation == "A")
        }
        #expect(mac.state == start.moving(1).moving(3))
        #expect(iPad.state == .allOn)

        // A move made while the offer shows does not make the toy know the other: the play is still parted.
        try iPad.move(1)
        try iPad.send(to: cloud)
        #expect(try mac.follow(cloud)?.installation == "B")
        #expect(mac.state == start.moving(1).moving(3))
    }

    /// Keeping one's own play is remembered, so that the other device then follows by itself.
    @Test func keepingOnesOwnPlayLeadsTheOtherToFollow() throws {
        let (mac, iPad) = try parted()
        let offered = try #require(try mac.follow(cloud))
        try mac.keepOwn(over: offered)
        #expect(try mac.follow(cloud) == nil, "kept: no more offer")
        try mac.send(to: cloud)

        let onIPad = try iPad.look(at: cloud)
        #expect(onIPad.takeUp?.installation == "A" && onIPad.offer == nil)
        try iPad.follow(cloud)
        #expect(iPad.state == mac.state)
        try iPad.send(to: cloud)
        #expect(try mac.look(at: cloud).takeUp == nil)
    }

    /// Taking up the other play makes the two the same toy: neither offers anything more.
    @Test func takingUpTheOtherPlayEndsTheOffer() throws {
        let (mac, iPad) = try parted()
        let offered = try #require(try mac.follow(cloud))
        try mac.takeUp(offered)
        #expect(mac.state == iPad.state)
        try mac.send(to: cloud)
        let onMac = try mac.look(at: cloud)
        let onIPad = try iPad.look(at: cloud)
        #expect(onMac.takeUp == nil && onMac.offer == nil)
        #expect(onIPad.takeUp == nil && onIPad.offer == nil)
    }

    /// The person keeps their own play on both devices at once, before either hears of the other: each keeping is a new
    /// change, so the play is offered again on both, and whichever they settle first, the other follows.
    @Test func keepingOnBothDevicesAtOnceOffersAgain() throws {
        let (mac, iPad) = try parted()
        let onMac = try #require(try mac.follow(cloud))
        let onIPad = try #require(try iPad.follow(cloud))
        try mac.keepOwn(over: onMac)
        try iPad.keepOwn(over: onIPad)
        try mac.send(to: cloud)
        try iPad.send(to: cloud)
        let again = try #require(try mac.follow(cloud))
        #expect(try iPad.follow(cloud)?.installation == "A")
        try mac.keepOwn(over: again)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        #expect(iPad.state == mac.state)
    }

    /// Time spent looking at a toy does not make it later: two devices with the same toy, one looked at longer, stay as
    /// they are.
    @Test func timeSpentDoesNotMakeAToyLater() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        try mac.move(1, 3)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        iPad.play.spend(600)
        iPad.now += 600
        try iPad.keep()
        try iPad.send(to: cloud)
        #expect(try mac.look(at: cloud).takeUp == nil)
        #expect(try iPad.look(at: cloud).takeUp == nil)
    }

    /// The rule reads no clock: a later toy replaces an earlier one even when its device's clock is behind.
    @Test func aLaterToyWinsWhateverTheClocksSay() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        iPad.now = Date(timeIntervalSince1970: 0)
        try mac.move(1)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        try iPad.move(3)
        try iPad.send(to: cloud)
        let onMac = try mac.look(at: cloud)
        #expect(try #require(onMac.takeUp).changedAt < mac.now)
        #expect(onMac.takeUp?.installation == "B")
    }

    // MARK: Three installations

    /// Two devices each carried on from a third's toy, apart: the third takes up one by itself, the one left most
    /// recently, and offers the other. When the person keeps one play, every device ends on it.
    @Test func threeInstallationsSettleOnOnePlay() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        let iPhone = try Installation("C")
        try mac.move(1)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        try iPhone.follow(cloud)
        iPad.now += 100
        iPhone.now += 200
        try iPad.move(3)
        try iPhone.move(1)
        try iPad.send(to: cloud)
        try iPhone.send(to: cloud)

        let onMac = try mac.look(at: cloud)
        #expect(onMac.takeUp?.installation == "C", "both are later; the one left most recently is taken")
        #expect(onMac.offer?.installation == "B", "and the other is offered")
        try mac.follow(cloud)
        try mac.send(to: cloud)
        #expect(mac.state == iPhone.state)

        // On the iPad, the iPhone's play is offered (and the Mac's, now the same toy).
        let offered = try #require(try iPad.follow(cloud))
        try iPad.keepOwn(over: offered)
        try iPad.send(to: cloud)
        try iPhone.follow(cloud)
        try iPhone.send(to: cloud)
        try mac.follow(cloud)
        try mac.send(to: cloud)
        #expect(iPhone.state == iPad.state && mac.state == iPad.state)
        for installation in [mac, iPad, iPhone] {
            let decision = try installation.look(at: cloud)
            #expect(decision.takeUp == nil && decision.offer == nil, "\(installation.id) is settled")
        }
    }

    /// Three plays parted three ways: each device offers one at a time, and settles them one after another.
    @Test func threePlaysPartedThreeWaysAreOfferedOneAtATime() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        let iPhone = try Installation("C")
        try mac.move(1)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        try iPhone.follow(cloud)
        try mac.move(3)
        try iPad.move(1)
        try iPhone.move(3, 1)
        for installation in [mac, iPad, iPhone] { try installation.send(to: cloud) }

        let first = try #require(try mac.follow(cloud))
        try mac.keepOwn(over: first)
        let second = try #require(try mac.follow(cloud), "the third play is still offered")
        #expect(second.installation != first.installation)
        try mac.keepOwn(over: second)
        #expect(try mac.follow(cloud) == nil)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        try iPhone.follow(cloud)
        #expect(iPad.state == mac.state && iPhone.state == mac.state)
    }

    // MARK: The records in the iCloud store

    /// Each installation writes only its own record, and only when something in it changed.
    @Test func anInstallationWritesOnlyItsOwnRecordAndOnlyWhenItChanged() throws {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        try mac.move(1)
        #expect(try mac.send(to: cloud))
        #expect(try !mac.send(to: cloud), "nothing changed, so nothing is sent")
        try iPad.send(to: cloud)
        try mac.move(3)
        #expect(try mac.send(to: cloud))
        let records = try cloud.container.mainContext.fetch(FetchDescriptor<SavedToy>(sortBy: [SortDescriptor(\.installation)]))
        #expect(records.map(\.installation) == ["A", "B"])
        #expect(records[1].toy?.isUntouched == true, "the iPad's record is as the iPad wrote it")
    }

    /// Two records of one installation, as a store fetched again from iCloud might hold: the other installations read
    /// the later by its lineage, and the installation's next write leaves one.
    @Test func twoRecordsOfOneInstallationBecomeOne() throws {
        let mac = try Installation("A")
        try mac.move(1)
        try mac.send(to: cloud)
        let stale = SavedToy(installation: "A")
        stale.changedAt = mac.now + 1_000
        stale.snapshot = try PlayState().snapshot.encoded()
        cloud.container.mainContext.insert(stale)
        try cloud.container.mainContext.save()

        let others = try cloud.otherToys(than: "B")
        #expect(others.count == 1)
        #expect(others.first?.lineage.head == Lineage.Change(installation: "A", count: 1), "the later by lineage, not by clock")

        try mac.move(3)
        try mac.send(to: cloud)
        let records = try cloud.container.mainContext.fetch(FetchDescriptor<SavedToy>())
        #expect(records.count == 1)
        #expect(records.first?.toyLineage.head == Lineage.Change(installation: "A", count: 2))
    }

    /// A toy this build cannot bring back, as a later build might write, is passed over: neither taken up nor offered.
    @Test func aToyThisBuildCannotReadIsPassedOver() throws {
        let later = SavedToy(installation: "Z")
        later.format = ToySnapshot.format + 1
        later.snapshot = Data("a later kind of toy".utf8)
        try later.setLineage(Lineage().changed(by: "Z"))
        cloud.container.mainContext.insert(later)
        try cloud.container.mainContext.save()
        let mac = try Installation("A")
        #expect(try cloud.otherToys(than: "A").isEmpty)
        #expect(try mac.look(at: cloud).takeUp == nil)
    }

    // MARK: The installation's id in the device's store

    @Test func theDevicesStoreKeepsTheInstallationsID() throws {
        let mac = try Installation("A")
        #expect(try mac.store.installationKept() == "A")
        let empty = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
        #expect(try empty.installationKept() == nil)
    }

    /// A store that came from another device: its toy, given the new id, is the same toy with the same lineage, so the
    /// play goes on, and the old installation, should it carry on, is the later.
    @Test func aToyGivenANewIDKeepsItsPlayAndLineage() throws {
        let old = try Installation("A")
        try old.move(1, 3)
        let lineage = try old.lineage
        try old.store.giveToy(of: "A", to: "N")
        #expect(try old.store.installationKept() == "N")
        #expect(try old.store.lineage(installation: "N") == lineage)
        #expect(try old.store.keptToy(installation: "N") == old.play.snapshot)
        #expect(try old.store.keptToy(installation: "A") == nil)

        // The device the backup came from carries on: its toy is the later.
        let original = try Installation("A")
        original.play.takeUp(old.play.snapshot)
        try original.store.takeUp(
            OtherToy(installation: "N", lineage: lineage, snapshot: old.play.snapshot, changedAt: original.now, appVersion: "1.4"),
            lineage: lineage, installation: "A", appVersion: "1.4"
        )
        try original.move(1)
        try original.send(to: cloud)
        let decision = ToyDecision(mine: lineage, others: try cloud.otherToys(than: "N"))
        #expect(decision.takeUp?.installation == "A")
    }

    @Test func aToyIsNotGivenAnIDThatKeepsOneAlready() throws {
        let store = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
        try store.keep(PlayState().snapshot, installation: "A", appVersion: "1.4")
        try store.keep(PlayState().snapshot, installation: "N", appVersion: "1.4")
        try store.giveToy(of: "A", to: "N")
        let ids = try store.container.mainContext.fetch(FetchDescriptor<SavedToy>()).map(\.installation).sorted()
        #expect(ids == ["A", "N"])
    }

    /// A store restored onto the same device, its keychain item come back with it: the store's count of changes is the
    /// backup's, so with the same id the moves made after the restore would be named as changes the iPad already knows,
    /// and its toy would replace them by itself. With no copy left out of backups the installation takes a new id, so the
    /// moves are new changes: the play has parted, and is offered on both devices.
    @Test(arguments: [1, 3])
    func aStoreRestoredOntoTheSameDeviceNamesNoChangeTwice(movesAfterRestore: Int) throws {
        let iPhone = try Installation("X")
        let iPad = try Installation("B")
        try iPhone.move(1)
        // Last night's backup: the iPhone's store with its toy at its first change.
        let restored = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
        try restored.copyToy(of: "X", from: iPhone.store)
        try iPhone.move(3)
        try iPhone.move(1)
        try iPhone.move(2)
        try iPhone.send(to: cloud)
        try iPad.follow(cloud)
        #expect(iPad.state == iPhone.state)
        try iPad.send(to: cloud)

        // The iPhone is erased and the backup restored: the keychain gives back X, the copy left out of backups is gone.
        let resolution = InstallationID.resolve(keychain: .holds("X"), leftOutOfBackups: .holdsNone, store: try restored.installationKept()) { "N" }
        #expect(resolution.id == "N" && resolution.givesToyFrom == "X")
        try restored.giveToy(of: "X", to: "N")
        var play = try #require(try restored.keptToy(installation: "N").flatMap(PlayState.init))
        // The person moves before the iPad's toy arrives.
        for ring in [3, 1, 2].prefix(movesAfterRestore) {
            play.tap(ring)
            while play.toy.isPlaying { play.advance(by: 10) }
            try restored.keep(play.snapshot, installation: "N", appVersion: "1.4")
        }

        let onIPhone = ToyDecision(mine: try restored.lineage(installation: "N"), others: try cloud.otherToys(than: "N"))
        #expect(onIPhone.takeUp == nil, "the moves made after the restore are not replaced by themselves")
        #expect(onIPhone.offer != nil, "the iPad's play is offered")
        try cloud.copyToy(of: "N", from: restored)
        let onIPad = try iPad.look(at: cloud)
        #expect(onIPad.takeUp == nil)
        #expect(onIPad.offer?.installation == "N", "the restored iPhone's play is offered on the iPad, not taken for the same toy")
    }

    // MARK: Helpers

    /// A Mac and an iPad whose play has parted in two, each toy in the iCloud store.
    private func parted() throws -> (Installation, Installation) {
        let mac = try Installation("A")
        let iPad = try Installation("B")
        try mac.move(1)
        try mac.send(to: cloud)
        try iPad.follow(cloud)
        try mac.move(3)
        try iPad.move(1)
        try mac.send(to: cloud)
        try iPad.send(to: cloud)
        return (mac, iPad)
    }
}
