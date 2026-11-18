import Foundation
import Puzzle
import Session
import SwiftData

// The two stores. The device's store never syncs; the iCloud store does, through the person's own iCloud. Each has a
// container of its own and is always opened the same way: Apple documents neither switching sync on and off for one
// store nor one container holding the same models in two stores. Sync decides where the finished plays live, and moving
// and copying them between the two stores is here.

extension RecordStore {
    // MARK: The iCloud store

    /// The container in iCloud. It can never be renamed or deleted, and only SwiftData writes to it.
    public static let cloudContainer = "iCloud.com.chentianren.PlayNineRings"

    /// CloudKit's two environments. Builds from Xcode and the simulator use development, which can be reset at any time;
    /// TestFlight and the App Store use production, whose schema can only grow.
    public enum CloudEnvironment: String, Sendable, CaseIterable {
        case development = "Development"
        case production = "Production"
    }

    /// The folder left out of backups in a place's `folder`: the iCloud stores, whose records can be fetched again and
    /// whose restored copy would do what is not documented, and the copy of the installation's id that tells a store
    /// restored from a backup (``InstallationID``). The device's store stays in backups, since with sync off it is the
    /// only copy.
    public nonisolated static func cloudFolder(in folder: URL) -> URL {
        folder.appending(path: "iCloud", directoryHint: .isDirectory)
    }

    /// Makes `cloudFolder` if it is missing, and marks it left out of backups: at every use, since Apple notes that some
    /// file operations clear the mark.
    nonisolated static func prepareCloudFolder(_ cloudFolder: URL) throws {
        try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = cloudFolder
        try folder.setResourceValues(values)
    }

    /// The iCloud store in `place` for `environment`.
    /// - In a folder, a file of its own for each environment, in ``cloudFolder(in:)``: one file is only ever opened
    ///   against one environment, though a debug build and the App Store version share their app's container on a Mac,
    ///   and on a device when one is installed over the other. A debug build's place is its own folder, so it never
    ///   opens a release build's file.
    /// - In memory, a stand-in that never syncs: a launch in memory opens no iCloud store at all.
    public static func cloudConfiguration(in place: Place, environment: CloudEnvironment) -> ModelConfiguration {
        switch place {
        case .folder(let folder):
            ModelConfiguration(
                "iCloud", schema: schema, url: cloudFolder(in: folder).appending(path: "\(environment.rawValue).store"),
                cloudKitDatabase: .private(cloudContainer)
            )
        case .memory:
            ModelConfiguration("iCloud", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
    }

    /// Opens the iCloud store in `place` for `environment`. In a folder that starts syncing it: only a build with the
    /// iCloud entitlement may ask for that, and only with sync on. In memory it opens the stand-in, as tests do.
    public static func cloudContainer(in place: Place, environment: CloudEnvironment) throws -> ModelContainer {
        if case .folder(let folder) = place {
            try prepareCloudFolder(cloudFolder(in: folder))
        }
        return try ModelContainer(for: schema, configurations: cloudConfiguration(in: place, environment: environment))
    }

    // MARK: Moving and copying the finished plays

    /// Moves every finished play in this store to `target`, as sync going on moves the device's records to the iCloud
    /// store. A play whose id `target` already holds is not written again. A batch is removed from here only after
    /// `target` has saved it, so that a move cut short is taken up by moving again: what reached `target` is skipped
    /// there and removed here. Returns how many plays were written to `target`.
    @discardableResult
    public func moveFinishedPlays(to target: RecordStore, batchSize: Int = 100) throws -> Int {
        var written = 0
        while true {
            var descriptor = FetchDescriptor<FinishedPlay>(sortBy: [SortDescriptor(\.finishedAt)])
            descriptor.fetchLimit = batchSize
            let batch = try mainContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            written += try target.insertCopies(of: batch)
            for play in batch { mainContext.delete(play) }
            try mainContext.save()
        }
        return written
    }

    /// Copies every finished play in this store that `target` does not hold to `target`, as turning sync off copies the
    /// iCloud store's records to the device's store. Nothing here changes. Copying again after a copy cut short writes
    /// what is still missing. Returns how many plays were written to `target`.
    @discardableResult
    public func copyFinishedPlays(to target: RecordStore, batchSize: Int = 100) throws -> Int {
        var written = 0
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<FinishedPlay>(sortBy: [SortDescriptor(\.finishedAt)])
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try mainContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            written += try target.insertCopies(of: batch)
            offset += batch.count
        }
        return written
    }

    /// Inserts a copy of each of `plays` whose id this store does not hold yet, one for each id, and saves. Returns how
    /// many were inserted.
    private func insertCopies(of plays: [FinishedPlay]) throws -> Int {
        let ids = plays.map(\.playID)
        let held = try mainContext.fetch(FetchDescriptor<FinishedPlay>(predicate: #Predicate { ids.contains($0.playID) }))
        var present = Set(held.map(\.playID))
        var inserted = 0
        for play in plays where present.insert(play.playID).inserted {
            mainContext.insert(FinishedPlay.copy(of: play))
            inserted += 1
        }
        if mainContext.hasChanges { try mainContext.save() }
        return inserted
    }
}

extension FinishedPlay {
    /// The fields a copy of a finished play carries: every stored property. A test holds it to the schema, so that a
    /// field added later is copied too.
    static let copiedFields: Set<String> = [
        "playID", "finishedAt", "startedAt", "startRings", "endRings", "moves", "undos", "movesPlayedForThePerson",
        "secondsSpent", "madeOn", "appVersion", "rules",
    ]

    /// A copy of `other`, field for field, for another store: a record this build does not understand is copied as it is.
    static func copy(of other: FinishedPlay) -> FinishedPlay {
        let placeholder = PlayRecord(
            playID: other.playID, startedAt: other.startedAt, finishedAt: other.finishedAt, startRings: .allOn,
            endRings: .allOff, moves: 0, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 0
        )
        let copy = FinishedPlay(placeholder, madeOn: .Mac, appVersion: other.appVersion)
        copy.playID = other.playID
        copy.finishedAt = other.finishedAt
        copy.startedAt = other.startedAt
        copy.startRings = other.startRings
        copy.endRings = other.endRings
        copy.moves = other.moves
        copy.undos = other.undos
        copy.movesPlayedForThePerson = other.movesPlayedForThePerson
        copy.secondsSpent = other.secondsSpent
        copy.madeOn = other.madeOn
        copy.appVersion = other.appVersion
        copy.rules = other.rules
        return copy
    }
}
