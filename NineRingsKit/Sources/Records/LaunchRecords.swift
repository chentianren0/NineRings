import Foundation
import Session

/// The toy and the finished plays as one launch keeps them: in memory, and also in a folder while one is open.
///
/// It knows nothing of where the folder comes from: the app opens it through GameSave, a test makes a temporary one. A
/// launch that never opens a folder keeps everything in memory, for that launch only. The rules it keeps:
/// - What is kept and recorded is in memory at once: ``keptToy`` and ``history`` change whether or not a folder takes
///   it.
/// - While a folder is open, each change is written to it as well (``RecordFolder``): a toy kept, a play recorded, the
///   history cleared.
/// - From ``closeFolder()`` until the next ``open(_:)``, as while the folder is opened again, nothing is written to any
///   folder. The toy kept meanwhile stays in memory, and the plays recorded and a clearing wait for the next folder.
/// - Opening a folder reads it, and the folder wins: the history is the folder's, after the clearing and the plays
///   that waited are written there. The toy read is for the player to take when this launch has not read or kept it
///   there already, whatever the time spent on it: at the first opening, and after another device kept a toy since.
///   Otherwise the toy in play stays, since it is the newer one, as when the folder keeps no toy; the next keep writes
///   it there.
/// - A write that fails leaves the folder as it was. A toy is written again at the next keep; a play or a clearing
///   waits for the next opening, as when no folder is open. When the history file is there but cannot be read as a
///   history, the history is the plays that wait.
public struct LaunchRecords: Sendable {
    /// The finished plays: the folder's while one is open, newest first, one for each play.
    public private(set) var history = PlayHistory.empty
    /// The toy as it was last kept, or as it was read for the player to take; nil before either.
    public private(set) var keptToy: ToySnapshot?

    /// The folder written to, while one is open.
    private var folder: RecordFolder?
    /// The toy this launch last read from a folder or kept in one; nil before the first, or when the folder read had
    /// none.
    private var toyInFolder: ToySnapshot?
    /// The plays recorded that are not in a folder yet, in the order they were recorded.
    private var waitingPlays: [PlayRecord] = []
    /// Whether the history was cleared and the folder not yet.
    private var clearingWaits = false

    public init() {}

    /// What opening a folder found.
    public struct Opening {
        /// The toy read, for the player to take; nil when the toy in play stays.
        public var toy: ToySnapshot?
        /// Whether anything was written to the folder: the clearing or the plays that waited.
        public var wrote = false
        /// What could not be read or written.
        public var errors: [any Error] = []
    }

    /// Keeps `snapshot` as the toy, and in the folder when one is open. Returns whether the folder's file was written:
    /// it is not when no folder is open, or the file holds this toy already. Throws when it could not be written; the
    /// next keep tries again.
    @discardableResult
    public mutating func keep(_ snapshot: ToySnapshot) throws -> Bool {
        keptToy = snapshot
        guard let folder else { return false }
        let wrote = try folder.keep(snapshot)
        toyInFolder = snapshot
        return wrote
    }

    /// Records `play` in the history (``PlayHistory/record(_:)``), and in the folder when one is open. Returns whether
    /// the folder's file was written. A play already recorded is not recorded again. Throws when it could not be
    /// written there, as when the history file cannot be read as a history; the play waits for the next opening.
    @discardableResult
    public mutating func record(_ play: PlayRecord) throws -> Bool {
        guard history.record(play) else { return false }
        guard let folder else {
            waitingPlays.append(play)
            return false
        }
        do {
            return try folder.record(play)
        } catch {
            waitingPlays.append(play)
            throw error
        }
    }

    /// Deletes every finished play, the ones this build cannot read too, and in the folder when one is open. Returns
    /// whether the folder's file was written. Throws when it could not be; the clearing waits for the next opening.
    @discardableResult
    public mutating func clearHistory() throws -> Bool {
        history = .empty
        waitingPlays = []
        guard let folder else {
            clearingWaits = true
            return false
        }
        do {
            try folder.clearHistory()
            clearingWaits = false
            return true
        } catch {
            clearingWaits = true
            throw error
        }
    }

    /// No folder is open from now on: nothing is written to one until the next ``open(_:)``.
    public mutating func closeFolder() {
        folder = nil
    }

    /// Opens `folder`: writes the clearing and the plays that waited, then reads the history and the toy there.
    public mutating func open(_ folder: RecordFolder) -> Opening {
        self.folder = folder
        var opening = Opening()
        if clearingWaits {
            do {
                try folder.clearHistory()
                clearingWaits = false
                opening.wrote = true
            } catch {
                opening.errors.append(error)
            }
        }
        var stillWaiting: [PlayRecord] = []
        for play in waitingPlays {
            do {
                if try folder.record(play) { opening.wrote = true }
            } catch {
                opening.errors.append(error)
                stillWaiting.append(play)
            }
        }
        waitingPlays = stillWaiting
        do {
            history = try folder.history()
        } catch {
            opening.errors.append(error)
            history = .empty
            for play in waitingPlays { history.record(play) }
        }
        let read = folder.keptToy()
        if let read, !(toyInFolder.map { read.isSameToy(as: $0) } ?? false) {
            opening.toy = read
            keptToy = read
        }
        toyInFolder = read
        return opening
    }
}
