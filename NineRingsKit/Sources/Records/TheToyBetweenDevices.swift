import Foundation
import Session
import SwiftData

// The toy between devices: each installation writes only its own `SavedToy` in the store that syncs, so that two devices
// never change the same record, and reads the others' to tell, by their lineages, which toy is the later.

extension SavedToy {
    /// What the toy was made knowing. A lineage that cannot be read counts as none, as a toy saved before lineages has.
    public var toyLineage: Lineage {
        Lineage(data: lineage) ?? Lineage()
    }

    func setLineage(_ value: Lineage) throws {
        lineage = try value.encoded()
    }
}

/// Another installation's toy, as the store that syncs brings it: a value, so that it outlives the store it was read from.
public struct OtherToy: Sendable, Equatable {
    public var installation: String
    public var lineage: Lineage
    /// The toy, one this build can bring back.
    public var snapshot: ToySnapshot
    /// When it last changed, by the clock of the device that changed it: for ordering two toys the person sees either
    /// way, never for telling which toy is the later.
    public var changedAt: Date
    public var appVersion: String

    public init(installation: String, lineage: Lineage, snapshot: ToySnapshot, changedAt: Date, appVersion: String) {
        self.installation = installation
        self.lineage = lineage
        self.snapshot = snapshot
        self.changedAt = changedAt
        self.appVersion = appVersion
    }
}

/// What this installation does about the other installations' toys, from its own toy's lineage. The rules:
/// - A toy made knowing this one, which this one was not made knowing, is the later, and replaces this one by itself.
///   Then the others are looked at again against the toy taken up, until none is later.
/// - A toy this one was made knowing, and the same toy, change nothing.
/// - A toy that neither was made knowing is a play parted in two: nothing is replaced, and it is offered, so that the
///   person takes it up or keeps their own.
/// - Which of two toys that are both later, or both parted, is taken or offered first goes by when each last changed,
///   the most recent first: only the order of two outcomes the person sees either way depends on a clock, never what
///   replaces what.
public struct ToyDecision: Sendable, Equatable {
    /// The toy to take up by itself, or nil when none is later than this installation's.
    public let takeUp: OtherToy?
    /// This installation's lineage once that toy is taken up: all the toys taken up on the way are known.
    public let lineage: Lineage
    /// A toy to offer, the play having parted in two, or nil.
    public let offer: OtherToy?

    public init(mine: Lineage, others: [OtherToy]) {
        let ordered = others.sorted { ($0.changedAt, $0.installation) > ($1.changedAt, $1.installation) }
        var lineage = mine
        var taken: OtherToy?
        // Each toy taken up knows one more head, and knowing only grows, so this ends.
        while let later = ordered.first(where: { lineage.compare(with: $0.lineage) == .otherIsLater }) {
            lineage = lineage.takingUp(later.lineage)
            taken = later
        }
        takeUp = taken
        self.lineage = lineage
        offer = ordered.first { lineage.compare(with: $0.lineage) == .parted }
    }
}

extension RecordStore {
    var mainContext: ModelContext { container.mainContext }

    /// Every record of `installation`'s toy, the one changed last first.
    func toyRecords(of installation: String) throws -> [SavedToy] {
        try mainContext.fetch(FetchDescriptor<SavedToy>(
            predicate: #Predicate { $0.installation == installation },
            sortBy: [SortDescriptor(\.changedAt, order: .reverse)]
        ))
    }

    /// `installation`'s toy: the record changed last, should there be more than one.
    func latestToy(of installation: String) throws -> SavedToy? {
        try toyRecords(of: installation).first
    }

    /// What `installation`'s toy was made knowing; a toy nobody has changed when it keeps none.
    public func lineage(installation: String) throws -> Lineage {
        try latestToy(of: installation)?.toyLineage ?? Lineage()
    }

    /// The installation whose toy this store keeps, the one changed last should there be more: in the device's store,
    /// this installation's id as the store knows it.
    public func installationKept() throws -> String? {
        var descriptor = FetchDescriptor<SavedToy>(sortBy: [SortDescriptor(\.changedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try mainContext.fetch(descriptor).first?.installation
    }

    /// Gives the toy kept under `old` to `new`, as when the store came from another device and this installation has a
    /// new id: the toy and its lineage are unchanged, so that the play goes on and every change it knew stays known.
    /// Nothing changes when `new` keeps a toy already.
    public func giveToy(of old: String, to new: String) throws {
        guard try latestToy(of: new) == nil else { return }
        let toys = try mainContext.fetch(FetchDescriptor<SavedToy>(predicate: #Predicate { $0.installation == old }))
        guard !toys.isEmpty else { return }
        for toy in toys { toy.installation = new }
        try mainContext.save()
    }

    /// Takes up `other` as `installation`'s toy, with `lineage` (``ToyDecision/lineage``): the toy and when it last changed
    /// are the other's.
    public func takeUp(_ other: OtherToy, lineage: Lineage, installation: String, appVersion: String) throws {
        let saved: SavedToy
        if let existing = try latestToy(of: installation) {
            saved = existing
        } else {
            saved = SavedToy(installation: installation)
            mainContext.insert(saved)
        }
        saved.snapshot = try other.snapshot.encoded()
        saved.format = ToySnapshot.format
        saved.changedAt = other.changedAt
        saved.appVersion = appVersion
        try saved.setLineage(lineage)
        try mainContext.save()
    }

    /// Keeps `installation`'s own toy over `other`, the play having parted in two: a change of `installation` made knowing
    /// the other toy, so that the other installation follows. The toy and `changedAt` stay as they are. Returns false when
    /// `installation` keeps no toy.
    @discardableResult
    public func keepOwnToy(over other: OtherToy, installation: String) throws -> Bool {
        guard let saved = try latestToy(of: installation) else { return false }
        try saved.setLineage(saved.toyLineage.keeping(over: other.lineage, by: installation))
        try mainContext.save()
        return true
    }

    /// Writes `installation`'s toy as `source` keeps it into this store, the store that syncs. Returns whether anything was written: nothing is when this store has it so already, so that nothing is sent for
    /// nothing. Should this store hold more than one record of `installation`, as a store fetched again from iCloud
    /// might, the others are deleted: only this installation writes its own.
    @discardableResult
    public func copyToy(of installation: String, from source: RecordStore) throws -> Bool {
        guard let kept = try source.latestToy(of: installation) else { return false }
        let records = try toyRecords(of: installation)
        var changed = false
        let saved: SavedToy
        if let first = records.first {
            saved = first
            for extra in records.dropFirst() {
                mainContext.delete(extra)
                changed = true
            }
        } else {
            saved = SavedToy(installation: installation)
            mainContext.insert(saved)
            changed = true
        }
        changed = saved.copy(from: kept) || changed
        guard changed else { return false }
        try mainContext.save()
        return true
    }

    /// Every other installation's toy in this store that this build can bring back: one for each installation, the later
    /// by their lineages should it have more than one record.
    public func otherToys(than installation: String) throws -> [OtherToy] {
        let records = try mainContext.fetch(FetchDescriptor<SavedToy>(predicate: #Predicate { $0.installation != installation }))
        var latest: [String: OtherToy] = [:]
        for record in records {
            guard let toy = record.otherToy else { continue }
            if let known = latest[toy.installation] {
                switch known.lineage.compare(with: toy.lineage) {
                case .otherIsLater: latest[toy.installation] = toy
                case .parted where toy.changedAt > known.changedAt: latest[toy.installation] = toy
                default: break
                }
            } else {
                latest[toy.installation] = toy
            }
        }
        return latest.values.sorted { $0.installation < $1.installation }
    }
}

extension SavedToy {
    /// The fields a copy of a saved toy carries: every stored property. A test holds it to the schema, so that a field
    /// added later is copied too.
    static let copiedFields: Set<String> = ["installation", "changedAt", "format", "snapshot", "appVersion", "lineage"]

    /// Makes this record a copy of `other`. Returns whether anything changed.
    fileprivate func copy(from other: SavedToy) -> Bool {
        var changed = false
        func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SavedToy, Value>, _ value: Value) {
            guard self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            changed = true
        }
        set(\.installation, other.installation)
        set(\.changedAt, other.changedAt)
        set(\.format, other.format)
        set(\.snapshot, other.snapshot)
        set(\.appVersion, other.appVersion)
        set(\.lineage, other.lineage)
        return changed
    }

    /// Another installation's toy as a value, or nil when this build cannot bring it back or read its lineage.
    fileprivate var otherToy: OtherToy? {
        guard let snapshot = toy, snapshot.toy != nil, let lineage = Lineage(data: lineage) else { return nil }
        return OtherToy(installation: installation, lineage: lineage, snapshot: snapshot, changedAt: changedAt, appVersion: appVersion)
    }
}
