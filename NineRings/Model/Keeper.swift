import Foundation
import os
import Records
import Session
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Where the person's toy is kept between launches, and where each finished play leaves its record: the device's own
/// store, which never syncs.
///
/// A store that cannot be opened or written loses nothing that is playing: the app plays on, keeping nothing, and says
/// why in the log.
@MainActor
final class Keeper {
    private let store: RecordStore
    /// This installation's id: random, made at the first launch and kept in the settings.
    private let installation: String
    private let appVersion: String
    private let madeOn: MadeOn
    private static let log = Logger(subsystem: "com.chentianren.PlayNineRings", category: "Keeper")

    /// The settings key of the installation's id.
    static let installationKey = "installation"

    /// Opens the device's store, or nil when it cannot be opened.
    init?() {
        do {
            store = RecordStore(container: try RecordStore.deviceContainer())
        } catch {
            Self.log.error("The device's store did not open: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        installation = Self.installationID()
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        madeOn = Self.device
    }

    /// The puzzle as this installation left it, or nil when it kept none this build can bring back.
    func keptPlay() -> PlayState? {
        do {
            return try store.keptToy(installation: installation).flatMap(PlayState.init)
        } catch {
            Self.log.error("The kept toy could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Keeps `snapshot` as this installation's toy; nothing is written when it is the toy kept already.
    func keep(_ snapshot: ToySnapshot) {
        do {
            try store.keep(snapshot, installation: installation, appVersion: appVersion)
        } catch {
            Self.log.error("The toy could not be kept: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Leaves the record of a finished play.
    func record(_ play: PlayRecord) {
        do {
            try store.record(play, madeOn: madeOn, appVersion: appVersion)
        } catch {
            Self.log.error("The finished play could not be recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func installationID() -> String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: installationKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installationKey)
        return id
    }

    private static var device: MadeOn {
        #if os(macOS)
        .Mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }
}
