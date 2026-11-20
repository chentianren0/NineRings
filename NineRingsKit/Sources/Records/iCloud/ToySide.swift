import Foundation
import Session

/// The toy on this device and its notes about iCloud, as the rules of docs/icloud.md section 6 read and change them.
///
/// It is a value: the store reads it, a call changes it, and the store writes it back in the same save as everything else
/// the call changed (``ICloudSync``). It knows nothing of CloudKit: a record's zone and change tag are strings, and its
/// system fields are opaque data handed back for the next save. It knows nothing of the gate either: which zone the
/// device uses, and whether a record arrived from it, is the caller's to say.
struct ToySide: Equatable {
    /// The toy, with when and on which kind of device it last changed. Nil before the first toy is kept.
    var toy: Kept?
    /// The mark *Toy changed*: the toy has to be sent.
    var isChanged = false
    /// The Toy record as this device last saw it, with its stamps. Nil when the device has seen none.
    var base: Base?
    /// The stamp under which the toy was last handed to iCloud, and whether the toy has changed since.
    var lastSend: LastSend?
    /// The stamps of this device's last sends of the toy, the oldest first.
    var ownStamps: [UUID] = []
    /// Another device's toy, held to be taken up, offered to the person, or held because this version cannot read it.
    var held: Held?

    /// The person's toy, with when and on which kind of device it last changed.
    struct Kept: Equatable {
        var snapshot: ToySnapshot
        var changedAt: Date
        var changedOn: String
    }

    /// The Toy record as this device last saw it (section 5, "Toy base").
    ///
    /// Its system fields carry its change tag and its zone. It can have stamps and no system fields: the held toy of a
    /// zone that is gone, over which the person kept their own. It can have system fields and no stamps: a toy this
    /// version could not read.
    struct Base: Equatable, Codable {
        /// The zone its system fields belong to; nil when it has none.
        var zone: String?
        var changeTag: String?
        var systemFields: Data?
        /// The stamps it carried, the oldest first, ending with its own.
        var stamps: [UUID]

        init(zone: String?, changeTag: String?, systemFields: Data?, stamps: [UUID]) {
            self.zone = systemFields == nil ? nil : zone
            self.changeTag = systemFields == nil ? nil : changeTag
            self.systemFields = systemFields
            self.stamps = stamps
        }

        init(_ record: CloudRecord, stamps: [UUID]) {
            self.init(zone: record.zone, changeTag: record.changeTag, systemFields: record.systemFields, stamps: stamps)
        }
    }

    /// The last time the toy was handed to iCloud.
    struct LastSend: Equatable, Codable {
        var stamp: UUID
        /// Whether the person has changed the toy since it was handed over.
        var changedSince: Bool
    }

    /// Another device's toy, as it arrived, and what it is held for. A held toy whose zone is gone has no system fields.
    struct Held: Equatable, Codable {
        var record: CloudRecord
        var kind: Kind

        enum Kind: Int, Codable {
            /// It replaces the toy here at the next calm moment (cases 5 and 6).
            case toTakeUp
            /// It is offered to the person (case 7).
            case offered
            /// Its format is higher than this version knows: neither taken up nor offered.
            case unreadable
        }

        /// Its payload, when this version can read it.
        var payload: ToyPayload? {
            if case .readable(let payload) = ToyPayload.reading(format: record.format, payload: record.payload) { payload } else { nil }
        }
    }

    /// The most own stamps kept: the stamps of the last twenty sends.
    static let ownStampsKept = 20

    // MARK: The person changes the toy (step 1)

    /// Keeps `snapshot` as the toy, changed at `date` on a device of kind `madeOn`.
    ///
    /// When it differs from the toy here in more than time spent, the person changed the toy: the mark is set, the toy
    /// counts as changed since its last send, and a held toy that waited to be taken up is offered instead (the last
    /// case of step 5). Time spent alone changes none of these, nor when the toy last changed. A first toy is marked
    /// unless it is untouched. Returns whether anything changed.
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
            if held?.kind == .toTakeUp { held?.kind = .offered }
        }
        return true
    }

    /// Whether the toy here is untouched, or there is none yet.
    var isUntouched: Bool { toy?.snapshot.isUntouched ?? true }

    // MARK: Sending (steps 2 and 3)

    /// Condition 4 of the gate (section 11): the toy is marked as changed, and no toy is held.
    var isDue: Bool { isChanged && held == nil }

    /// The record to hand to the engine for zone `zone`, the zone the device uses (step 2), or nil when the toy is not
    /// due.
    ///
    /// It is built from the toy as it now is, the base's system fields, and the stamps: the base's, followed by this
    /// version's own. A base from another zone counts as empty; a base without system fields gives a record without
    /// them, which iCloud takes as a new record. A toy that has not changed since it was last handed over keeps that
    /// stamp; otherwise `makeStamp` gives a new one, which becomes the last send and joins the own stamps. The caller
    /// saves this side before handing the record over.
    mutating func recordToSend(in zone: String, appVersion: String, makeStamp: () -> UUID) throws -> RecordToSend? {
        guard isDue, let kept = toy else { return nil }
        let stamp: UUID
        if let lastSend, !lastSend.changedSince {
            stamp = lastSend.stamp
        } else {
            stamp = makeStamp()
            lastSend = LastSend(stamp: stamp, changedSince: false)
            ownStamps = Array((ownStamps + [stamp]).suffix(Self.ownStampsKept))
        }
        let usable = base.flatMap { $0.zone == nil || $0.zone == zone ? $0 : nil }
        let stamps = (usable?.stamps ?? []).filter { $0 != stamp } + [stamp]
        let payload = ToyPayload(
            toy: kept.snapshot, changedAt: kept.changedAt, changedOn: kept.changedOn, appVersion: appVersion,
            stamps: Array(stamps.suffix(ToyPayload.stampsKept))
        )
        return RecordToSend(
            type: CloudRecord.toyType, zone: zone, name: CloudRecord.toyName, systemFields: usable?.systemFields,
            format: ToyPayload.format, payload: try payload.encoded()
        )
    }

    /// iCloud accepted a save of the toy and returned `record`, of the zone the device uses (step 3).
    ///
    /// The record becomes the base, unless it is an earlier version than one the device already holds, its base or a
    /// held toy this version can read: then its answer came late, and the base stays as it is. When its own stamp is the
    /// stamp of the last send, and the toy has not changed since, the mark is cleared.
    mutating func accepted(_ record: CloudRecord) {
        guard case .readable(let payload) = ToyPayload.reading(format: record.format, payload: record.payload) else {
            // The device's own record always reads; should it not, it still is iCloud's latest the device saw.
            base = Base(record, stamps: [])
            return
        }
        if !isEarlierVersion(payload) {
            base = Base(record, stamps: payload.stamps)
        }
        if let lastSend, lastSend.stamp == payload.stamp, !lastSend.changedSince {
            isChanged = false
        }
    }

    /// iCloud no longer knows the record the device meant to change, or reports the Toy record deleted (section 10): the
    /// base is emptied, so that the toy goes out as a new record.
    mutating func forgetBase() {
        base = nil
    }

    // MARK: A toy arrives (step 5)

    /// Which case of step 5 applied to an arriving toy.
    enum Arrival: Equatable {
        /// Case 1: the record this device holds as its base, in the same zone with the same change tag.
        case alreadyTheBase
        /// Its format is higher than this version knows: held as unreadable.
        case heldUnreadable
        /// Its format is known and its content cannot be read: it became the base through its system fields alone.
        case brokenBecameBase
        /// Case 2: an earlier version than one this device holds.
        case earlierVersion
        /// Case 3: this device's own send coming back. It became the base; `sameToy` when the mark was cleared.
        case ownSend(sameToy: Bool)
        /// Case 4: the same toy as the one here. It became the base, and the mark was cleared.
        case sameToy
        /// Cases 5 and 6: held, to be taken up at the next calm moment.
        case toTakeUp
        /// Case 7: held, and offered.
        case offered
    }

    /// A toy arrives, through a fetch or with a refusal, from the zone the device uses: the first case that fits
    /// applies. Whenever it is not ignored by case 1 or case 2, a toy that was held is no longer held.
    @discardableResult
    mutating func arrived(_ record: CloudRecord) -> Arrival {
        if let tag = record.changeTag, let base, base.zone != nil, base.zone == record.zone, base.changeTag == tag {
            return .alreadyTheBase
        }
        let payload: ToyPayload
        switch ToyPayload.reading(format: record.format, payload: record.payload) {
        case .higherFormat:
            held = Held(record: record, kind: .unreadable)
            return .heldUnreadable
        case .broken:
            held = nil
            base = Base(record, stamps: [])
            if !isUntouched { isChanged = true }
            return .brokenBecameBase
        case .readable(let read):
            payload = read
        }
        if isEarlierVersion(payload) {
            return .earlierVersion
        }
        held = nil
        if let stamp = payload.stamp, ownStamps.contains(stamp) {
            base = Base(record, stamps: payload.stamps)
            let same = toy?.snapshot.isSameToy(as: payload.toy) ?? false
            if same { isChanged = false }
            return .ownSend(sameToy: same)
        }
        if let kept = toy, kept.snapshot.isSameToy(as: payload.toy) {
            base = Base(record, stamps: payload.stamps)
            isChanged = false
            return .sameToy
        }
        if !isChanged {
            held = Held(record: record, kind: .toTakeUp)
            return .toTakeUp
        }
        if let lastSend, !lastSend.changedSince, payload.earlierStamps.contains(lastSend.stamp) {
            held = Held(record: record, kind: .toTakeUp)
            return .toTakeUp
        }
        held = Held(record: record, kind: .offered)
        return .offered
    }

    /// Whether `payload` is an earlier version than one this device holds (case 2): its own stamp is among the earlier
    /// stamps of the base, or of a held toy this version can read. A record's earlier stamps never include its own.
    private func isEarlierVersion(_ payload: ToyPayload) -> Bool {
        guard let stamp = payload.stamp else { return false }
        if let base, base.stamps.dropLast().contains(stamp) { return true }
        return held?.payload?.earlierStamps.contains(stamp) ?? false
    }

    // MARK: The held toy, and the person's answer (step 6)

    /// Takes the held toy up at a calm moment (cases 5 and 6). Returns the toy taken up, or nil when no held toy waits
    /// to be taken up.
    mutating func takeUp() -> ToySnapshot? {
        guard held?.kind == .toTakeUp else { return nil }
        return replaceWithHeld()
    }

    /// Play That One: the held toy replaces the toy here and becomes the base, and nothing is sent. Returns the toy now
    /// here, or nil when no toy is offered.
    mutating func playThatOne() -> ToySnapshot? {
        guard held?.kind == .offered else { return nil }
        return replaceWithHeld()
    }

    /// Keep This One: the held toy becomes the base, so that the device has now seen it, and the toy here is marked as
    /// changed. A held toy without system fields gives a base of its stamps alone, and the toy here goes out as a new
    /// record. Returns whether a toy was offered.
    mutating func keepThisOne() -> Bool {
        guard let held, held.kind == .offered, let payload = held.payload else { return false }
        base = Base(held.record, stamps: payload.stamps)
        self.held = nil
        isChanged = true
        return true
    }

    /// Replaces the toy here with the held toy, which becomes the base. The note of the last send is emptied, because the
    /// toy here has then never been handed over. The mark is cleared, unless the held toy has no system fields: its zone
    /// is gone, the zone the device uses does not have it, and the toy is marked as changed instead.
    private mutating func replaceWithHeld() -> ToySnapshot? {
        guard let held, let payload = held.payload else { return nil }
        toy = Kept(snapshot: payload.toy, changedAt: payload.changedAt, changedOn: payload.changedOn)
        base = Base(held.record, stamps: payload.stamps)
        isChanged = held.record.systemFields == nil
        lastSend = nil
        self.held = nil
        return payload.toy
    }

    /// The held toy, when it is held as unreadable and this version can now read it: at each launch it is handled as an
    /// arriving toy, by the caller. It is no longer held.
    mutating func takeHeldUnreadableThatNowReads() -> CloudRecord? {
        guard let held, held.kind == .unreadable, held.payload != nil else { return nil }
        self.held = nil
        return held.record
    }

    // MARK: Leaving a zone (section 9), a purge, another account

    /// Leaves every zone but `kept`: the base and the held toy's system fields are emptied when they belong to another
    /// zone, and when the base did, the toy is marked as changed unless it is untouched.
    mutating func leaveZones(keeping kept: String?) {
        if let zone = base?.zone, zone != kept {
            base = nil
            if !isUntouched { isChanged = true }
        }
        if var held, let zone = held.record.zone, zone != kept {
            held.record = held.record.withoutSystemFields
            self.held = held
        }
    }

    /// Puts the toy back to `untouched` and empties its notes: the mark, the base, the note of the last send, the own
    /// stamps and any held toy.
    mutating func putBack(to untouched: Kept) {
        self = ToySide(toy: untouched)
    }
}
