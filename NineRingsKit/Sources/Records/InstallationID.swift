/// The id of one installation of the app on one device, which names its `SavedToy` and its changes (``Lineage``).
///
/// Two devices must never share an id, or both would write one record. The settings and the device's store travel with
/// a backup restored onto another device; a keychain item kept for this device only does not, as Apple documents. So the
/// id is kept in such an item, and a copy of it in the device's store: its toy is kept under it. The rules:
/// - When the keychain's id is the store's, it is this installation's.
/// - Otherwise this installation takes a new id. When the keychain has another id or none while the store keeps a toy,
///   the store came from another device: the toy kept there is given the new id, so that the play goes on here, and
///   the old id stays the other device's. When the store keeps no toy, its count of changes is lost with it, so the old
///   id is not taken up again either: a change it made could be named twice.
/// - When the keychain cannot be used at all, the store's id is kept, or a new one made, and nothing is written there.
public enum InstallationID {
    /// What the keychain holds.
    public enum Keychain: Sendable, Equatable {
        case holds(String)
        case holdsNone
        /// The keychain could not be read or written, as in a build without the keychain's entitlement.
        case unusable
    }

    /// The id this launch uses, what to write to the keychain, and whose toy in the device's store becomes this
    /// installation's.
    public struct Resolution: Sendable, Equatable {
        public let id: String
        /// Whether `id` is to be written to the keychain.
        public let writesKeychain: Bool
        /// The id the device's store keeps its toy under, when that toy is to be given `id`.
        public let givesToyFrom: String?

        public init(id: String, writesKeychain: Bool, givesToyFrom: String?) {
            self.id = id
            self.writesKeychain = writesKeychain
            self.givesToyFrom = givesToyFrom
        }
    }

    /// The id for a launch whose keychain holds `keychain` and whose device's store keeps its toy under `store`;
    /// `newID` makes an id when one is needed.
    public static func resolve(keychain: Keychain, store: String?, newID: () -> String) -> Resolution {
        switch keychain {
        case .holds(let id) where id == store:
            return Resolution(id: id, writesKeychain: false, givesToyFrom: nil)
        case .holds, .holdsNone:
            return Resolution(id: newID(), writesKeychain: true, givesToyFrom: store)
        case .unusable:
            return Resolution(id: store ?? newID(), writesKeychain: false, givesToyFrom: nil)
        }
    }
}
