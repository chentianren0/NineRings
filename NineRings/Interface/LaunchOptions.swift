import Foundation
import Motion
import Puzzle

/// Options read from the launch arguments, in a debug build only.
///
/// A build that ships reads none of the app's own launch options: whatever it is launched with, it starts as the person
/// left it. A measuring build reads only its own `-measure` (`MeasureScript`). The rule is checked in the app's sources
/// by `LaunchOptionRulesTests`.
enum LaunchOptions {
    /// `-move 2` opens the app where ring 2 first comes off on the way from every ring on to every ring off, with that
    /// move on the slider.
    static var move: Move? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-move"), index + 1 < arguments.count, let ring = Int(arguments[index + 1]) else { return nil }
        return Player.moves.first { $0.ring == ring }
        #else
        return nil
        #endif
    }

    /// `-start-progress 0.5` opens the app that far through that move, for checking a pose by hand.
    static var startProgress: Double? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-start-progress"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
        #else
        return nil
        #endif
    }

    /// `-sample-plays 3` fills this launch's history with three finished plays, each different (see
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
    /// Whether this launch sets up or plays its own toy, or asks for sample plays: `-keeps-toy NO`, `-move`,
    /// `-set-rings`, `-play-last-move`, the store's pictures, the frame capture and `-sample-plays`. Such a launch has
    /// to start where it says and leave what the person keeps as it was. Today every launch keeps its records in memory
    /// and nothing reads this; it is the list of launches that are to stay in memory once the records are kept between
    /// launches.
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
