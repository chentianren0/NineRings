import Foundation
import Observation
import os
import Records
import Session
#if canImport(UIKit)
import UIKit
#endif

/// The app's one keeper of records: where the person's toy is kept between launches, where each finished play leaves
/// its record, and where every screen reads the plays.
///
/// It is made once for each launch, where the app starts, and given to every scene: the main window, the Mac's Settings
/// window, and any window added later. So the store behind it is opened once, however many times a window is made.
///
/// **What a screen may use: four things, and nothing else.** What is behind them can change (another store, records
/// arriving from another device, a store closed while the app runs) without a screen changing:
/// - ``history``'s `plays`: the finished plays, as values.
/// - ``history``'s `unreadable`: how many plays are kept that this build cannot read.
/// - ``clearHistory()``: deleting every finished play.
/// - ``clearingReachesOtherDevices``: whether clearing also deletes the plays on the person's other devices.
///
/// Nothing a screen gets from it is a SwiftData object, and nothing tells which store is behind it. Whatever changes the
/// records behind it reads ``history`` again from what is kept, as `record(_:)` and ``clearHistory()`` do, so that the
/// four stay true. `Player` uses the rest, `keptPlay()`, `keep(_:)` and `record(_:)`, as it always has.
///
/// The launch decides where the records are (`LaunchOptions.recordPlace`): a release build in the device's store, a
/// debug build in a store of its own, and a debug launch that sets up its own toy in memory. A store that cannot be
/// opened or written loses nothing that is playing: the app plays on, keeping nothing, and says why in the log.
@MainActor
@Observable
final class Keeper {
    /// The finished plays, as values: `plays`, newest first, one for each play (no two have the same `playID`), and
    /// `unreadable`, how many plays are kept that this build cannot read, which a newer version of the app can leave.
    /// Those are not among `plays`.
    ///
    /// It is always what is kept: it changes the moment a play is recorded, and is empty the moment the history is
    /// cleared. It can also change at any other moment, as records arrive from another device or move between stores,
    /// so a screen shows it as it is, and keeps no copy. It is empty when no store could be opened.
    private(set) var history = PlayHistory.empty

    /// Whether clearing the history also deletes the plays on the person's other devices. False while the records are
    /// kept on this device only, as now. With iCloud it is true while sync is on, so it can change while a screen is
    /// open: the history's confirmation chooses its words by it as it shows.
    private(set) var clearingReachesOtherDevices = false

    @ObservationIgnored private let store: RecordStore?
    /// This installation's id: random, made at the first launch and kept in the settings.
    @ObservationIgnored private let installation: String
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let madeOn: MadeOn
    private static let log = Logger(subsystem: "com.chentianren.PlayNineRings", category: "Keeper")

    /// The settings key of the installation's id.
    static let installationKey = "installation"

    /// Opens the device's store in `place`, and records `samplePlays` sample plays in it when it is in memory. With no
    /// store opened, it keeps nothing.
    init(place: RecordStore.Place, samplePlays: Int = 0) {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        madeOn = Self.device
        // A store in memory is this launch's alone, and so is its installation: nothing is written to the settings.
        installation = place == .memory ? UUID().uuidString : Self.installationID()
        do {
            store = RecordStore(container: try RecordStore.deviceContainer(in: place))
        } catch {
            store = nil
            Self.log.error("The device's store did not open: \(error.localizedDescription, privacy: .public)")
            return
        }
        if place == .memory, samplePlays > 0 {
            for sample in PlayRecord.samples(samplePlays, latest: .now) {
                write("A sample play could not be recorded") { try $0.record(sample, madeOn: madeOn, appVersion: appVersion) }
            }
        }
        readHistory()
        Self.log.notice(
            "The device's store opened \(Self.describe(place), privacy: .public), with \(self.history.plays.count) plays and \(self.history.unreadable) this build cannot read."
        )
    }

    // MARK: The plays, for every screen

    /// Deletes every finished play, the ones this build cannot read too, one by one: the delete that reaches the
    /// person's other devices when the records sync. The kept toy stays, and so does the play in progress, which is not
    /// finished. Afterwards ``history`` is empty, unless the store could not be written: then it still shows every play,
    /// and the log says why. It deletes what is kept at that moment: a play that arrives afterwards, from another
    /// device, shows.
    func clearHistory() {
        write("The history could not be cleared") { store in
            let deleted = try store.clearHistory()
            Self.log.notice("The history was cleared: \(deleted) records deleted.")
        }
        readHistory()
    }

    // MARK: The toy and the records, for the player

    /// The puzzle as this installation left it, or nil when it kept none this build can bring back.
    func keptPlay() -> PlayState? {
        guard let store else { return nil }
        do {
            return try store.keptToy(installation: installation).flatMap(PlayState.init)
        } catch {
            Self.log.error("The kept toy could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Keeps `snapshot` as this installation's toy; nothing is written when it is the toy kept already.
    func keep(_ snapshot: ToySnapshot) {
        write("The toy could not be kept") { try $0.keep(snapshot, installation: installation, appVersion: appVersion) }
    }

    /// Leaves the record of a finished play, which ``history`` then shows.
    func record(_ play: PlayRecord) {
        guard write("The finished play could not be recorded", { try $0.record(play, madeOn: madeOn, appVersion: appVersion) }) else { return }
        readHistory()
    }

    // MARK: The store

    /// Reads ``history`` again from the store. Setting it to what it already was notifies nobody.
    private func readHistory() {
        guard let store else { return }
        do {
            history = try store.playHistory()
        } catch {
            Self.log.error("The history could not be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes to the store with `change`, saying `failure` and why in the log when it throws. Returns whether it wrote:
    /// with no store, it does not.
    @discardableResult
    private func write(_ failure: StaticString, _ change: (RecordStore) throws -> Void) -> Bool {
        guard let store else { return false }
        do {
            try change(store)
            return true
        } catch {
            Self.log.error("\(String(describing: failure), privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func describe(_ place: RecordStore.Place) -> String {
        switch place {
        case .folder(let folder): "in the folder \(folder.lastPathComponent)"
        case .memory: "in memory"
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
