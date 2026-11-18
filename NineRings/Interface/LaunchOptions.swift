import Foundation
import Motion
import Puzzle

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

    /// Whether the person's toy is kept between launches. A release build always keeps it. A debug build keeps it
    /// unless `-keeps-toy NO` is passed or another option sets up the toy (`-move`, `-set-rings`), so that a launch for
    /// a picture starts where it says and leaves the toy kept as it was.
    static var keepsToy: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-keeps-toy"), index + 1 < arguments.count, arguments[index + 1] == "NO" { return false }
        return move == nil && settingRings == nil
        #else
        return true
        #endif
    }

    #if DEBUG
    /// `-set-rings 110100000` opens the app setting the rings by hand, set to that arrangement: nine digits, ring 1
    /// first, 1 for on.
    static var settingRings: PuzzleState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-set-rings"), index + 1 < arguments.count else { return nil }
        return PuzzleState(arguments[index + 1])
    }
    #endif
}
