import Foundation
import Observation
import os
import Records
import Session
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// The app's one keeper of records: where the person's toy is kept between launches, where each finished play leaves
/// its record, and where every screen reads the plays.
///
/// It is made once for each launch, where the app starts, and given to every scene: the main window, the Mac's Settings
/// window, and any window added later. So the stores behind it are opened once, however many times a window is made.
///
/// **What a screen may use: four things, and nothing else.** What is behind them can change (another store, records
/// arriving from another device, a store closed while the app runs) without a screen changing:
/// - ``history``'s `plays`: the finished plays, as values.
/// - ``history``'s `unreadable`: how many plays are kept that this build cannot read.
/// - ``clearHistory()``: deleting every finished play.
/// - ``clearingReachesOtherDevices``: whether clearing also deletes the plays on the person's other devices.
///
/// iCloud adds three, for its own two lines, and none of them tells which store is behind the keeper:
/// ``iCloudIsUnavailable`` and ``syncSwitchChanged()`` for the switch in Settings, and ``isOfferingOtherPlay`` for the
/// line that offers the other play, whose two choices go through `Player`.
///
/// Nothing a screen gets from it is a SwiftData object, and nothing tells which store is behind it. Whatever changes the
/// records behind it reads ``history`` again from what is kept, as `record(_:)`, ``clearHistory()``, sync going on and
/// off and records arriving from iCloud do, so that the four stay true. `Player` uses the rest.
///
/// The launch decides where the records are (`LaunchOptions.recordPlace`): a release build in the device's store, a
/// debug build in a store of its own, and a debug launch that sets up its own toy in memory. A store that cannot be
/// opened or written loses nothing that is playing: the app plays on, keeping nothing, and says why in the log.
///
/// **iCloud.** Two stores, each with a container of its own (see `SyncRule`):
/// - The device's store never syncs. It always holds this installation's toy, kept at every rest, and with sync off the
///   finished plays.
/// - The iCloud store syncs, and is open exactly while sync is on: the switch is on and iCloud is available. It holds
///   the finished plays then, and each installation's toy, which this one writes at calm moments: when the app leaves
///   the front, when a play is finished, and at most once a minute otherwise.
/// - It looks at the other installations' toys at launch, when the app comes to the front, and whenever records arrive
///   from iCloud: a toy made knowing this one waits for `Player` to take it up at a calm moment; a play parted in two is
///   offered.
/// - Before the iCloud store is let go, everything read from it is let go: only values leave it.
/// - In memory, the iCloud store is a stand-in that never syncs, and iCloud counts as available.
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

    /// Whether clearing the history also deletes the plays on the person's other devices: true while sync is on, so it
    /// can change while a screen is open: the history's confirmation chooses its words by it as it shows.
    private(set) var clearingReachesOtherDevices = false

    /// Whether the switch is on while iCloud is not available, as Settings says quietly under the switch. False until
    /// CloudKit has answered.
    private(set) var iCloudIsUnavailable = false

    /// Whether the line that offers another device's play shows: the play has parted in two.
    private(set) var isOfferingOtherPlay = false

    /// Told when a toy made knowing this one has arrived, for `Player` to take it up at a calm moment.
    @ObservationIgnored var laterToyArrived: (() -> Void)?
    /// Whether such a toy waits.
    @ObservationIgnored private(set) var hasLaterToy = false

    /// The device's store; nil when it did not open.
    @ObservationIgnored private let device: RecordStore?
    /// The iCloud store, open while sync is on.
    @ObservationIgnored private var cloud: RecordStore?
    @ObservationIgnored private var arrivals: HistoryObserver?
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private let place: RecordStore.Place
    /// This installation's id (``InstallationID``).
    @ObservationIgnored private let installation: String
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let madeOn: MadeOn
    @ObservationIgnored private var account: ICloudAccount?
    /// Whether iCloud is available; nil until CloudKit has answered.
    @ObservationIgnored private var isAvailable: Bool?
    /// A copy to the device's store that is due, in memory, for a launch in memory.
    @ObservationIgnored private var copyIsDueInMemory = false
    /// When the toy was last written to the iCloud store, and the write waiting for the minute to pass.
    @ObservationIgnored private var lastSent: ContinuousClock.Instant?
    @ObservationIgnored private var sending: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.chentianren.PlayNineRings", category: "Keeper")
    /// The least time between two writes of the toy to the iCloud store, but at calm moments.
    private static let sendingInterval = Duration.seconds(60)

    /// Opens the device's store in `place`, and records `samplePlays` sample plays in it when it is in memory, then
    /// starts sync. With no store opened, it keeps nothing.
    init(place: RecordStore.Place, samplePlays: Int = 0) {
        self.place = place
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        madeOn = Self.device
        let device: RecordStore
        do {
            device = RecordStore(container: try RecordStore.deviceContainer(in: place))
        } catch {
            self.device = nil
            installation = UUID().uuidString
            Self.log.error("The device's store did not open: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.device = device
        installation = Self.installationID(in: place, device: device)
        if (try? device.installationKept()) == nil {
            // The store keeps the copy of the id from the start.
            write("The first toy could not be kept", to: device) { try $0.keep(PlayState().snapshot, installation: installation, appVersion: appVersion) }
        }
        if place == .memory, samplePlays > 0 {
            for sample in PlayRecord.samples(samplePlays, latest: .now) {
                write("A sample play could not be recorded", to: device) { try $0.record(sample, madeOn: madeOn, appVersion: appVersion) }
            }
        }
        readHistory()
        Self.log.notice(
            "The device's store opened \(Self.describe(place), privacy: .public), with \(self.history.plays.count) plays and \(self.history.unreadable) this build cannot read."
        )
        startSync()
    }

    // MARK: The plays, for every screen

    /// Deletes every finished play, the ones this build cannot read too, one by one: the delete that reaches the
    /// person's other devices when the records sync. The kept toy stays, and so does the play in progress, which is not
    /// finished. Afterwards ``history`` is empty, unless the store could not be written: then it still shows every play,
    /// and the log says why. It deletes what is kept at that moment: a play that arrives afterwards, from another
    /// device, shows.
    func clearHistory() {
        write("The history could not be cleared", to: records) { store in
            let deleted = try store.clearHistory()
            Self.log.notice("The history was cleared: \(deleted) records deleted.")
        }
        readHistory()
    }

    // MARK: The switch, for Settings

    /// The switch in Settings has changed: sync goes on or off as it now says.
    func syncSwitchChanged() {
        applySync()
    }

    // MARK: The toy and the records, for the player

    /// The puzzle as this installation left it, or nil when it kept none this build can bring back.
    func keptPlay() -> PlayState? {
        guard let device else { return nil }
        do {
            return try device.keptToy(installation: installation).flatMap(PlayState.init)
        } catch {
            Self.log.error("The kept toy could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Keeps `snapshot` as this installation's toy in the device's store; nothing is written when it is the toy kept
    /// already. It reaches the iCloud store within a minute.
    func keep(_ snapshot: ToySnapshot) {
        guard write("The toy could not be kept", to: device, { try $0.keep(snapshot, installation: installation, appVersion: appVersion) }) else { return }
        sendToySoon()
    }

    /// Leaves the record of a finished play, which ``history`` then shows, and sends the toy at once.
    func record(_ play: PlayRecord) {
        guard write("The finished play could not be recorded", to: records, { try $0.record(play, madeOn: madeOn, appVersion: appVersion) }) else { return }
        readHistory()
        sendToy()
    }

    /// The app has come to the front: a time to look at the other installations' toys, and to ask again whether iCloud
    /// is available.
    func cameToFront() {
        lookAtOtherToys()
        if let account { Task { await account.ask() } }
    }

    /// The app has left the front: the toy is sent at once.
    func leftFront() {
        sendToy()
    }

    /// The toy made knowing this one, taken up as this installation's, for `Player` to take up at a calm moment; nil when
    /// none waits.
    func takeLaterToy() -> ToySnapshot? {
        guard let device, let decision = decide(), let later = decision.takeUp else {
            hasLaterToy = false
            return nil
        }
        guard write("The later toy could not be taken up", to: device, {
            try $0.takeUp(later, lineage: decision.lineage, installation: installation, appVersion: appVersion)
        }) else { return nil }
        Self.log.notice("This installation took up a later toy, left by another installation.")
        // A take-up follows every later toy at once, so the look that follows tells nobody: the player is taking it up.
        lookAtOtherToys(tellingPlayer: false)
        return later.snapshot
    }

    /// The other device's play, offered, taken up in place of this one, for `Player` to show; nil when none is offered.
    func playThatOne() -> ToySnapshot? {
        guard let device, let offered = decide()?.offer else { return nil }
        guard write("The other play could not be taken up", to: device, { store in
            try store.takeUp(offered, lineage: try store.lineage(installation: installation).takingUp(offered.lineage),
                             installation: installation, appVersion: appVersion)
        }) else { return nil }
        Self.log.notice("The person took up the other device's play.")
        sendToy()
        lookAtOtherToys(tellingPlayer: false)
        return offered.snapshot
    }

    /// This device's play kept over the one offered: the other device then follows.
    func keepThisOne() {
        guard let device, let offered = decide()?.offer else { return }
        guard write("This play could not be kept over the other", to: device, { try $0.keepOwnToy(over: offered, installation: installation) }) else { return }
        Self.log.notice("The person kept this device's play over the other device's.")
        sendToy()
        lookAtOtherToys()
    }

    // MARK: Sync

    /// The store the finished plays are in: the iCloud store while sync is on, the device's otherwise.
    private var records: RecordStore? {
        cloud ?? device
    }

    /// The switch, on until it is turned off. Read as `bool(forKey:)` reads it, so that a setting given as text, as
    /// `-syncsWithICloud NO` gives it, counts as the switch does.
    private var switchIsOn: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: ICloudSetting.key) == nil || defaults.bool(forKey: ICloudSetting.key)
    }

    /// Whether a copy to the device's store is due, kept for each place, so that a debug build's never touches the App
    /// Store version's; in memory, for the launch alone.
    private var copyIsDue: Bool {
        get {
            guard case .folder(let folder) = place else { return copyIsDueInMemory }
            return UserDefaults.standard.bool(forKey: Self.copyKey(folder))
        }
        set {
            guard case .folder(let folder) = place else { return copyIsDueInMemory = newValue }
            UserDefaults.standard.set(newValue, forKey: Self.copyKey(folder))
        }
    }

    private static func copyKey(_ folder: URL) -> String {
        "iCloudCopyIsDue \(folder.lastPathComponent)"
    }

    /// Learns whether iCloud is available, and follows it.
    private func startSync() {
        #if DEBUG
        if ICloudLaunchOptions.countsICloudUnavailable {
            Self.log.notice("iCloud counts as not available in this launch.")
            isAvailable = false
            return applySync()
        }
        #endif
        if place == .memory {
            // A stand-in, never syncing, plays iCloud's part.
            isAvailable = true
            return applySync()
        }
        guard CloudAccess.isEntitled else {
            Self.log.notice("This build has no iCloud entitlement: its records stay on this device.")
            isAvailable = false
            return applySync()
        }
        let account = ICloudAccount()
        account.onChange = { [weak self] available in
            self?.isAvailable = available
            self?.applySync()
        }
        self.account = account
        // Until CloudKit answers, the records are where sync off keeps them.
        applySync()
    }

    /// Does what ``SyncRule`` says for the switch, iCloud and the stores as they are, then reads the history again.
    private func applySync() {
        guard let device else { return }
        let available = isAvailable ?? false
        steps: for step in SyncRule.steps(switchIsOn: switchIsOn, isAvailable: available, isOpen: cloud != nil, copyIsDue: copyIsDue) {
            switch step {
            case .openICloudStore:
                // Without the store, nothing that needs it is done.
                if !openICloudStore() { break steps }
            case .moveToICloud:
                guard let cloud else { break }
                write("The finished plays could not be moved to iCloud", to: device) { device in
                    let moved = try device.moveFinishedPlays(to: cloud)
                    Self.log.notice("Sync is on: \(moved) finished plays moved from the device's store to iCloud.")
                }
            case .copyToDevice:
                guard let cloud else { break }
                copyIsDue = true
                let copied = write("The finished plays could not be copied from iCloud", to: cloud) { cloud in
                    let copied = try cloud.copyFinishedPlays(to: device)
                    Self.log.notice("The switch went off: \(copied) finished plays copied from iCloud to the device's store.")
                }
                // A copy cut short stays due, and is finished at a later launch.
                if copied { copyIsDue = false }
            case .letGoOfICloudStore:
                letGoOfICloudStore()
            case .forgetCopy:
                copyIsDue = false
            }
        }
        clearingReachesOtherDevices = cloud != nil
        iCloudIsUnavailable = switchIsOn && isAvailable == false
        readHistory()
        if cloud != nil {
            sendToy()
            lookAtOtherToys()
        }
    }

    /// Opens the iCloud store, and starts following the records that arrive in it. Returns whether it opened.
    private func openICloudStore() -> Bool {
        let environment = CloudAccess.environment
        do {
            let container = try RecordStore.cloudContainer(in: place, environment: environment)
            cloud = RecordStore(container: container)
            Self.log.notice("The iCloud store opened \(Self.describe(self.place), privacy: .public), for CloudKit's \(environment.rawValue, privacy: .public) environment.")
        } catch {
            Self.log.error("The iCloud store did not open: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #if DEBUG
        stagePlay()
        #endif
        followArrivals()
        return true
    }

    /// Follows the changes that reach the iCloud store from iCloud, as Apple's `HistoryObserver` reports them: the
    /// history is read again, and the other installations' toys looked at.
    private func followArrivals() {
        guard let cloud else { return }
        do {
            let arrivals = try HistoryObserver(observedModels: [FinishedPlay.self, SavedToy.self], modelContainer: cloud.container)
            self.arrivals = arrivals
            watching = Task { [weak self] in
                for await _ in Observations({ arrivals.eventCounter }).dropFirst() {
                    self?.recordsArrived()
                }
            }
        } catch {
            Self.log.error("The records arriving in the iCloud store cannot be followed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordsArrived() {
        guard cloud != nil else { return }
        readHistory()
        lookAtOtherToys()
    }

    /// Lets go of the iCloud store: what follows it first, then the store. Nothing read from it is kept but values.
    private func letGoOfICloudStore() {
        watching?.cancel()
        watching = nil
        arrivals = nil
        sending?.cancel()
        sending = nil
        hasLaterToy = false
        isOfferingOtherPlay = false
        cloud = nil
        Self.log.notice("The iCloud store was let go: nothing more is sent.")
    }

    // MARK: The toy between devices

    /// Writes this installation's toy to the iCloud store at once, if anything in it changed.
    private func sendToy() {
        sending?.cancel()
        sending = nil
        guard let cloud, let device else { return }
        write("The toy could not be written to iCloud", to: cloud) { cloud in
            if try cloud.copyToy(of: installation, from: device) {
                lastSent = .now
                Self.log.notice("This installation's toy was written to iCloud.")
            }
        }
    }

    /// Writes the toy to the iCloud store now, or when a minute has passed since the last write.
    private func sendToySoon() {
        guard cloud != nil, sending == nil else { return }
        guard let lastSent, lastSent.duration(to: .now) < Self.sendingInterval else { return sendToy() }
        let due = lastSent.advanced(by: Self.sendingInterval)
        sending = Task { [weak self] in
            try? await Task.sleep(until: due, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.sending = nil
            self?.sendToy()
        }
    }

    /// What to do about the other installations' toys now; nil without the iCloud store.
    private func decide() -> ToyDecision? {
        guard let cloud, let device else { return nil }
        do {
            return ToyDecision(mine: try device.lineage(installation: installation), others: try cloud.otherToys(than: installation))
        } catch {
            Self.log.error("The other installations' toys could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Looks at the other installations' toys: offers a play parted in two, and tells `Player` of a later toy unless it
    /// is the player that asked.
    private func lookAtOtherToys(tellingPlayer: Bool = true) {
        let decision = decide()
        let offers = decision?.offer != nil
        if offers != isOfferingOtherPlay {
            Self.log.notice("\(offers ? "The play has parted in two: the other play is offered." : "No other play is offered.", privacy: .public)")
        }
        isOfferingOtherPlay = offers
        hasLaterToy = decision?.takeUp != nil
        if hasLaterToy, tellingPlayer { laterToyArrived?() }
    }

    // MARK: The store

    /// Reads ``history`` again from the store the plays are in. Setting it to what it already was notifies nobody.
    private func readHistory() {
        guard let records else { return }
        do {
            history = try records.playHistory()
        } catch {
            Self.log.error("The history could not be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes to `store` with `change`, saying `failure` and why in the log when it throws. Returns whether it wrote:
    /// with no store, it does not.
    @discardableResult
    private func write(_ failure: StaticString, to store: RecordStore?, _ change: (RecordStore) throws -> Void) -> Bool {
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

    /// This installation's id: in memory, the launch's own; otherwise as ``InstallationID`` decides it from the keychain,
    /// the copy left out of backups and the device's store, giving the store's toy to a new id when the store came from
    /// another device or back from a backup.
    private static func installationID(in place: RecordStore.Place, device: RecordStore) -> String {
        guard case .folder(let folder) = place else { return UUID().uuidString }
        let keychain = InstallationKeychain(folder: folder)
        let apart = InstallationID.CopyLeftOutOfBackups(folder: folder)
        let kept = try? device.installationKept()
        let resolution = InstallationID.resolve(keychain: keychain.read(), leftOutOfBackups: apart.read(), store: kept) {
            UUID().uuidString
        }
        if resolution.writesKeychain, !keychain.write(resolution.id) {
            log.error("The installation's id could not be written to the keychain.")
        }
        if resolution.writesCopyLeftOutOfBackups, !apart.write(resolution.id) {
            log.error("The installation's id could not be written to its copy left out of backups.")
        }
        if let old = resolution.givesToyFrom {
            do {
                try device.giveToy(of: old, to: resolution.id)
                log.notice("The device's store came from another installation or back from a backup: its toy now goes on under a new id.")
            } catch {
                log.error("The toy could not be given the new id: \(error.localizedDescription, privacy: .public)")
            }
        } else if resolution.id != kept {
            log.notice("This installation has a new id.")
        }
        return resolution.id
    }

    private static var device: MadeOn {
        #if os(macOS)
        .Mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    #if DEBUG
    /// In a launch in memory, puts another installation's toy in the stand-in for iCloud (`-stage-other-play`): this
    /// installation's toy is made a change of its own, ring 1 off, and the other's is ring 2 off, made knowing it or not.
    private func stagePlay() {
        guard place == .memory, let staged = ICloudLaunchOptions.stagedPlay, let cloud, let device else { return }
        write("Another installation's toy could not be staged", to: device) { device in
            var mine = PlayState()
            mine.tap(1)
            while mine.toy.isPlaying { mine.advance(by: 10) }
            try device.keep(mine.snapshot, installation: installation, appVersion: appVersion)
            var theirs = PlayState()
            theirs.tap(2)
            while theirs.toy.isPlaying { theirs.advance(by: 10) }
            let other = SavedToy(installation: "staged")
            other.changedAt = .now
            other.snapshot = try theirs.snapshot.encoded()
            let mineKnown = try device.lineage(installation: installation)
            let lineage = staged == .later ? mineKnown.changed(by: "staged") : Lineage().changed(by: "staged")
            other.lineage = try lineage.encoded()
            cloud.container.mainContext.insert(other)
            try cloud.container.mainContext.save()
            Self.log.notice("Another installation's toy is staged: \(staged.rawValue, privacy: .public).")
        }
    }
    #endif
}
