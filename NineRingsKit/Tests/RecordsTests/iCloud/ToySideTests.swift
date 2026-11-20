import Foundation
import Puzzle
@testable import Records
import Session
import Testing

/// The toy between devices, docs/icloud.md section 6, case by case, on the toy's notes alone: no store and no iCloud.
@Suite struct ToySideTests {
    // MARK: Toys and records

    /// The untouched toy every toy of a test starts from: each fresh toy has a play of its own.
    private let fresh = PlayState().snapshot

    /// A toy with `rings` tapped and played out, from the test's untouched toy or from `start`.
    private func toy(_ rings: [Int], from start: ToySnapshot? = nil) -> ToySnapshot {
        var state = PlayState(start ?? fresh)!
        for ring in rings {
            state.tap(ring)
            while state.toy.isPlaying { state.advance(by: 10) }
        }
        return state.snapshot
    }

    private func spent(_ snapshot: ToySnapshot, _ seconds: Double) -> ToySnapshot {
        var state = PlayState(snapshot)!
        state.spend(seconds)
        return state.snapshot
    }

    /// The Toy record with `toy`, `stamps` and change tag `tag`.
    private func record(_ toy: ToySnapshot, stamps: [UUID], tag: String, format: Int = ToyPayload.format) -> CloudRecord {
        let payload = ToyPayload(toy: toy, changedAt: Date(timeIntervalSinceReferenceDate: 1_000), changedOn: "iPad", appVersion: "2.0", stamps: stamps)
        return CloudRecord(
            type: CloudRecord.toyType, name: CloudRecord.toyName, changeTag: tag, systemFields: Data("fields \(tag)".utf8),
            format: format, payload: try! payload.encoded()
        )
    }

    /// Notes with `kept` as the toy, last exchanged with iCloud as `base`.
    private func side(_ kept: ToySnapshot, base: CloudRecord? = nil, changed: Bool = false) -> ToySide {
        var side = ToySide()
        side.toy = ToySide.Kept(snapshot: kept, changedAt: .distantPast, changedOn: "iPhone")
        side.isChanged = changed
        if let base { side.base = ToySide.Base(base, ToySide.read(base)!) }
        return side
    }

    private func stamps(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

    /// Sends the toy: the record built and its stamp.
    private func send(_ side: inout ToySide) throws -> (record: RecordToSend, stamp: UUID) {
        let record = try #require(try side.recordToSend(appVersion: "2.0", makeStamp: UUID.init))
        let payload = try #require(ToyPayload(format: record.format, payload: record.payload))
        return (record, try #require(payload.stamp))
    }

    /// The record iCloud returns for `sent` saved with tag `tag`.
    private func saved(_ sent: RecordToSend, tag: String) -> CloudRecord {
        CloudRecord(type: sent.type, name: sent.name, changeTag: tag, systemFields: Data("fields \(tag)".utf8), format: sent.format, payload: sent.payload)
    }

    // MARK: Step 1: the person changes the toy

    @Test func aChangeSetsTheMarkAndTimeAloneDoesNot() {
        let start = toy([1])
        var notes = side(start)
        let result1 = notes.keep(spent(start, 30), at: .now, on: "iPhone")
        #expect(result1)
        #expect(!notes.isChanged, "time spent alone does not set the mark")
        #expect(notes.toy?.changedAt == .distantPast, "nor when the toy last changed")
        let moved = toy([3], from: start)
        let result2 = notes.keep(moved, at: Date(timeIntervalSinceReferenceDate: 5), on: "Mac")
        #expect(result2)
        #expect(notes.isChanged)
        #expect(notes.toy?.changedAt == Date(timeIntervalSinceReferenceDate: 5) && notes.toy?.changedOn == "Mac")
        let again = notes.keep(moved, at: .now, on: "Mac")
        #expect(!again, "the same toy again changes nothing")
    }

    /// The app starts on a new device with an untouched toy, which is not marked as changed; a first toy with moves is.
    @Test func aFirstToyIsMarkedUnlessUntouched() {
        var first = ToySide()
        let kept = first.keep(fresh, at: .now, on: "Mac")
        #expect(kept)
        #expect(!first.isChanged)
        var played = ToySide()
        played.keep(toy([1]), at: .now, on: "Mac")
        #expect(played.isChanged)
    }

    // MARK: Step 2: a sending moment

    @Test func onlyAToyMarkedAndNotHeldIsSent() throws {
        var notes = side(toy([1]))
        #expect(try notes.recordToSend(appVersion: "2.0", makeStamp: UUID.init) == nil, "not marked")
        notes.isChanged = true
        notes.held = record(toy([2]), stamps: stamps(1), tag: "9")
        #expect(!notes.isDue)
        #expect(try notes.recordToSend(appVersion: "2.0", makeStamp: UUID.init) == nil, "a toy is held")
        notes.held = nil
        #expect(notes.isDue)
        #expect(try notes.recordToSend(appVersion: "2.0", makeStamp: UUID.init) != nil)
    }

    /// The record carries the base's tag in its system fields, and the stamps: the base's, followed by its own.
    @Test func theRecordCarriesTheBasesTagAndStamps() throws {
        let earlier = stamps(3)
        let base = record(toy([1]), stamps: earlier, tag: "7")
        var notes = side(toy([1, 3]), base: base, changed: true)
        let (sent, stamp) = try send(&notes)
        #expect(sent.systemFields == base.systemFields)
        #expect(sent.type == CloudRecord.toyType && sent.name == CloudRecord.toyName)
        let payload = try #require(ToyPayload(format: sent.format, payload: sent.payload))
        #expect(payload.stamps == earlier + [stamp])
        #expect(payload.toy == notes.toy?.snapshot)
        #expect(notes.lastSend == ToySide.LastSend(stamp: stamp, changedSince: false))
        #expect(notes.ownStamps == [stamp])
    }

    @Test func aDeviceThatNeverSawTheRecordSendsItAsNew() throws {
        var notes = side(toy([1]), changed: true)
        #expect(try send(&notes).record.systemFields == nil)
    }

    /// A toy that has not changed since it was handed over keeps its stamp, so that sending it again uses no new one.
    @Test func aToySentAgainUnchangedKeepsItsStamp() throws {
        var notes = side(toy([1]), changed: true)
        let first = try send(&notes).stamp
        #expect(try send(&notes).stamp == first)
        #expect(notes.ownStamps == [first])
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        let second = try send(&notes).stamp
        #expect(second != first)
        #expect(notes.ownStamps == [first, second])
    }

    @Test func atMostTwentyStampsAreCarriedAndKept() throws {
        let base = record(toy([1]), stamps: stamps(20), tag: "4")
        var notes = side(toy([1]), base: base, changed: true)
        for index in 0..<25 {
            notes.keep(toy(Array(repeating: 1, count: index + 2)), at: .now, on: "iPhone")
            let (sent, stamp) = try send(&notes)
            let payload = try #require(ToyPayload(format: sent.format, payload: sent.payload))
            #expect(payload.stamps.count == 20 && payload.stamp == stamp)
        }
        #expect(notes.ownStamps.count == 20)
    }

    // MARK: Step 3: iCloud accepts the save

    @Test func anAcceptedSaveBecomesTheBaseAndClearsTheMark() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let (sent, stamp) = try send(&notes)
        notes.accepted(saved(sent, tag: "2"))
        #expect(notes.base?.changeTag == "2" && notes.base?.stamps.last == stamp)
        #expect(!notes.isChanged)
    }

    @Test func aToyChangedSinceItWasHandedOverStaysMarked() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        notes.keep(toy([1, 3]), at: .now, on: "iPhone")
        notes.accepted(saved(sent, tag: "2"))
        #expect(notes.base?.changeTag == "2")
        #expect(notes.isChanged)
    }

    // MARK: Step 5: a toy arrives

    /// The first case: the record this device already holds as its base, with the same change tag. Nothing is new, and
    /// nothing happens, also when the toy here has changed since, as when a fetch from nothing delivers the record again.
    @Test func theRecordHeldAsTheBaseChangesNothing() {
        let base = record(toy([1]), stamps: stamps(2), tag: "5")
        var notes = side(toy([1, 3]), base: base, changed: true)
        let before = notes
        let result4 = notes.arrived(base)
        #expect(result4 == .alreadyTheBase)
        #expect(notes == before)
    }

    /// A version before the base: its own stamp is among the base's earlier stamps. Nothing happens.
    @Test func aVersionBeforeTheBaseChangesNothing() {
        let chain = stamps(3)
        let base = record(toy([1, 3]), stamps: chain, tag: "8")
        var notes = side(toy([1, 3]), base: base)
        let older = record(toy([1]), stamps: Array(chain.prefix(2)), tag: "6")
        let before = notes
        let result5 = notes.arrived(older)
        #expect(result5 == .earlierVersion)
        #expect(notes == before, "an older toy is not taken up over a newer one")
    }

    /// A version before a held toy: a held toy is only ever replaced by a later one.
    @Test func aVersionBeforeAHeldToyChangesNothing() {
        let chain = stamps(3)
        var notes = side(toy([2]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let result6 = notes.arrived(record(toy([1, 3]), stamps: chain, tag: "9"))
        #expect(result6 == .offered)
        let before = notes
        let result7 = notes.arrived(record(toy([1]), stamps: Array(chain.prefix(2)), tag: "7"))
        #expect(result7 == .earlierVersion)
        #expect(notes == before)
    }

    @Test func anAcceptedSaveThatIsAnEarlierVersionLeavesTheBase() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let (sent, stamp) = try send(&notes)
        // Another device took the save up and went on before its answer came.
        let later = record(toy([1, 3]), stamps: [stamp, UUID()], tag: "3")
        let result8 = notes.arrived(later)
        #expect(result8 == .toTakeUp)
        _ = notes.takeUp()
        notes.accepted(saved(sent, tag: "2"))
        #expect(notes.base?.changeTag == "3", "the base never goes back")
    }

    /// A toy in a format this version cannot read is held without an offer; no toy is sent while it is held, and it is
    /// neither taken up nor replaced.
    @Test(arguments: [2, 99])
    func aToyThisVersionCannotReadIsHeldWithoutAnOffer(format: Int) throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let newer = record(toy([2]), stamps: stamps(1), tag: "4", format: format)
        let result9 = notes.arrived(newer)
        #expect(result9 == .heldUnreadable)
        #expect(notes.heldFate == .unreadable)
        #expect(!notes.isDue)
        #expect(try notes.recordToSend(appVersion: "2.0", makeStamp: UUID.init) == nil)
        let result10 = notes.takeUp()
        let chosen = notes.playThatOne()
        let kept = notes.keepThisOne()
        #expect(result10 == nil && chosen == nil && !kept)
        #expect(notes.toy?.snapshot == toy([1]), "this device's toy stays")
        #expect(notes.base?.changeTag == "1")
    }

    /// One rule for every toy this version cannot read: a payload of format 1 that is broken is held the same way.
    @Test func aBrokenToyIsHeldWithoutAnOffer() {
        var notes = side(toy([1]))
        let broken = CloudRecord(type: CloudRecord.toyType, name: CloudRecord.toyName, changeTag: "3", systemFields: nil, format: 1, payload: Data("{".utf8))
        let result11 = notes.arrived(broken)
        #expect(result11 == .heldUnreadable)
        #expect(notes.heldFate == .unreadable)
    }

    /// A readable toy that arrives takes the place of one this version cannot read.
    @Test func aReadableToyTakesTheUnreadablesPlace() {
        var notes = side(toy([1]))
        _ = notes.arrived(record(toy([2]), stamps: stamps(1), tag: "4", format: 2))
        let result12 = notes.arrived(record(toy([1, 3]), stamps: stamps(1), tag: "5"))
        #expect(result12 == .toTakeUp)
        #expect(notes.held?.changeTag == "5")
    }

    /// Its own stamp is one of this device's own stamps, and it is the same toy as the one here: it becomes the base, and
    /// the mark is cleared.
    @Test func ownSendComingBackUnchangedClearsTheMark() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        let result13 = notes.arrived(saved(sent, tag: "2"))
        #expect(result13 == .ownSend(queuesAgain: false))
        #expect(notes.base?.changeTag == "2")
        #expect(!notes.isChanged)
    }

    /// Its own stamp is this device's, and the toy here has changed since: the mark stays and the toy is queued again.
    @Test func ownSendComingBackAfterAChangeIsQueuedAgain() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        notes.keep(toy([1, 3]), at: .now, on: "iPhone")
        let result14 = notes.arrived(saved(sent, tag: "2"))
        #expect(result14 == .ownSend(queuesAgain: true))
        #expect(notes.base?.changeTag == "2" && notes.isChanged && notes.isDue)
    }

    @Test func theSameToyBecomesTheBaseAndClearsTheMark() {
        let mine = toy([1])
        var notes = side(spent(mine, 99), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let theirs = record(spent(mine, 3), stamps: stamps(2), tag: "6")
        let result15 = notes.arrived(theirs)
        #expect(result15 == .sameToy)
        #expect(notes.base?.changeTag == "6" && !notes.isChanged)
        #expect(notes.toy?.snapshot.play?.secondsSpent == 99, "the toy here stays, with its own time")
    }

    /// The toy here is not marked: the arriving toy is taken up at the next calm moment, and only then becomes the base.
    @Test func anArrivingToyIsTakenUpWhenTheToyHereIsNotMarked() {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "1"))
        let theirs = record(toy([1, 3]), stamps: stamps(2), tag: "2")
        let result16 = notes.arrived(theirs)
        #expect(result16 == .toTakeUp)
        #expect(notes.base?.changeTag == "1", "until then the base stays as it was")
        let result17 = notes.takeUp()
        #expect(result17 == toy([1, 3]))
        #expect(notes.toy?.snapshot == toy([1, 3]) && notes.toy?.changedOn == "iPad")
        #expect(notes.base?.changeTag == "2" && !notes.isChanged && notes.held == nil && notes.lastSend == nil)
    }

    /// If the person changes the toy before that moment comes, the last case applies: the toy is offered.
    @Test func aChangeBeforeTheCalmMomentTurnsTakingUpIntoTheOffer() {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "1"))
        _ = notes.arrived(record(toy([1, 3]), stamps: stamps(2), tag: "2"))
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        #expect(notes.heldFate == .offered)
        let result18 = notes.takeUp()
        #expect(result18 == nil)
    }

    /// The fifth case: the toy here is marked, but it has not changed since it was handed over, and its stamp is among the
    /// arriving toy's earlier stamps. The save reached iCloud though its answer did not come back, and whoever wrote the
    /// arriving toy had it before them: it is taken up.
    @Test func aToyWrittenOnThisDevicesUnansweredSendIsTakenUp() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let (_, stamp) = try send(&notes)
        let goneOn = record(toy([1, 3]), stamps: [UUID(), stamp, UUID()], tag: "3")
        let result19 = notes.arrived(goneOn)
        #expect(result19 == .toTakeUp)
        let result20 = notes.takeUp()
        #expect(result20 == toy([1, 3]))
    }

    @Test func aToyChangedSinceItsSendIsOfferedThoughItsStampArrives() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let (_, stamp) = try send(&notes)
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        let result21 = notes.arrived(record(toy([1, 3]), stamps: [stamp, UUID()], tag: "3"))
        #expect(result21 == .offered)
    }

    /// Otherwise both devices have changed the toy: it is held and offered, and the base stays as it was.
    @Test func whenBothChangedTheToyIsOffered() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        _ = try send(&notes)
        let result22 = notes.arrived(record(toy([2]), stamps: stamps(2), tag: "3"))
        #expect(result22 == .offered)
        #expect(notes.heldFate == .offered && notes.base?.changeTag == "1")
    }

    /// While a toy is held, a still newer toy takes its place; one that becomes the base leaves nothing held.
    @Test func aNewerToyTakesTheHeldOnesPlace() {
        var notes = side(toy([2]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        _ = notes.arrived(record(toy([1]), stamps: stamps(1), tag: "3"))
        let result23 = notes.arrived(record(toy([1, 3]), stamps: stamps(2), tag: "4"))
        #expect(result23 == .offered)
        #expect(notes.held?.changeTag == "4")
        let result24 = notes.arrived(record(toy([2]), stamps: stamps(3), tag: "5"))
        #expect(result24 == .sameToy)
        #expect(notes.held == nil)
    }

    // MARK: Step 6: the person answers the offer

    @Test func playThatOneReplacesTheToyAndSendsNothing() {
        var notes = side(toy([2]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        _ = notes.arrived(record(toy([1, 3]), stamps: stamps(2), tag: "3"))
        let result25 = notes.playThatOne()
        #expect(result25 == toy([1, 3]))
        #expect(notes.base?.changeTag == "3" && !notes.isChanged && notes.held == nil && notes.lastSend == nil)
        #expect(!notes.isDue)
    }

    @Test func keepThisOneMakesTheHeldToyTheBaseAndSendsAtOnce() throws {
        var notes = side(toy([2]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        let held = record(toy([1, 3]), stamps: stamps(2), tag: "3")
        _ = notes.arrived(held)
        let result26 = notes.keepThisOne()
        #expect(result26)
        #expect(notes.base?.changeTag == "3" && notes.held == nil && notes.isDue)
        #expect(notes.toy?.snapshot == toy([2]))
        let sent = try send(&notes).record
        #expect(sent.systemFields == held.systemFields, "sent again with the tag of the record it was shown")
    }

    // MARK: When the record or the zone goes

    @Test func aRecordICloudNoLongerKnowsEmptiesTheBase() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "1"), changed: true)
        notes.forgetBase()
        #expect(notes.base == nil)
        #expect(try send(&notes).record.systemFields == nil, "sent as a new record")
    }

    @Test func aResetOfEncryptedDataMarksTheToyAndEmptiesTheSystemFields() {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "1"))
        _ = notes.arrived(record(toy([1, 3]), stamps: stamps(2), tag: "2"))
        notes.afterEncryptedDataReset()
        #expect(notes.base == nil && notes.isChanged)
        #expect(notes.held?.systemFields == nil && notes.held?.changeTag == nil)
        #expect(notes.heldFate == .offered, "a held toy can still be chosen after a reset")
        var untouched = side(fresh)
        untouched.afterEncryptedDataReset()
        #expect(!untouched.isChanged, "an untouched toy is not marked")
    }

    /// Because iCloud no longer has it after a reset, Play That One then marks the toy as changed.
    @Test func playThatOneAfterAResetMarksTheToy() {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "1"), changed: true)
        _ = notes.arrived(record(toy([2]), stamps: stamps(2), tag: "2"))
        notes.afterEncryptedDataReset()
        let result27 = notes.playThatOne()
        #expect(result27 == toy([2]))
        #expect(notes.isChanged && notes.base?.systemFields == nil)
    }

    @Test func puttingTheToyBackEmptiesItsNotes() throws {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "1"), changed: true)
        _ = try send(&notes)
        _ = notes.arrived(record(toy([2]), stamps: stamps(2), tag: "2"))
        let putBack = PlayState().snapshot
        notes.putBack(to: ToySide.Kept(snapshot: putBack, changedAt: .distantPast, changedOn: "Mac"))
        #expect(notes == ToySide(toy: ToySide.Kept(snapshot: putBack, changedAt: .distantPast, changedOn: "Mac")))
    }

    /// At launch a held toy is looked at again by the cases of step 5.
    @Test func aHeldToyIsLookedAtAgain() {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "1"), changed: true)
        _ = notes.arrived(record(toy([2]), stamps: stamps(2), tag: "2"))
        let result28 = notes.lookAgainAtHeldToy()
        #expect(result28 == .offered)
        #expect(notes.held?.changeTag == "2")
        var unreadable = side(toy([1]))
        _ = unreadable.arrived(record(toy([2]), stamps: stamps(1), tag: "3", format: 2))
        let result29 = unreadable.lookAgainAtHeldToy()
        #expect(result29 == nil, "a toy this version cannot read stays held")
        #expect(unreadable.heldFate == .unreadable)
    }
}
