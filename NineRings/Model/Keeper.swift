import Foundation
import Observation
import Records
import Session

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
/// Whatever changes the records sets ``history`` to what is kept, as `record(_:)` and ``clearHistory()`` do, so that the
/// four stay true. `Player` uses the rest, `keptPlay()`, `keep(_:)` and `record(_:)`, as it always has.
///
/// It keeps the toy and the plays in memory, for this launch only: each launch starts with no toy kept and no plays.
@MainActor
@Observable
final class Keeper {
    /// The finished plays, as values: `plays`, newest first, one for each play (no two have the same `playID`), and
    /// `unreadable`, how many plays are kept that this build cannot read. Those are not among `plays`.
    ///
    /// It is always what is kept: it changes the moment a play is recorded, and is empty the moment the history is
    /// cleared, so a screen shows it as it is, and keeps no copy.
    private(set) var history = PlayHistory.empty

    /// Whether clearing the history also deletes the plays on the person's other devices. False, as the records are
    /// kept on this device only. The history's confirmation chooses its words by it as it shows.
    private(set) var clearingReachesOtherDevices = false

    /// The toy as it was last kept.
    @ObservationIgnored private var keptToy: ToySnapshot?

    /// Starts with no toy kept, and with `samplePlays` sample plays recorded.
    init(samplePlays: Int = 0) {
        for sample in PlayRecord.samples(samplePlays, latest: .now) {
            record(sample)
        }
    }

    // MARK: The plays, for every screen

    /// Deletes every finished play, the ones this build cannot read too. The kept toy stays, and so does the play in
    /// progress, which is not finished. Afterwards ``history`` is empty.
    func clearHistory() {
        history = .empty
    }

    // MARK: The toy and the records, for the player

    /// The puzzle as it was last kept, or nil when none was kept that this build can bring back.
    func keptPlay() -> PlayState? {
        keptToy.flatMap(PlayState.init)
    }

    /// Keeps `snapshot` as the toy.
    func keep(_ snapshot: ToySnapshot) {
        keptToy = snapshot
    }

    /// Leaves the record of a finished play, which ``history`` then shows, in its place among the newest first. A play
    /// whose id is recorded already is not recorded again.
    func record(_ play: PlayRecord) {
        guard !history.plays.contains(where: { $0.playID == play.playID }) else { return }
        let index = history.plays.firstIndex { $0.finishedAt < play.finishedAt } ?? history.plays.endIndex
        history.plays.insert(play, at: index)
    }
}
