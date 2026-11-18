import CloudKit
import Foundation
import Observation
import os
import Records
#if os(macOS)
import Security
#else
import MachO
#endif

/// What this build may do with iCloud: whether it may use the container at all, and which of CloudKit's environments
/// it talks to.
///
/// A build may use iCloud only when its entitlements name the container: Apple's `CKContainer.init(identifier:)` asks
/// for the identifier to be in them, and making one without them stops the app. A build signed by Xcode carries them;
/// a build made without signing, as GitHub's checks make, does not, and never opens the iCloud store.
///
/// The environment comes from how the build was signed, as CloudKit decides it from the
/// `com.apple.developer.icloud-container-environment` entitlement. A build signed for development carries none and
/// talks to development; TestFlight and the App Store sign it with `Production`. The iCloud store has a file for each
/// environment, so that the two never meet in one file.
enum CloudAccess {
    /// Whether the entitlements name the app's container.
    static let isEntitled: Bool = {
        #if os(macOS)
        let containers = entitlement("com.apple.developer.icloud-container-identifiers") as? [String]
        return containers?.contains(RecordStore.cloudContainer) ?? false
        #elseif targetEnvironment(simulator)
        // A simulator build keeps its entitlements in its executable, where Xcode writes them when it signs to run.
        let containers = simulatorEntitlements?["com.apple.developer.icloud-container-identifiers"] as? [String]
        return containers?.contains(RecordStore.cloudContainer) ?? false
        #else
        // On a device nothing runs that is not signed, and this target is always signed with its entitlements.
        return true
        #endif
    }()

    /// The environment this build talks to.
    static let environment: RecordStore.CloudEnvironment = {
        #if os(macOS)
        let value = entitlement("com.apple.developer.icloud-container-environment")
        let isProduction = (value as? String) == "Production" || (value as? [String]) == ["Production"]
        return isProduction ? .production : .development
        #elseif targetEnvironment(simulator)
        // Apple: the simulator works only with the development environment.
        return .development
        #else
        // A build installed from Xcode carries the profile it was signed with, a development one; TestFlight and the
        // App Store carry none.
        return developmentProfile ? .development : .production
        #endif
    }()

    #if os(macOS)
    private static func entitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
    #elseif targetEnvironment(simulator)
    private static var simulatorEntitlements: [String: Any]? {
        guard let header = unsafe _dyld_get_image_header(0) else { return nil }
        var size: UInt = 0
        let data: Data? = unsafe header.withMemoryRebound(to: mach_header_64.self, capacity: 1) { header in
            guard let bytes = unsafe getsectiondata(header, "__TEXT", "__entitlements", &size) else { return nil }
            return unsafe Data(bytes: bytes, count: Int(size))
        }
        guard let data else { return nil }
        // The format's pointer, unused, is nil.
        return unsafe try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
    #else
    /// Whether the app carries a development profile: one that lets a debugger attach.
    private static var developmentProfile: Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let signed = try? Data(contentsOf: url),
              let start = signed.range(of: Data("<?xml".utf8)),
              let end = signed.range(of: Data("</plist>".utf8), in: start.lowerBound..<signed.endIndex),
              let profile = unsafe try? PropertyListSerialization.propertyList(from: signed[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any]
        else { return false }
        return entitlements["get-task-allow"] as? Bool ?? false
    }
    #endif
}

/// Whether iCloud is available to the app now: an account signed in, and iCloud not switched off for the app. It asks
/// CloudKit at once, and again whenever CloudKit says the account changed, as Apple's `accountStatus` page asks. Only
/// `available` counts: no account, a restricted one, one temporarily unavailable or a status CloudKit could not tell
/// all count as not available, and none of them deletes anything.
///
/// Only a build that ``CloudAccess/isEntitled`` makes one, once for the launch: it watches for as long as the app runs.
@MainActor
@Observable
final class ICloudAccount {
    /// Whether iCloud is available; nil until CloudKit has answered once.
    private(set) var isAvailable: Bool?

    @ObservationIgnored private let container: CKContainer
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// Told each time the answer changes.
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    private static let log = Logger(subsystem: "com.chentianren.PlayNineRings", category: "iCloud")

    init() {
        precondition(CloudAccess.isEntitled, "a build without the iCloud entitlement must not make a CloudKit container")
        container = CKContainer(identifier: RecordStore.cloudContainer)
        watching = Task { [weak self] in
            await self?.ask()
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await self?.ask()
            }
        }
    }

    private func ask() async {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            Self.log.error("iCloud's account status could not be read: \(error.localizedDescription, privacy: .public)")
            status = .couldNotDetermine
        }
        let available = status == .available
        Self.log.notice("iCloud's account status: \(status.rawValue, privacy: .public), so iCloud is \(available ? "available" : "not available", privacy: .public).")
        guard available != isAvailable else { return }
        isAvailable = available
        onChange?(available)
    }
}
