#if DEBUG
import CoreData
import Foundation
import os
import Records
import SwiftData

/// Creates CloudKit's development schema from the models: every record type and field, which saving records alone
/// might not create, and which Apple's TN3164 says must all exist before sync works. It follows Apple's example in
/// "Syncing model data across a person's devices", with three differences:
/// - It runs only when a launch asks for it, with `-cloudkit-schema create`, never at every launch: Apple's sample for
///   sharing Core Data objects says not to run it in the normal development process, it blocks other CloudKit work
///   while it runs, and it would reach iCloud even with sync off.
/// - It uses a store file of its own, made for it and removed after, so that the app's iCloud store is never opened by
///   two frameworks, nor at all with sync off.
/// - It prints the records it makes (`printSchema`), so that the log shows the names of the record types and fields.
///
/// `-cloudkit-schema print` only checks the models and prints the records, uploading nothing (`dryRun`): the way to see
/// what a change to the models would add before creating it. Only a debug build with the iCloud entitlement, talking to
/// the development environment, runs either.
enum CloudSchema {
    private static let log = Logger(subsystem: "com.chentianren.PlayNineRings", category: "iCloud")

    /// What this launch asks for: `create` or `print`, or nil.
    private static var asked: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-cloudkit-schema"), index + 1 < arguments.count else { return nil }
        return ["create", "print"].contains(arguments[index + 1]) ? arguments[index + 1] : nil
    }

    /// Creates the development schema, or prints it, when this launch asks for it.
    static func createIfAsked() {
        guard let asked else { return }
        let uploads = asked == "create"
        guard CloudAccess.isEntitled else {
            return log.error("The CloudKit schema was not created: this build does not have the iCloud entitlement.")
        }
        guard CloudAccess.environment == .development else {
            return log.error("The CloudKit schema was not created: this build talks to production, whose schema is promoted, not made.")
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "NineRings schema \(UUID().uuidString).store")
        defer { removeStore(at: file) }
        do {
            // Apple's example: the container is let go within the pool, before anything else opens a store.
            try autoreleasepool {
                let description = NSPersistentStoreDescription(url: file)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: RecordStore.cloudContainer)
                // Loaded synchronously, so that loading finishes before the schema is created.
                description.shouldAddStoreAsynchronously = false
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [FinishedPlay.self, SavedToy.self]) else {
                    throw CocoaError(.featureUnsupported)
                }
                let container = NSPersistentCloudKitContainer(name: "NineRings", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                var loadError: (any Error)?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }
                log.notice("\(uploads ? "Creating" : "Printing", privacy: .public) the CloudKit development schema of \(RecordStore.cloudContainer, privacy: .public)…")
                // The names CloudKit gives them, as Apple's "Reading CloudKit Records for Core Data" maps an entity
                // and its attributes: fixed for good once the schema is in production.
                for entity in model.entities.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
                    let fields = entity.attributesByName.keys.sorted().map { "CD_\($0)" }.joined(separator: ", ")
                    log.notice("Record type CD_\(entity.name ?? "", privacy: .public): \(fields, privacy: .public)")
                }
                try container.initializeCloudKitSchema(options: uploads ? [.printSchema] : [.printSchema, .dryRun])
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            log.notice("The CloudKit development schema was \(uploads ? "created" : "printed", privacy: .public).")
        } catch {
            log.error("The CloudKit schema was not created: \(String(describing: error), privacy: .public)")
        }
    }

    /// Removes the store at `file` with the files SQLite and Core Data keep beside it.
    private static func removeStore(at file: URL) {
        let folder = file.deletingLastPathComponent()
        let name = file.lastPathComponent
        let beside = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for item in beside where item.hasPrefix(name) || item.hasPrefix(".\(file.deletingPathExtension().lastPathComponent)_SUPPORT") {
            try? FileManager.default.removeItem(at: folder.appending(path: item))
        }
    }
}
#endif
