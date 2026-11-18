import Foundation
import Records
import Security

/// The installation's id in the keychain, in an item kept for this device only: Apple documents such an item as not
/// moving to another device with a backup (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). On the Mac it is in the
/// data protection keychain, which behaves as on iPhone and iPad. It never syncs through iCloud Keychain.
///
/// There is one item for each folder the stores are kept in, named after it: a debug build and the App Store version
/// share the keychain on a Mac, and on a device when one is installed over the other, but each keeps its own stores, so
/// each needs its own id. One item for both would tell each build, at every launch, that its store came from another
/// device.
///
/// The rule that decides the id from it and the device's store is ``InstallationID``, in the package.
struct InstallationKeychain {
    private static let service = "com.chentianren.PlayNineRings.installation"
    /// The folder's name.
    private let account: String

    /// The item for the stores kept in `folder`.
    init(folder: URL) {
        account = folder.lastPathComponent
    }

    private var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// What the keychain holds. Any answer but an id or "no such item" is a keychain that cannot be used now, as in a
    /// build without the keychain's entitlement, or on an iPhone not yet unlocked since it started.
    func read() -> InstallationID.Copy {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let id = String(data: data, encoding: .utf8), !id.isEmpty else { return .unusable }
            return .holds(id)
        case errSecItemNotFound:
            return .holdsNone
        default:
            return .unusable
        }
    }

    /// Writes `id`, in place of any id there. Returns whether it was written.
    @discardableResult
    func write(_ id: String) -> Bool {
        SecItemDelete(item as CFDictionary)
        var attributes = item
        attributes[kSecValueData as String] = Data(id.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
