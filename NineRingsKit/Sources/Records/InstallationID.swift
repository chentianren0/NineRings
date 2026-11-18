import Foundation

/// The id of one installation of the app on one device, which names its `SavedToy` and its changes (``Lineage``).
///
/// Two devices must never share an id, or both would write one record; and an installation must never name a change
/// twice, or a later change could count as one another device already knows, and be replaced by itself. Both hold while
/// the device's store is this installation's own, unbroken: never brought from another device, and never gone back to
/// a backup with its count of changes. So the id is kept in three places, and stands only when every one of them that
/// can be read holds the store's id:
/// - the device's store, which keeps its toy under it, and travels with every backup;
/// - a keychain item kept for this device only, which Apple documents as not moving to another device with a backup,
///   though it comes back with a backup restored onto the same device;
/// - a copy in a folder left out of backups, which a restore does not bring back.
///
/// A store restored from another device's backup lacks this device's keychain id; one restored onto the same device
/// lacks the copy left out of backups. Either way this installation takes a new id, and the toy the store keeps is given
/// to it with its lineage, so that the play goes on here and every change it knew stays known, while the old id's own
/// later changes stay that id's. When the store keeps no toy, its count of changes is lost with it, and a new id is made
/// too. A place that cannot be used, such as a keychain in a build without its entitlement, is left out, and nothing is
/// written there.
public enum InstallationID {
    /// What one of the places outside the store holds.
    public enum Copy: Sendable, Equatable {
        case holds(String)
        case holdsNone
        /// The place could not be read or written, as a keychain in a build without the keychain's entitlement.
        case unusable
    }

    /// The id this launch uses, the places to write it to, and whose toy in the device's store becomes this
    /// installation's.
    public struct Resolution: Sendable, Equatable {
        public let id: String
        /// Whether `id` is to be written to the keychain.
        public let writesKeychain: Bool
        /// Whether `id` is to be written to the copy left out of backups.
        public let writesCopyLeftOutOfBackups: Bool
        /// The id the device's store keeps its toy under, when that toy is to be given `id`.
        public let givesToyFrom: String?

        public init(id: String, writesKeychain: Bool, writesCopyLeftOutOfBackups: Bool, givesToyFrom: String?) {
            self.id = id
            self.writesKeychain = writesKeychain
            self.writesCopyLeftOutOfBackups = writesCopyLeftOutOfBackups
            self.givesToyFrom = givesToyFrom
        }
    }

    /// The id for a launch whose keychain holds `keychain`, whose copy left out of backups holds `leftOutOfBackups`, and
    /// whose device's store keeps its toy under `store`; `newID` makes an id when one is needed.
    public static func resolve(keychain: Copy, leftOutOfBackups: Copy, store: String?, newID: () -> String) -> Resolution {
        let places = [keychain, leftOutOfBackups]
        if let store, places.allSatisfy({ $0 == .holds(store) || $0 == .unusable }) {
            return Resolution(id: store, writesKeychain: false, writesCopyLeftOutOfBackups: false, givesToyFrom: nil)
        }
        return Resolution(
            id: newID(), writesKeychain: keychain != .unusable, writesCopyLeftOutOfBackups: leftOutOfBackups != .unusable,
            givesToyFrom: store
        )
    }

    /// The copy of the id left out of backups, a small file in the folder of the stores that a restore does not bring
    /// back (``RecordStore/cloudFolder(in:)``).
    public struct CopyLeftOutOfBackups: Sendable {
        let file: URL

        /// The copy for the stores kept in `folder`.
        public init(folder: URL) {
            file = RecordStore.cloudFolder(in: folder).appending(path: "Installation")
        }

        /// What it holds: none when there is no file, as after a restore; unusable when the file cannot be read.
        public func read() -> Copy {
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return .holdsNone }
            guard let data = try? Data(contentsOf: file), let id = String(data: data, encoding: .utf8) else { return .unusable }
            return id.isEmpty ? .holdsNone : .holds(id)
        }

        /// Writes `id`, in place of any id there, in the folder left out of backups. Returns whether it was written.
        @discardableResult
        public func write(_ id: String) -> Bool {
            do {
                try RecordStore.prepareCloudFolder(file.deletingLastPathComponent())
                try Data(id.utf8).write(to: file, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }
}
