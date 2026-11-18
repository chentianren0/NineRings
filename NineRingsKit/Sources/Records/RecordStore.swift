import Foundation
import Session
import SwiftData

/// Reads and writes the kept toy and the records of finished plays in one store.
///
/// It takes a container and never makes its own, so that the app decides where the records live (the device's store
/// now; with iCloud, the store that syncs). The rules it keeps:
/// - Each installation keeps one `SavedToy`, changed in place, and only when the toy kept has changed.
/// - A finished play is written once: a play whose id is already recorded is not written again.
/// - The history is every `FinishedPlay`, newest first. Two with the same id are one play: the earlier stays and the
///   other is deleted.
@MainActor
public final class RecordStore {
    /// The models it keeps.
    public static let schema = Schema([FinishedPlay.self, SavedToy.self])

    /// The folder the stores live in: the app's own, inside Application Support, so that a build without the app's
    /// sandbox does not write beside other apps' files.
    public static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "NineRings", directoryHint: .isDirectory)
    }

    /// The device's own store, which never syncs: `cloudKitDatabase` is `.none` explicitly, so that the iCloud
    /// entitlement, once the app has it, does not make it sync. In memory for tests.
    public static func deviceConfiguration(inMemory: Bool = false) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration("Device", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return ModelConfiguration("Device", schema: schema, url: folder.appending(path: "Device.store"), cloudKitDatabase: .none)
    }

    /// A container for the device's own store.
    public static func deviceContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return try ModelContainer(for: schema, configurations: deviceConfiguration(inMemory: inMemory))
    }

    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: The kept toy

    /// The toy `installation` kept, or nil when it kept none this build can read.
    public func keptToy(installation: String) throws -> ToySnapshot? {
        try savedToy(installation: installation)?.toy
    }

    /// Keeps `snapshot` as `installation`'s toy, changed at `date`. Returns whether anything was written: nothing is when
    /// the toy kept is the same.
    @discardableResult
    public func keep(_ snapshot: ToySnapshot, installation: String, appVersion: String, at date: Date = .now) throws -> Bool {
        let data = try snapshot.encoded()
        let saved: SavedToy
        if let existing = try savedToy(installation: installation) {
            guard existing.snapshot != data || existing.format != ToySnapshot.format else { return false }
            saved = existing
        } else {
            saved = SavedToy(installation: installation)
            context.insert(saved)
        }
        saved.changedAt = date
        saved.format = ToySnapshot.format
        saved.snapshot = data
        saved.appVersion = appVersion
        try context.save()
        return true
    }

    /// The installation's `SavedToy`: the one changed last, should there be more than one.
    private func savedToy(installation: String) throws -> SavedToy? {
        var descriptor = FetchDescriptor<SavedToy>(
            predicate: #Predicate { $0.installation == installation },
            sortBy: [SortDescriptor(\.changedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Finished plays

    /// Records `play`, made on `madeOn` by version `appVersion`, unless a play with its id is already recorded.
    public func record(_ play: PlayRecord, madeOn: MadeOn, appVersion: String) throws {
        let id = play.playID
        let recorded = try context.fetchCount(FetchDescriptor<FinishedPlay>(predicate: #Predicate { $0.playID == id }))
        guard recorded == 0 else { return }
        context.insert(FinishedPlay(play, madeOn: madeOn, appVersion: appVersion))
        try context.save()
    }

    /// Every finished play, newest first, each play once: of two with the same id, the earlier stays and the other is
    /// deleted.
    public func history() throws -> [FinishedPlay] {
        let all = try context.fetch(FetchDescriptor<FinishedPlay>(sortBy: [SortDescriptor(\.finishedAt, order: .forward)]))
        var seen = Set<UUID>()
        var kept: [FinishedPlay] = []
        for play in all {
            if seen.insert(play.playID).inserted {
                kept.append(play)
            } else {
                context.delete(play)
            }
        }
        if context.hasChanges { try context.save() }
        return kept.reversed()
    }
}
