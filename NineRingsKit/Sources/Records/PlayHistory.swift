import Foundation
import Puzzle
import Session

/// The finished plays as a screen shows them. They are values, so what is kept behind them can change while a screen
/// shows them.
public struct PlayHistory: Sendable, Equatable {
    /// Every finished play this build can read, newest first, one for each play: no two have the same `playID`.
    public var plays: [PlayRecord]
    /// How many finished plays are kept that this build cannot read, one for each play. A newer version of the app can
    /// leave them, with rules this build does not know (``PlayRecord/rules``). They are not among `plays`.
    public var unreadable: Int

    public init(plays: [PlayRecord] = [], unreadable: Int = 0) {
        self.plays = plays
        self.unreadable = unreadable
    }

    /// No play kept.
    public static let empty = PlayHistory()
}

extension PlayRecord {
    /// `count` finished plays for trying the app, newest first: the newest finished at `latest`, and each a day before
    /// the one after it. Each goes from every ring on to every ring off, and no two have the same numbers. They take
    /// four kinds in turn: the shortest way; with undos; with moves played for the person; and the long way, with
    /// moves toward every ring on and back. So among three or more there is one of each of the first three.
    public static func samples(_ count: Int, latest: Date) -> [PlayRecord] {
        let distance = abs(PuzzleState.allOn.rank - PuzzleState.allOff.rank)
        return (0..<max(0, count)).map { index in
            let round = index / 4
            var moves = distance
            var undos = 0
            var playedForThePerson = 0
            let seconds: Double
            switch index % 4 {
            case 0:
                seconds = 540
            case 1:
                undos = 4 + round
                seconds = 780
            case 2:
                playedForThePerson = 60 + 20 * round
                seconds = 420
            default:
                moves += 2 * (3 + round)
                seconds = 960
            }
            // 61 seconds more each round keeps every time apart from every other: no two bases differ by a multiple.
            let secondsSpent = seconds + 61 * Double(round)
            let finishedAt = latest.addingTimeInterval(-86_400 * Double(index))
            return PlayRecord(
                playID: UUID(), startedAt: finishedAt.addingTimeInterval(-1.5 * secondsSpent), finishedAt: finishedAt,
                startRings: .allOn, endRings: .allOff, moves: moves, undos: undos, movesPlayedForThePerson: playedForThePerson,
                secondsSpent: secondsSpent
            )
        }
    }
}
