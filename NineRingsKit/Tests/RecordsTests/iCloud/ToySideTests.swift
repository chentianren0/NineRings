import Foundation
import Puzzle
@testable import Records
import Session
import Testing

/// The toy between devices, docs/icloud.md section 6, step by step and case by case, on the toy's notes alone: no store
/// and no iCloud.
@Suite struct ToySideTests {
    // MARK: Toys and records

    /// The zone the tests' records are in, and another.
    private let zone = "NineRings-1-00000000-0000-4000-8000-000000000001"
    private let otherZone = "NineRings-2-00000000-0000-4000-8000-000000000002"

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

    /// The Toy record with `toy`, `stamps` and change tag `tag`, in `zone`.
    private func record(_ toy: ToySnapshot, stamps: [UUID], tag: String, in zone: String? = nil, format: Int = ToyPayload.format) -> CloudRecord {
        let payload = ToyPayload(toy: toy, changedAt: Date(timeIntervalSinceReferenceDate: 1_000), changedOn: "iPad", appVersion: "2.0", stamps: stamps)
        return CloudRecord(
            type: CloudRecord.toyType, zone: zone ?? self.zone, name: CloudRecord.toyName, changeTag: tag,
            systemFields: Data("fields \(tag)".utf8), format: format, payload: try! payload.encoded()
        )
    }

    /// A Toy record whose content cannot be read, in `format`.
    private func unreadable(tag: String, format: Int) -> CloudRecord {
        CloudRecord(
            type: CloudRecord.toyType, zone: zone, name: CloudRecord.toyName, changeTag: tag,
            systemFields: Data("fields \(tag)".utf8), format: format, payload: Data(#"{"aLaterShape":true}"#.utf8)
        )
    }

    /// Notes with `kept` as the toy, last exchanged with iCloud as `base`.
    private func side(_ kept: ToySnapshot, base: CloudRecord? = nil, changed: Bool = false) -> ToySide {
        var side = ToySide()
        side.toy = ToySide.Kept(snapshot: kept, changedAt: .distantPast, changedOn: "iPhone")
        side.isChanged = changed
        if let base { side.base = ToySide.Base(base, stamps: payload(of: base).stamps) }
        return side
    }

    private func payload(of record: CloudRecord) -> ToyPayload {
        ToyPayload(format: record.format!, payload: record.payload!)!
    }

    private func stamps(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

    /// Sends the toy into the tests' zone: the record built and its stamp.
    private func send(_ side: inout ToySide, in zone: String? = nil) throws -> (record: RecordToSend, stamp: UUID) {
        let record = try #require(try side.recordToSend(in: zone ?? self.zone, appVersion: "2.0", makeStamp: UUID.init))
        let payload = try #require(ToyPayload(format: record.format, payload: record.payload))
        return (record, try #require(payload.stamp))
    }

    /// The record iCloud returns for `sent` saved with tag `tag`.
    private func saved(_ sent: RecordToSend, tag: String) -> CloudRecord {
        CloudRecord(
            type: sent.type, zone: sent.zone, name: sent.name, changeTag: tag, systemFields: Data("fields \(tag)".utf8),
            format: sent.format, payload: sent.payload
        )
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
        let result3 = notes.keep(moved, at: .now, on: "Mac")
        #expect(!result3, "the same toy again changes nothing")
    }

    /// A change notes that the toy has changed since its last send; time spent does not.
    @Test func aChangeIsNotedSinceTheLastSend() throws {
        var notes = side(toy([1]), changed: true)
        _ = try send(&notes)
        notes.keep(spent(toy([1]), 20), at: .now, on: "iPhone")
        #expect(notes.lastSend?.changedSince == false)
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        #expect(notes.lastSend?.changedSince == true)
    }

    /// The app starts on a new device with an untouched toy, which is not marked as changed; a first toy with moves is.
    @Test func aFirstToyIsMarkedUnlessUntouched() {
        var first = ToySide()
        let result4 = first.keep(fresh, at: .now, on: "Mac")
        #expect(result4)
        #expect(!first.isChanged)
        var played = ToySide()
        played.keep(toy([1]), at: .now, on: "Mac")
        #expect(played.isChanged)
    }

    // MARK: Step 2: the gate lets the toy go

    @Test func onlyAToyMarkedAndNotHeldIsBuilt() throws {
        var notes = side(toy([1]))
        #expect(try notes.recordToSend(in: zone, appVersion: "2.0", makeStamp: UUID.init) == nil, "not marked")
        notes.isChanged = true
        notes.held = ToySide.Held(record: record(toy([2]), stamps: stamps(1), tag: "9"), kind: .offered)
        #expect(!notes.isDue)
        #expect(try notes.recordToSend(in: zone, appVersion: "2.0", makeStamp: UUID.init) == nil, "a toy is held")
        notes.held = nil
        #expect(notes.isDue)
        #expect(try notes.recordToSend(in: zone, appVersion: "2.0", makeStamp: UUID.init) != nil)
    }

    /// The record carries the base's system fields and the stamps: the base's, followed by its own.
    @Test func theRecordCarriesTheBasesSystemFieldsAndStamps() throws {
        let earlier = stamps(3)
        let base = record(toy([1]), stamps: earlier, tag: "7")
        var notes = side(toy([1, 3]), base: base, changed: true)
        let (sent, stamp) = try send(&notes)
        #expect(sent.systemFields == base.systemFields && sent.zone == zone)
        #expect(sent.type == CloudRecord.toyType && sent.name == CloudRecord.toyName)
        let payload = try #require(ToyPayload(format: sent.format, payload: sent.payload))
        #expect(payload.stamps == earlier + [stamp])
        #expect(payload.toy == notes.toy?.snapshot)
        #expect(notes.lastSend == ToySide.LastSend(stamp: stamp, changedSince: false))
        #expect(notes.ownStamps == [stamp])
    }

    /// A record is built only from system fields of the zone the device uses: a base from another zone counts as empty.
    @Test func aBaseFromAnotherZoneCountsAsEmpty() throws {
        let base = record(toy([1]), stamps: stamps(2), tag: "7", in: otherZone)
        var notes = side(toy([1, 3]), base: base, changed: true)
        let (sent, stamp) = try send(&notes)
        #expect(sent.systemFields == nil)
        #expect(ToyPayload(format: sent.format, payload: sent.payload)?.stamps == [stamp])
    }

    /// A base without system fields gives a record without them, which iCloud takes as a new record, with the base's
    /// stamps.
    @Test func aBaseWithoutSystemFieldsGivesANewRecord() throws {
        let earlier = stamps(2)
        var notes = side(toy([1]), changed: true)
        notes.base = ToySide.Base(zone: nil, changeTag: nil, systemFields: nil, stamps: earlier)
        let (sent, stamp) = try send(&notes)
        #expect(sent.systemFields == nil)
        #expect(ToyPayload(format: sent.format, payload: sent.payload)?.stamps == earlier + [stamp])
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
            _ = try send(&notes)
        }
        let (sent, _) = try send(&notes)
        #expect(ToyPayload(format: sent.format, payload: sent.payload)?.stamps.count == 20)
        #expect(notes.ownStamps.count == 20)
    }

    // MARK: Step 3: iCloud accepts the save

    @Test func anAcceptedSaveBecomesTheBaseAndClearsTheMark() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        notes.accepted(saved(sent, tag: "5"))
        #expect(notes.base?.changeTag == "5" && notes.base?.zone == zone && !notes.isChanged)
    }

    /// The mark is cleared only when the returned record's own stamp is the stamp of the last send, and the toy has not
    /// changed since.
    @Test func aToyChangedSinceItWasHandedOverStaysMarked() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        notes.accepted(saved(sent, tag: "5"))
        #expect(notes.base?.changeTag == "5" && notes.isChanged)
    }

    @Test func anAnswerToAnEarlierSendLeavesTheMark() throws {
        var notes = side(toy([1]), changed: true)
        let (first, _) = try send(&notes)
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        _ = try send(&notes)
        notes.accepted(saved(first, tag: "5"))
        #expect(notes.isChanged, "the last send's stamp is another")
    }

    /// An answer can arrive late, when a later version is already the base: the base stays as it is.
    @Test func aLateAnswerLeavesTheBase() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, stamp) = try send(&notes)
        let later = record(toy([1, 1]), stamps: [stamp, UUID()], tag: "8")
        notes.arrived(later)
        _ = notes.takeUp()
        notes.accepted(saved(sent, tag: "5"))
        #expect(notes.base?.changeTag == "8")
    }

    // MARK: Step 4: iCloud refuses the save (the refused record arrives: step 5)

    /// iCloud no longer knows the Toy record: the base is emptied, and the toy goes out as a new record (section 10).
    @Test func aRecordICloudNoLongerKnowsEmptiesTheBase() throws {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "3"), changed: true)
        notes.forgetBase()
        #expect(notes.base == nil && notes.isChanged)
        #expect(try send(&notes).record.systemFields == nil)
    }

    // MARK: Step 5: a toy arrives

    @Test func caseOneTheRecordHeldAsTheBaseChangesNothing() {
        let base = record(toy([1]), stamps: stamps(1), tag: "3")
        var notes = side(toy([1, 3]), base: base, changed: true)
        let before = notes
        let result5 = notes.arrived(base)
        #expect(result5 == .alreadyTheBase)
        #expect(notes == before)
    }

    /// Case 1 compares within one zone: a record of another zone with the same tag is not the base.
    @Test func caseOneComparesWithinOneZone() {
        let base = record(toy([1]), stamps: stamps(1), tag: "3")
        var notes = side(toy([1]), base: base)
        var elsewhere = record(toy([1, 3]), stamps: stamps(1), tag: "3")
        elsewhere.zone = otherZone
        let result6 = notes.arrived(elsewhere)
        #expect(result6 != .alreadyTheBase)
    }

    /// A toy in a higher format is held as unreadable, and its stamps are not read; a held toy is no longer held.
    @Test(arguments: [2, 99])
    func aToyInAHigherFormatIsHeldAsUnreadable(format: Int) {
        var notes = side(toy([1]), changed: true)
        notes.held = ToySide.Held(record: record(toy([2]), stamps: stamps(1), tag: "2"), kind: .offered)
        let result7 = notes.arrived(unreadable(tag: "4", format: format))
        #expect(result7 == .heldUnreadable)
        #expect(notes.held?.kind == .unreadable && !notes.isDue)
        #expect(notes.toy?.snapshot == toy([1]), "the toy here is neither taken up nor replaced")
    }

    /// A toy in a known format whose content cannot be read becomes the base through its system fields alone, and the toy
    /// here is marked as changed unless it is untouched.
    @Test(arguments: [true, false])
    func aBrokenToyBecomesTheBaseAndTheToyHereGoesOutOverIt(untouched: Bool) throws {
        var notes = side(untouched ? fresh : toy([1]))
        notes.held = ToySide.Held(record: record(toy([2]), stamps: stamps(1), tag: "2"), kind: .offered)
        let broken = unreadable(tag: "4", format: ToyPayload.format)
        let result8 = notes.arrived(broken)
        #expect(result8 == .brokenBecameBase)
        #expect(notes.base == ToySide.Base(broken, stamps: []) && notes.held == nil)
        #expect(notes.isChanged == !untouched)
        if !untouched { #expect(try send(&notes).record.systemFields == broken.systemFields) }
    }

    @Test func caseTwoAVersionBeforeTheBaseChangesNothing() {
        let earlier = stamps(2)
        let base = record(toy([1, 3]), stamps: earlier + [UUID()], tag: "6")
        var notes = side(toy([1, 3]), base: base)
        let old = record(toy([1]), stamps: [earlier[0], earlier[1]], tag: "4")
        let before = notes
        let result9 = notes.arrived(old)
        #expect(result9 == .earlierVersion)
        #expect(notes == before)
    }

    @Test func caseTwoAVersionBeforeAHeldToyChangesNothing() {
        var notes = side(toy([1]), changed: true)
        let first = UUID()
        notes.held = ToySide.Held(record: record(toy([2, 2]), stamps: [first, UUID()], tag: "6"), kind: .offered)
        let before = notes
        let result10 = notes.arrived(record(toy([2]), stamps: [first], tag: "5"))
        #expect(result10 == .earlierVersion)
        #expect(notes == before)
    }

    /// A record's earlier stamps never include its own: the base's own stamp does not make a record an earlier version.
    @Test func theBasesOwnStampIsNotAnEarlierStamp() {
        let own = UUID()
        var notes = side(toy([1]), changed: true)
        notes.base = ToySide.Base(zone: nil, changeTag: nil, systemFields: nil, stamps: [UUID(), own])
        let result11 = notes.arrived(record(toy([2]), stamps: [own], tag: "5"))
        #expect(result11 != .earlierVersion)
    }

    @Test func caseThreeOwnSendComingBackUnchangedClearsTheMark() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        let result12 = notes.arrived(saved(sent, tag: "5"))
        #expect(result12 == .ownSend(sameToy: true))
        #expect(notes.base?.changeTag == "5" && !notes.isChanged)
    }

    @Test func caseThreeOwnSendComingBackAfterAChangeKeepsTheMark() throws {
        var notes = side(toy([1]), changed: true)
        let (sent, _) = try send(&notes)
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        let result13 = notes.arrived(saved(sent, tag: "5"))
        #expect(result13 == .ownSend(sameToy: false))
        #expect(notes.base?.changeTag == "5" && notes.isChanged)
    }

    @Test func caseFourTheSameToyBecomesTheBaseAndClearsTheMark() {
        var notes = side(toy([1]), changed: true)
        let result14 = notes.arrived(record(spent(toy([1]), 40), stamps: stamps(1), tag: "5"))
        #expect(result14 == .sameToy)
        #expect(notes.base?.changeTag == "5" && !notes.isChanged)
    }

    /// Case 5: the toy here is not marked, and the arriving toy is taken up at the next calm moment: it becomes the base,
    /// the mark is cleared, and the note of the last send is emptied. Until then the base stays.
    @Test func caseFiveATakeUpWaitsForACalmMoment() throws {
        let base = record(toy([1]), stamps: stamps(1), tag: "3")
        var notes = side(toy([1]), base: base)
        notes.lastSend = ToySide.LastSend(stamp: UUID(), changedSince: false)
        let arriving = record(toy([1, 3]), stamps: stamps(2), tag: "6")
        let result15 = notes.arrived(arriving)
        #expect(result15 == .toTakeUp)
        #expect(notes.base?.changeTag == "3" && notes.held?.kind == .toTakeUp)
        let result16 = notes.takeUp()
        #expect(result16 == payload(of: arriving).toy)
        #expect(notes.base?.changeTag == "6" && !notes.isChanged && notes.lastSend == nil && notes.held == nil)
    }

    /// If the person changes the toy before the calm moment comes, the last case applies.
    @Test func aChangeBeforeTheCalmMomentTurnsTakingUpIntoTheOffer() {
        var notes = side(toy([1]))
        notes.arrived(record(toy([1, 3]), stamps: stamps(1), tag: "6"))
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        #expect(notes.held?.kind == .offered)
        let result17 = notes.takeUp()
        #expect(result17 == nil)
    }

    /// Case 6: the toy here is marked, has not changed since it was handed over, and its stamp is among the arriving toy's
    /// earlier stamps: it is taken up.
    @Test func caseSixAToyWrittenOnThisDevicesUnansweredSendIsTakenUp() throws {
        var notes = side(toy([1]), changed: true)
        let (_, stamp) = try send(&notes)
        let arriving = record(toy([1, 3]), stamps: [stamp, UUID()], tag: "7")
        let result18 = notes.arrived(arriving)
        #expect(result18 == .toTakeUp)
        let result19 = notes.takeUp()
        #expect(result19 != nil)
        #expect(!notes.isChanged && notes.lastSend == nil)
    }

    @Test func caseSevenAToyChangedSinceItsSendIsOfferedThoughItsStampArrives() throws {
        var notes = side(toy([1]), changed: true)
        let (_, stamp) = try send(&notes)
        notes.keep(toy([1, 1]), at: .now, on: "iPhone")
        let result20 = notes.arrived(record(toy([1, 3]), stamps: [stamp, UUID()], tag: "7"))
        #expect(result20 == .offered)
    }

    @Test func caseSevenWhenBothChangedTheToyIsOffered() throws {
        var notes = side(toy([1]), base: record(toy([]), stamps: stamps(1), tag: "2"), changed: true)
        let result21 = notes.arrived(record(toy([3]), stamps: stamps(2), tag: "7"))
        #expect(result21 == .offered)
        #expect(notes.base?.changeTag == "2", "the base stays as it was")
    }

    /// A toy that arrives and is not ignored by case 1 or case 2 takes a held toy's place.
    @Test func aNewerToyTakesTheHeldOnesPlace() {
        var notes = side(toy([1]), changed: true)
        let first = UUID()
        notes.held = ToySide.Held(record: record(toy([2]), stamps: [first], tag: "5"), kind: .offered)
        notes.arrived(record(toy([2, 2]), stamps: [first, UUID()], tag: "6"))
        #expect(notes.held?.record.changeTag == "6")
    }

    /// At each launch, a held unreadable toy that this version can now read is handled as an arriving toy.
    @Test func aHeldUnreadableToyThatNowReadsIsTakenOut() {
        var notes = side(toy([1]))
        let readable = record(toy([1, 3]), stamps: stamps(1), tag: "6")
        notes.held = ToySide.Held(record: readable, kind: .unreadable)
        let result22 = notes.takeHeldUnreadableThatNowReads()
        #expect(result22 == readable && notes.held == nil)
        notes.held = ToySide.Held(record: unreadable(tag: "7", format: 2), kind: .unreadable)
        let result23 = notes.takeHeldUnreadableThatNowReads()
        #expect(result23 == nil && notes.held != nil)
    }

    // MARK: Step 6: the person answers the offer

    @Test func playThatOneReplacesTheToyAndSendsNothing() {
        var notes = side(toy([1]), changed: true)
        notes.lastSend = ToySide.LastSend(stamp: UUID(), changedSince: true)
        let theirs = record(toy([3]), stamps: stamps(1), tag: "7")
        notes.arrived(theirs)
        let result24 = notes.playThatOne()
        #expect(result24 == payload(of: theirs).toy)
        #expect(notes.base?.changeTag == "7" && !notes.isChanged && notes.lastSend == nil && notes.held == nil)
    }

    @Test func keepThisOneMakesTheHeldToyTheBaseAndMarksTheToy() throws {
        var notes = side(toy([1]), changed: true)
        notes.arrived(record(toy([3]), stamps: stamps(1), tag: "7"))
        let result25 = notes.keepThisOne()
        #expect(result25)
        #expect(notes.base?.changeTag == "7" && notes.held == nil && notes.isChanged)
        #expect(try send(&notes).record.systemFields == Data("fields 7".utf8))
    }

    /// A held toy without system fields, whose zone is gone: Play That One marks the toy, because iCloud does not have
    /// it, and so does taking it up; Keep This One makes its stamps the base, and the toy here goes out as a new record.
    @Test func aHeldToyWithoutSystemFields() throws {
        let theirs = record(toy([3]), stamps: stamps(2), tag: "7").withoutSystemFields
        var played = side(toy([1]), changed: true)
        played.held = ToySide.Held(record: theirs, kind: .offered)
        let result26 = played.playThatOne()
        #expect(result26 != nil)
        #expect(played.isChanged && played.base?.systemFields == nil && played.base?.stamps == payload(of: theirs).stamps)
        var taken = side(toy([1]))
        taken.held = ToySide.Held(record: theirs, kind: .toTakeUp)
        let result27 = taken.takeUp()
        #expect(result27 != nil)
        #expect(taken.isChanged, "one rule for both: the zone the device uses does not have it")
        var kept = side(toy([1]), changed: true)
        kept.held = ToySide.Held(record: theirs, kind: .offered)
        let result28 = kept.keepThisOne()
        #expect(result28)
        let (sent, stamp) = try send(&kept)
        #expect(sent.systemFields == nil)
        #expect(ToyPayload(format: sent.format, payload: sent.payload)?.stamps == payload(of: theirs).stamps + [stamp])
    }

    // MARK: Leaving a zone, and the toy put back

    /// Leaving a zone empties the base and the held toy's system fields of that zone, and marks the toy unless it is
    /// untouched.
    @Test(arguments: [true, false])
    func leavingAZone(untouched: Bool) {
        var notes = side(untouched ? fresh : toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "3"))
        notes.held = ToySide.Held(record: record(toy([2]), stamps: stamps(1), tag: "4"), kind: .offered)
        notes.leaveZones(keeping: otherZone)
        #expect(notes.base == nil)
        #expect(notes.held?.record.systemFields == nil && notes.held?.record.zone == nil)
        #expect(notes.isChanged == !untouched)
    }

    @Test func leavingAnotherZoneKeepsWhatBelongsToTheZoneKept() {
        let base = record(toy([1]), stamps: stamps(1), tag: "3")
        var notes = side(toy([1]), base: base)
        notes.leaveZones(keeping: zone)
        #expect(notes.base?.changeTag == "3" && !notes.isChanged)
    }

    @Test func puttingTheToyBackEmptiesItsNotes() throws {
        var notes = side(toy([1]), base: record(toy([1]), stamps: stamps(1), tag: "3"), changed: true)
        _ = try send(&notes)
        notes.held = ToySide.Held(record: record(toy([2]), stamps: stamps(1), tag: "4"), kind: .offered)
        notes.putBack(to: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: "iPhone"))
        #expect(notes == ToySide(toy: ToySide.Kept(snapshot: fresh, changedAt: .distantPast, changedOn: "iPhone")))
    }
}
