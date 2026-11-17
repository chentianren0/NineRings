import Foundation
import Puzzle
import Session

/// The words said to someone who cannot see the toy, beyond what the screen shows: what the toy is, where a ring went,
/// and what each line of ``Narration`` says. Where the screen has words for it already (the status line, the reason a
/// ring cannot move), these are those words; the rest are in `Accessibility.xcstrings`.
enum Spoken {
    /// What the toy is: the rings on, then the rings that can move. "Rings 1 to 3 and 5 are on. Rings 1 and 4 can move."
    static func summary(_ summary: ToySummary) -> String {
        [on(summary), movable(summary.movable)].joined(separator: " ")
    }

    /// Which rings are on.
    private static func on(_ summary: ToySummary) -> String {
        switch summary.onCount {
        case 0:
            String(localized: Sentences.status(.resting(.allOff)))
        case PuzzleState.ringCount:
            String(localized: "toy.allOn", table: "Accessibility")
        case 1:
            String(localized: "toy.oneOn \(summary.on[0].lowerBound)", table: "Accessibility")
        default:
            String(localized: "toy.someOn \(list(summary.on))", table: "Accessibility")
        }
    }

    /// Runs of rings as a list: a run of three or more as "1 to 3", shorter runs ring by ring.
    private static func list(_ runs: [ClosedRange<Int>]) -> String {
        let items = runs.flatMap { run -> [String] in
            if run.count >= 3 {
                return [String(localized: "toy.run \(run.lowerBound) \(run.upperBound)", table: "Accessibility")]
            }
            return run.map { $0.formatted() }
        }
        return items.formatted(.list(type: .and))
    }

    /// Which rings can move: one or two.
    private static func movable(_ rings: [Int]) -> String {
        if rings.count == 1 {
            return String(localized: "toy.movable.one \(rings[0])", table: "Accessibility")
        }
        return String(localized: "toy.movable.some \(rings.map { $0.formatted() }.formatted(.list(type: .and)))", table: "Accessibility")
    }

    /// What a move that ended says: the ring on or off, and, when it was the last, that every ring is off.
    static func ended(ring: Int, state: PuzzleState) -> String {
        let ring = state.isOn(ring)
            ? String(localized: "ring.isOn \(ring)", table: "Accessibility")
            : String(localized: "ring.isOff \(ring)", table: "Accessibility")
        guard state == .allOff else { return ring }
        return [ring, String(localized: Sentences.status(.resting(.allOff)))].joined(separator: " ")
    }

    /// The words for one line of narration.
    static func line(_ line: Narration.Line) -> String {
        switch line {
        case .began(let status), .paused(let status):
            String(localized: Sentences.status(status))
        case .ended(let ring, let state):
            ended(ring: ring, state: state)
        case .refused(let ring, let block):
            String(localized: Sentences.blocked(ring, by: block))
        case .rested(let summary):
            Self.summary(summary)
        }
    }

    /// The words for all of it, in order.
    static func narration(_ narration: Narration) -> String {
        narration.lines.map(line).joined(separator: " ")
    }
}
