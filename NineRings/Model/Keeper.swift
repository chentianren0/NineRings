import Foundation
import GameSave
import Observation
import Records
import Session
import os

/// The app's one keeper of records: where the person's toy is kept, where each finished play leaves its record, and
/// where every screen reads the plays.
///
/// It is made once for each launch, where the app starts, and given to every scene: the main window, the Mac's Settings
/// window, and any window added later. So every window reads the same records, however many times a window is made.
///
/// **What a screen may use: four things, and nothing else.** What is behind them can change without a screen changing:
/// - ``history``'s `plays`: the finished plays, as values.
/// - ``history``'s `unreadable`: how many plays are kept that this build cannot read.
/// - ``clearHistory()``: deleting every finished play.
/// - ``clearingReachesOtherDevices``: whether clearing also deletes the plays on the person's other devices.
///
/// Whatever changes the records sets ``history`` to what is kept, as `record(_:)` and ``clearHistory()`` do, so that
/// the four stay true. `Player` uses `keptPlay()`, `keep(_:)` and `record(_:)`, as it always has. The main window uses
/// the rest, for GameSave's folder.
///
/// **Where the records are kept.** A launch in memory keeps them for that launch only, and never opens GameSave: the
/// launches that set up their own toy or plays (`LaunchOptions.keepsRecordsInMemory`) and the measuring build. Every
/// other launch keeps them in GameSave's folder, as `Toy.json` and `History.json` (`RecordFolder`). GameSave syncs the
/// folder through the person's iCloud Drive, and keeps it on the device when iCloud Drive is off. The rules for what is
/// read and written, and when, are `LaunchRecords`'s; here is only GameSave:
/// - The folder is opened as the app first comes to the front, and closed and opened again each time it comes back
///   (``cameToFront()``, ``leftFront()``), since GameSave syncs while it is closed. A folder still loading is left to
///   finish.
/// - While it loads, Apple's alert can show: the main window binds ``loading`` to `gameSaveSyncingAlert`, which also
///   lets the person choose when two devices have different saves. Nothing is written to the folder meanwhile.
/// - When loading has finished (``finishLoading()``) with a folder, ready, offline or kept on the device, its two files
///   are read; with none, as on an error, the records stay in memory, and the next return to the front tries again. A
///   folder that finishes loading with no word from the alert is read at the next return to the front.
/// - After each write to the folder it asks GameSave to send.
@MainActor
@Observable
final class Keeper {
    /// The finished plays, as values: `plays`, newest first, one for each play (no two have the same `playID`), and
    /// `unreadable`, how many plays are kept that this build cannot read. Those are not among `plays`.
    ///
    /// It is always what is kept: it changes the moment a play is recorded, is empty the moment the history is
    /// cleared, and is the folder's once the folder is read, so a screen shows it as it is, and keeps no copy.
    private(set) var history = PlayHistory.empty

    /// Whether clearing the history also deletes the plays on the person's other devices: whether the folder a clearing
    /// reaches, now or at the next opening, syncs through iCloud Drive (see `LaunchRecords`). False in memory. The
    /// history's confirmation chooses its words by it as it shows.
    private(set) var clearingReachesOtherDevices: Bool

    /// GameSave's folder while it loads, for Apple's alert, which shows while this is set; nil otherwise, and always in
    /// a launch in memory.
    var loading: GameSaveSyncedDirectory?

    /// The toy and the plays, in memory and in the folder while one is open, by `LaunchRecords`'s rules.
    @ObservationIgnored private var records: LaunchRecords
    /// Whether this launch keeps its records in GameSave's folder.
    @ObservationIgnored private let opensGameSave: Bool
    /// GameSave's folder as last opened: loading, open, or unusable; nil before the first opening.
    @ObservationIgnored private var directory: GameSaveSyncedDirectory?
    /// Whether the app coming to the front opens the folder: before the first time, and after it has left the front.
    @ObservationIgnored private var opensAtFront = true

    /// The iCloud container GameSave keeps the folder in.
    private static let container = "iCloud.com.chentianren.PlayNineRings"
    private static let log = Logger(subsystem: "NineRings", category: "Records")

    /// Starts with no toy kept and no plays. A launch `inMemory` never opens GameSave, and starts with `samplePlays`
    /// sample plays recorded.
    init(inMemory: Bool, samplePlays: Int = 0) {
        opensGameSave = !inMemory
        records = LaunchRecords(opensFolders: !inMemory)
        clearingReachesOtherDevices = records.clearingReachesOtherDevices
        guard inMemory else { return }
        for sample in PlayRecord.samples(samplePlays, latest: .now) {
            record(sample)
        }
    }

    // MARK: The plays, for every screen

    /// Deletes every finished play, the ones this build cannot read too. The kept toy stays, and so does the play in
    /// progress, which is not finished. Afterwards ``history`` is empty.
    func clearHistory() {
        do {
            if try records.clearHistory() { send() }
        } catch {
            Self.log.error("The history could not be cleared in the folder: \(error, privacy: .public)")
        }
        history = records.history
    }

    // MARK: The toy and the records, for the player

    /// The puzzle as it was last kept, or nil when none was kept that this build can bring back.
    func keptPlay() -> PlayState? {
        records.keptToy.flatMap(PlayState.init)
    }

    /// Keeps `snapshot` as the toy.
    func keep(_ snapshot: ToySnapshot) {
        do {
            if try records.keep(snapshot) { send() }
        } catch {
            Self.log.error("The toy could not be kept in the folder: \(error, privacy: .public)")
        }
    }

    /// Leaves the record of a finished play, which ``history`` then shows, in its place among the newest first. A play
    /// whose id is recorded already is not recorded again.
    func record(_ play: PlayRecord) {
        do {
            if try records.record(play) { send() }
        } catch {
            Self.log.error("A finished play could not be recorded in the folder: \(error, privacy: .public)")
        }
        history = records.history
    }

    // MARK: GameSave's folder, for the main window

    /// The app has come to the front: the first time, the folder is opened; after the app has left the front, it is
    /// closed and opened again. Nothing is written to it until it has loaded. A folder still loading is left to finish,
    /// as Apple's alert follows only the folder it began with, and what it loads is new already. A folder that has
    /// finished loading with no word from the alert is read now, as `finishLoading()` reads it, and this returns the
    /// toy read when the player is to take it.
    func cameToFront() -> ToySnapshot? {
        guard opensGameSave, opensAtFront else { return nil }
        opensAtFront = false
        if let loading {
            switch loading.state {
            case .syncing, .conflicted:
                return nil
            default:
                Self.log.info("The folder had loaded with no word from Apple's alert; it is read now")
                return finishLoading()
            }
        }
        directory?.close()
        records.closeFolder()
        let directory = GameSaveSyncedDirectory.openDirectory(containerIdentifier: Self.container)
        Self.log.info("Opening the folder \(directory.id, privacy: .public): \(directory.state.description, privacy: .public)")
        self.directory = directory
        loading = directory
        return nil
    }

    /// The app has left the front: on the Mac, it is no longer the active app; on iPhone and iPad, it is in the
    /// background. Coming back opens the folder again.
    func leftFront() {
        opensAtFront = true
    }

    /// The Mac's main window has closed, and the app runs on: as leaving the front. A folder still loading is closed
    /// and dropped, as its alert has gone with the window, so that a late word from that alert reads nothing, and the
    /// window the Dock opens next opens it again under its own.
    func windowClosed() {
        opensAtFront = true
        guard loading != nil else { return }
        directory?.close()
        directory = nil
        loading = nil
        Self.log.info("The window closed while the folder loaded; the next window opens it again")
    }

    /// Apple's alert has finished loading the folder: with a folder, its two files are read, and this returns the toy
    /// read when the player is to take it (see `LaunchRecords`). Without one, the records stay in memory, until the
    /// next return to the front opens it again.
    func finishLoading() -> ToySnapshot? {
        guard let directory else { return nil }
        let state = directory.state
        Self.log.info(
            "The folder \(directory.id, privacy: .public) has loaded: \(state.description, privacy: .public); the alert's folder is \(self.loading == nil ? "nil" : "set", privacy: .public)"
        )
        switch state {
        case .ready(let url), .offline(let url):
            return open(url, syncs: true)
        case .local(let url):
            return open(url, syncs: false)
        case .syncing, .conflicted, .error, .closed:
            return stayInMemory(state)
        @unknown default:
            return stayInMemory(state)
        }
    }

    /// Loading ended without a folder: the records stay in memory, and the next return to the front tries again.
    private func stayInMemory(_ state: GameSaveSyncedDirectory.State) -> ToySnapshot? {
        loading = nil
        Self.log.error("The folder cannot be used; the records stay in memory: \(state.description, privacy: .public)")
        return nil
    }

    private func open(_ url: URL, syncs: Bool) -> ToySnapshot? {
        loading = nil
        let opening = records.open(RecordFolder(url: url), syncs: syncs)
        clearingReachesOtherDevices = records.clearingReachesOtherDevices
        for error in opening.errors {
            Self.log.error("The folder could not be read or written in full: \(error, privacy: .public)")
        }
        if opening.wrote { send() }
        history = records.history
        return opening.toy
    }

    /// Asks GameSave to send what was written to the folder.
    private func send() {
        guard let directory else { return }
        Task {
            let pending = await directory.triggerPendingUpload()
            Self.log.info("Asked GameSave to send: \(pending ? "uploads were pending" : "nothing was pending", privacy: .public)")
        }
    }
}
