import Foundation
import Session
import SwiftData

/// Reads and writes the kept toy and the records of finished plays in one store.
///
/// It takes a container and never makes its own, so that the app decides where the records live (the device's store
/// now; with iCloud, the store that syncs). The rules it keeps:
/// - Each installation keeps one `SavedToy`, changed in place, and only when what it keeps has changed. Its `changedAt`
///   is when the toy last changed: time spent on the play is kept too, but does not make the toy newer, so that with
///   iCloud the toy that changed last is the one played last, not the one looked at last.
/// - A finished play is written once: a play whose id is already recorded is not written again.
/// - The history is every `FinishedPlay`, newest first, each play once. Two with the same id are one play, as sync can
///   bring together: the earlier shows, and nothing is deleted, so that two devices cleaning up at once can never
///   delete both.
@MainActor
public final class RecordStore {
    /// The models it keeps.
    public static let schema = Schema([FinishedPlay.self, SavedToy.self])

    /// The folder the stores live in: the app's own, inside Application Support, so that a build without the app's
    /// sandbox does not write beside other apps' files.
    public static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "NineRings", directoryHint: .isDirectory)
    }

    /// The folder a debug build keeps its stores in: one of its own, beside ``folder``. A debug build signed for a
    /// device shares the App Store version's container on it, Application Support included, so that only a folder of
    /// its own keeps its test plays out of the person's history.
    public static var debugFolder: URL {
        URL.applicationSupportDirectory.appending(path: "NineRings Debug", directoryHint: .isDirectory)
    }

    /// Where a build keeps its stores. The app chooses once, at launch: a release build in ``folder``, a debug build in
    /// ``debugFolder`` or in memory. Every store is opened in a place, so that no build reaches a file by default.
    public enum Place: Sendable, Equatable {
        /// In files in this folder.
        case folder(URL)
        /// In memory: the records last as long as the launch, and nothing reaches a file.
        case memory
    }

    /// The models the device's own store keeps: those of ``schema``, and the toy, the finished plays and the notes the
    /// iCloud rules keep (``ICloudSync``), which never go into a store that syncs through SwiftData.
    static let deviceSchema = Schema([FinishedPlay.self, SavedToy.self, KeptToy.self, KeptPlay.self, SyncNotes.self])

    /// The device's own store in `place`, which never syncs: `cloudKitDatabase` is `.none` explicitly, so that the
    /// iCloud entitlement, once the app has it, does not make it sync.
    public static func deviceConfiguration(in place: Place) -> ModelConfiguration {
        switch place {
        case .folder(let folder):
            ModelConfiguration("Device", schema: deviceSchema, url: folder.appending(path: "Device.store"), cloudKitDatabase: .none)
        case .memory:
            ModelConfiguration("Device", schema: deviceSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
    }

    /// A container for the device's own store in `place`.
    public static func deviceContainer(in place: Place) throws -> ModelContainer {
        if case .folder(let folder) = place {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return try ModelContainer(for: deviceSchema, configurations: deviceConfiguration(in: place))
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

    /// Keeps `snapshot` as `installation`'s toy, at `date`. Returns whether anything was written: nothing is when the
    /// snapshot kept is the same. `changedAt` becomes `date` only when the toy changed, not when only the time spent did;
    /// then the toy's lineage counts a change of `installation` too (``Lineage``). A first toy kept is a change unless
    /// nobody has touched it.
    @discardableResult
    public func keep(_ snapshot: ToySnapshot, installation: String, appVersion: String, at date: Date = .now) throws -> Bool {
        let data = try snapshot.encoded()
        let saved: SavedToy
        if let existing = try savedToy(installation: installation) {
            guard existing.snapshot != data || existing.format != ToySnapshot.format else { return false }
            saved = existing
            if !(existing.toy?.isSameToy(as: snapshot) ?? false) {
                saved.changedAt = date
                try saved.setLineage(saved.toyLineage.changed(by: installation))
            }
        } else {
            saved = SavedToy(installation: installation)
            saved.changedAt = date
            if !snapshot.isUntouched { try saved.setLineage(Lineage().changed(by: installation)) }
            context.insert(saved)
        }
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

    /// Every finished play, newest first, each play once: of two with the same id the earlier shows, and nothing is
    /// deleted. Copies finished at the same moment are told apart by where and by which version they were made, so that
    /// every device shows the same one.
    public func history() throws -> [FinishedPlay] {
        let all = try context.fetch(FetchDescriptor<FinishedPlay>(sortBy: [
            SortDescriptor(\.finishedAt, order: .forward), SortDescriptor(\.madeOn), SortDescriptor(\.appVersion),
        ]))
        var seen = Set<UUID>()
        return all.filter { seen.insert($0.playID).inserted }.reversed()
    }
}
