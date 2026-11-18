import Foundation
import Motion
import Puzzle
import Records

/// Options read from the launch arguments.
enum LaunchOptions {
    /// `-move 2` opens the app where ring 2 first comes off on the way from every ring on to every ring off, with that
    /// move on the slider.
    static var move: Move? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-move"), index + 1 < arguments.count, let ring = Int(arguments[index + 1]) else { return nil }
        return Player.moves.first { $0.ring == ring }
    }

    /// `-start-progress 0.5` opens the app that far through that move, for checking a pose by hand.
    static var startProgress: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-start-progress"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }

    /// Where this launch keeps its records: the kept toy and the finished plays.
    /// - A release build keeps them in the device's store, in the app's folder.
    /// - A debug build keeps them in a store in a folder of its own, never the release build's file: signed for this
    ///   device, it shares the App Store version's container.
    /// - A debug launch that sets up its own toy (`-keeps-toy NO`, `-move`, `-set-rings`, `-play-last-move`, the store's
    ///   pictures, the frame capture) or asks for sample plays (`-sample-plays`) keeps them in memory. Plays are recorded
    ///   and can be read during the launch, and nothing reaches a file, so that such a launch starts where it says and
    ///   leaves what is kept as it was.
    static var recordPlace: RecordStore.Place {
        #if DEBUG
        keepsRecordsInMemory ? .memory : .folder(RecordStore.debugFolder)
        #else
        .folder(RecordStore.folder)
        #endif
    }

    /// `-sample-plays 3` fills this launch's store, in memory, with three finished plays, each different (see
    /// `PlayRecord.samples`); `-sample-plays 0` leaves it empty. None in a release build.
    static var samplePlays: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-sample-plays"), index + 1 < arguments.count else { return 0 }
        return max(0, Int(arguments[index + 1]) ?? 0)
        #else
        return 0
        #endif
    }

    #if DEBUG
    private static var keepsRecordsInMemory: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let keepsNoToy = arguments.firstIndex(of: "-keeps-toy").map { $0 + 1 < arguments.count && arguments[$0 + 1] == "NO" } ?? false
        let setsUpToy = keepsNoToy || move != nil || settingRings != nil || ScreenLaunchOptions.playsLastMove
            || StoreCapture.isActive || Capture.request != nil
        return setsUpToy || arguments.contains("-sample-plays")
    }

    /// `-set-rings 110100000` opens the app setting the rings by hand, set to that arrangement: nine digits, ring 1
    /// first, 1 for on.
    static var settingRings: PuzzleState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-set-rings"), index + 1 < arguments.count else { return nil }
        return PuzzleState(arguments[index + 1])
    }
    #endif
}
