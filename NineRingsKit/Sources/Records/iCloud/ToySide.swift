import Foundation
import Session

/// The toy on this device and its notes about iCloud, as the rules of docs/icloud.md section 6 read and change them.
///
/// It is a value: the store reads it, an event changes it, and the store writes it back in the same save as everything
/// else the event changed (``ICloudSync``). It knows nothing of CloudKit: a record's change tag is a string, and its
/// system fields are opaque data handed back for the next save.
struct ToySide: Equatable {
    /// The toy, with when and on which kind of device it last changed. Nil before the first toy is kept.
    var toy: Kept?
    /// The mark *Toy changed*: the toy differs, in more than time spent, from the one last exchanged with iCloud.
    var isChanged = false
    /// The Toy record as this device last saw it, with the stamps it carried. Nil when the device has seen none.
    var base: Base?
    /// The stamp under which the toy was last handed to iCloud, and whether the toy has changed since.
    var lastSend: LastSend?
    /// The stamps of this device's last sends of the toy, the oldest first.
    var ownStamps: [UUID] = []
    /// Another device's toy, kept until the person has chosen or a calm moment lets this device take it up; or a toy this
    /// version cannot read, kept without an offer. While a toy is held, this device sends no toy.
    var held: CloudRecord?

    /// The person's toy, with when and on which kind of device it last changed.
    struct Kept: Equatable {
        var snapshot: ToySnapshot
        var changedAt: Date
        var changedOn: String
    }

    /// The Toy record as this device last saw it.
    struct Base: Equatable, Codable {
        /// Its change tag. Nil only for a record whose system fields were emptied by a reset of encrypted data.
        var changeTag: String?
        /// CloudKit's system fields, which carry the tag. Nil as for the tag.
        var systemFields: Data?
        /// The stamps it carried, the oldest first, ending with its own.
        var stamps: [UUID]

        init(changeTag: String?, systemFields: Data?, stamps: [UUID]) {
            self.changeTag = changeTag
            self.systemFields = systemFields
            self.stamps = stamps
        }

        init(_ record: CloudRecord, _ payload: ToyPayload) {
            self.init(changeTag: record.changeTag, systemFields: record.systemFields, stamps: payload.stamps)
        }
    }

    /// The last time the toy was handed to iCloud.
    struct LastSend: Equatable, Codable {
        var stamp: UUID
        /// Whether the toy has changed, in more than time spent, since it was handed over.
        var changedSince: Bool
    }

    /// The most own stamps kept: the stamps of the last twenty sends.
    static let ownStampsKept = 20

    // MARK: The person changes the toy (step 1)

    /// Keeps `snapshot` as the toy, changed at `date` on a device of kind `madeOn`. When it differs from the toy here in
    /// more than time spent, the mark is set and the toy counts as changed since its last send; time spent alone changes
    /// neither, nor when the toy last changed. A first toy is marked unless nobody has touched it. Returns whether
    /// anything changed.
    @discardableResult
    mutating func keep(_ snapshot: ToySnapshot, at date: Date, on madeOn: String) -> Bool {
        guard let kept = toy else {
            toy = Kept(snapshot: snapshot, changedAt: date, changedOn: madeOn)
            isChanged = !snapshot.isUntouched
            return true
        }
        guard kept.snapshot != snapshot else { return false }
        if kept.snapshot.isSameToy(as: snapshot) {
            toy?.snapshot = snapshot
        } else {
            toy = Kept(snapshot: snapshot, changedAt: date, changedOn: madeOn)
            isChanged = true
            lastSend?.changedSince = true
        }
        return true
    }

    // MARK: Sending (steps 2 and 3)

    /// Whether the toy is to go to iCloud: it is marked as changed, and no toy is held.
    var isDue: Bool { isChanged && held == nil }

    /// The record to hand to the engine as it asks (step 2), or nil when the toy is not due.
    ///
    /// It is built from the toy as it now is, the base's system fields, which carry the base's tag, and the stamps: the
    /// base's, followed by this version's own. A toy that has not changed since it was last handed over keeps that
    /// stamp; otherwise `makeStamp` gives a new one, which becomes the last send and joins the own stamps. The caller
    /// saves this side before handing the record over.
    mutating func recordToSend(appVersion: String, makeStamp: () -> UUID) throws -> RecordToSend? {
        guard isDue, let kept = toy else { return nil }
        let stamp: UUID
        if let lastSend, !lastSend.changedSince {
            stamp = lastSend.stamp
        } else {
            stamp = makeStamp()
            lastSend = LastSend(stamp: stamp, changedSince: false)
            ownStamps = Array((ownStamps + [stamp]).suffix(Self.ownStampsKept))
        }
        let stamps = (base?.stamps ?? []).filter { $0 != stamp } + [stamp]
        let payload = ToyPayload(
            toy: kept.snapshot, changedAt: kept.changedAt, changedOn: kept.changedOn, appVersion: appVersion,
            stamps: Array(stamps.suffix(ToyPayload.stampsKept))
        )
        return RecordToSend(
            type: CloudRecord.toyType, name: CloudRecord.toyName, systemFields: base?.systemFields,
            format: ToyPayload.format, payload: try payload.encoded()
        )
    }

    /// iCloud accepted a save of the toy and returned `record` (step 3). The record becomes the base, and when the toy has
    /// not changed since it was handed over, the mark is cleared. A record that is an earlier version than one the device
    /// already holds, its base or a held toy, changes nothing: its answer came late, after a later version had reached the
    /// device.
    mutating func accepted(_ record: CloudRecord) {
        guard let payload = Self.read(record) else {
            // The device's own record always reads; should it not, the record still is iCloud's latest the device saw.
            base = Base(changeTag: record.changeTag, systemFields: record.systemFields, stamps: [])
            return
        }
        guard !isEarlierVersion(payload) else { return }
        base = Base(record, payload)
        if let lastSend, lastSend.stamp == payload.stamp, !lastSend.changedSince {
            isChanged = false
        }
    }

    /// iCloud no longer knows the record the device meant to change, or reports the Toy record deleted: the base is
    /// emptied, so that the toy is sent as a new record.
    mutating func forgetBase() {
        base = nil
    }

    // MARK: A toy arrives (step 5)

    /// What became of an arriving toy, by the case of step 5 that applied.
    enum Arrival: Equatable {
        /// The record this device holds as its base, with the same change tag: nothing is new.
        case alreadyTheBase
        /// A version before one this device holds: its own stamp is among the earlier stamps of the base or of a held
        /// toy. Nothing happens.
        case earlierVersion
        /// A payload this version cannot read: held, without an offer.
        case heldUnreadable
        /// This device's own send coming back: it became the base. `queuesAgain` when the toy here has changed since.
        case ownSend(queuesAgain: Bool)
        /// The same toy as the one here: it became the base, and the mark was cleared.
        case sameToy
        /// Held, to be taken up at the next calm moment.
        case toTakeUp
        /// Held, and offered: both devices have changed the toy.
        case offered
    }

    /// A toy arrives, through a fetch or with a refusal: the first case that fits applies. A toy that becomes the base
    /// takes the place of any held toy, and so does a toy that is held. Since an earlier version than a held toy changes
    /// nothing, a held toy is only ever replaced by a later one.
    mutating func arrived(_ record: CloudRecord) -> Arrival {
        if let tag = record.changeTag, tag == base?.changeTag {
            return .alreadyTheBase
        }
        guard let payload = Self.read(record) else {
            held = record
            return .heldUnreadable
        }
        if isEarlierVersion(payload) {
            return .earlierVersion
        }
        if let stamp = payload.stamp, ownStamps.contains(stamp) {
            base = Base(record, payload)
            held = nil
            if toy?.snapshot.isSameToy(as: payload.toy) ?? false {
                isChanged = false
                return .ownSend(queuesAgain: false)
            }
            return .ownSend(queuesAgain: isChanged)
        }
        if let kept = toy, kept.snapshot.isSameToy(as: payload.toy) {
            base = Base(record, payload)
            isChanged = false
            held = nil
            return .sameToy
        }
        held = record
        return heldFate == .toTakeUp ? .toTakeUp : .offered
    }

    /// Whether `payload` is a version before one this device holds: its own stamp is among the stamps that the base, or a
    /// held toy this version can read, carried before its own. Stamps name versions of the one record in the order
    /// CloudKit accepted them, so the version this device holds has gone on from it.
    private func isEarlierVersion(_ payload: ToyPayload) -> Bool {
        guard let stamp = payload.stamp else { return false }
        if let base, base.stamps.dropLast().contains(stamp) { return true }
        return heldPayload?.earlierStamps.contains(stamp) ?? false
    }

    // MARK: The held toy

    /// What becomes of the held toy.
    enum HeldFate: Equatable {
        /// This version cannot read it: neither taken up nor offered.
        case unreadable
        /// It replaces the toy here at the next calm moment (cases 4 and 5): the toy here is not marked, or it is marked
        /// only for a send that has not changed since and whose stamp the held toy carries among its earlier ones, so
        /// that whoever wrote it had that send before them.
        case toTakeUp
        /// It is offered (the last case): both devices have changed the toy.
        case offered
    }

    /// What becomes of the held toy, from the notes as they are now; nil when none is held. A person who changes the toy
    /// before a calm moment comes turns a toy that waited to be taken up into an offer, as step 5 says.
    var heldFate: HeldFate? {
        guard let held else { return nil }
        guard let payload = Self.read(held) else { return .unreadable }
        if !isChanged { return .toTakeUp }
        if let lastSend, !lastSend.changedSince, payload.earlierStamps.contains(lastSend.stamp) {
            return .toTakeUp
        }
        return .offered
    }

    /// The held toy's payload, when this version can read it.
    var heldPayload: ToyPayload? { held.flatMap(Self.read) }

    /// Takes the held toy up at a calm moment (cases 4 and 5): it replaces the toy here and becomes the base. Returns the
    /// toy taken up, or nil when no held toy waits to be taken up.
    mutating func takeUp() -> ToySnapshot? {
        guard heldFate == .toTakeUp else { return nil }
        return replaceWithHeld()
    }

    /// Play That One (step 6): the held toy replaces the toy here and becomes the base, and nothing is sent. Returns the
    /// toy now here, or nil when no toy this version can read is held.
    mutating func playThatOne() -> ToySnapshot? {
        replaceWithHeld()
    }

    /// Keep This One (step 6): the held toy becomes the base, so that the device has now seen it, and the toy here is to be
    /// sent at once: it stays marked, or is marked now. Returns whether a toy this version can read was held.
    mutating func keepThisOne() -> Bool {
        guard let held, let payload = Self.read(held) else { return false }
        base = Base(held, payload)
        self.held = nil
        isChanged = true
        return true
    }

    /// Replaces the toy here with the held toy, which becomes the base. The toy here was never handed over, so there is
    /// no last send. The mark is cleared, unless iCloud no longer has the held toy (its system fields were emptied by a
    /// reset of encrypted data): then the toy is marked, so that it goes to iCloud again.
    private mutating func replaceWithHeld() -> ToySnapshot? {
        guard let held, let payload = Self.read(held) else { return nil }
        toy = Kept(snapshot: payload.toy, changedAt: payload.changedAt, changedOn: payload.changedOn)
        base = Base(held, payload)
        isChanged = held.systemFields == nil
        lastSend = nil
        self.held = nil
        return payload.toy
    }

    /// Looks at the held toy again, as if it had just arrived: at launch, so that a toy an earlier version could not read
    /// is taken up or offered by a version that can.
    mutating func lookAgainAtHeldToy() -> Arrival? {
        guard let record = held, Self.read(record) != nil else { return nil }
        held = nil
        return arrived(record)
    }

    // MARK: When iCloud's copy goes (section 9) or another account arrives (section 8)

    /// Puts the toy back to `untouched` and empties its notes: the base, the marks, the stamps and any held toy.
    mutating func putBack(to untouched: Kept) {
        self = ToySide(toy: untouched)
    }

    /// After a reset of the person's encrypted data: the base and the held toy's system fields are emptied, and the toy is
    /// marked as changed unless nobody has touched it, so that it goes to iCloud again.
    mutating func afterEncryptedDataReset() {
        base = nil
        held?.changeTag = nil
        held?.systemFields = nil
        if let kept = toy, !kept.snapshot.isUntouched {
            isChanged = true
        }
    }

    // MARK: Reading

    /// The toy payload of `record`, or nil when this version cannot read it.
    static func read(_ record: CloudRecord) -> ToyPayload? {
        guard let format = record.format, let payload = record.payload else { return nil }
        return ToyPayload(format: format, payload: payload)
    }
}
