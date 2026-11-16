import Foundation
import Motion
import Puzzle
import Session
import SwiftUI

/// The one line that says what is happening, or why nothing is.
struct StatusLine: View {
    let status: PuzzleSession.Status

    var body: some View {
        Label {
            // Two lines are always kept, so that the controls do not jump as the line changes. A long reason takes
            // as many more as it needs: cut short, it would no longer say why.
            ZStack(alignment: .topLeading) {
                Text(verbatim: "\n").hidden().accessibilityHidden(true)
                Text(Sentences.status(status))
                    .foregroundStyle(isQuiet ? .secondary : .primary)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(isBlocked ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onChange(of: status) { _, status in
            // A refusal comes after a tap with nothing moving, so say it aloud to someone who cannot see it.
            if case .note = status {
                AccessibilityNotification.Announcement(String(localized: Sentences.status(status))).post()
            }
        }
    }

    private var isBlocked: Bool {
        if case .note(.blocked) = status { return true }
        return false
    }

    /// A move not written yet is a passing gap in the app, not something the person did wrong: it is said quietly.
    private var isQuiet: Bool {
        if case .note(.notWritten) = status { return true }
        return false
    }

    private var symbol: String {
        switch status {
        case .playing: "play.fill"
        case .paused: "pause.fill"
        case .note(.blocked): "hand.raised.fill"
        case .note(.notWritten): "pencil.line"
        case .resting: "hand.tap"
        }
    }
}

/// Every sentence the screen says about the puzzle, kept in the String Catalog.
enum Sentences {
    static func status(_ status: PuzzleSession.Status) -> LocalizedStringResource {
        switch status {
        case .playing(let move, let stage, let undoing):
            let stage = stageName(stage)
            if undoing {
                return move.takesOff
                    ? LocalizedStringResource("Undoing: ring \(move.ring) comes back off — \(stage)", comment: "Status while undoing a move that put a ring on. The first variable is the ring's number, the second the name of the stage the move is in.")
                    : LocalizedStringResource("Undoing: ring \(move.ring) goes back on — \(stage)", comment: "Status while undoing a move that took a ring off. The first variable is the ring's number, the second the name of the stage the move is in.")
            }
            return move.takesOff
                ? LocalizedStringResource("Ring \(move.ring) comes off — \(stage)", comment: "Status while a ring comes off. The first variable is the ring's number, the second the name of the stage the move is in.")
                : LocalizedStringResource("Ring \(move.ring) goes on — \(stage)", comment: "Status while a ring goes on. The first variable is the ring's number, the second the name of the stage the move is in.")
        case .paused(let move, let stage, _):
            let stage = stageName(stage)
            return move.takesOff
                ? LocalizedStringResource("Paused: ring \(move.ring) coming off — \(stage)", comment: "Status while a ring's move is stopped part way. The first variable is the ring's number, the second the name of the stage.")
                : LocalizedStringResource("Paused: ring \(move.ring) going on — \(stage)", comment: "Status while a ring's move is stopped part way. The first variable is the ring's number, the second the name of the stage.")
        case .note(.blocked(let ring, let block)):
            return blocked(ring, by: block)
        case .note(.notWritten(let move, let whileSolving)):
            if whileSolving {
                return move.takesOff
                    ? LocalizedStringResource("Solving stopped: the next move, ring \(move.ring) coming off, is not in the app yet.", comment: "Status when solving reaches a move the app cannot show yet. The variable is the ring's number.")
                    : LocalizedStringResource("Solving stopped: the next move, ring \(move.ring) going on, is not in the app yet.", comment: "Status when solving reaches a move the app cannot show yet. The variable is the ring's number.")
            }
            return move.takesOff
                ? LocalizedStringResource("Ring \(move.ring) can come off now, but that move is not in the app yet.", comment: "Status after tapping a ring whose move is allowed but not yet in the app. The variable is the ring's number.")
                : LocalizedStringResource("Ring \(move.ring) can go on now, but that move is not in the app yet.", comment: "Status after tapping a ring whose move is allowed but not yet in the app. The variable is the ring's number.")
        case .resting(let state):
            if state == .allOff {
                return LocalizedStringResource("All rings are off. The puzzle is solved.", comment: "Status when every ring is off the sword.")
            }
            #if os(macOS)
            if state == .allOn {
                return LocalizedStringResource("All nine rings are on the sword. Click a numbered marker to move its ring.", comment: "Status at the start, with every ring on, on the Mac. The markers are the row of numbered discs, one for each ring.")
            }
            return LocalizedStringResource("Click a numbered marker to move its ring.", comment: "Status when nothing is moving, on the Mac. The markers are the row of numbered discs, one for each ring.")
            #else
            if state == .allOn {
                return LocalizedStringResource("All nine rings are on the sword. Tap a numbered marker to move its ring.", comment: "Status at the start, with every ring on. The markers are the row of numbered discs, one for each ring.")
            }
            return LocalizedStringResource("Tap a numbered marker to move its ring.", comment: "Status when nothing is moving. The markers are the row of numbered discs, one for each ring.")
            #endif
        }
    }

    /// Why `ring` cannot move, from the rule: ring k needs ring k−1 on and rings 1 to k−2 off.
    static func blocked(_ ring: Int, by block: PuzzleState.Block) -> LocalizedStringResource {
        switch block {
        case .earlierRingOn(let earlier):
            LocalizedStringResource(
                "Ring \(ring) can’t move while ring \(earlier) is on: ring \(earlier)’s rod stands in the slot between ring \(ring) and the tip.",
                comment: "Why a ring cannot move. The first and fourth variables are the ring tapped; the second and third the earlier ring that is on. A ring's rod is the wire that holds it; the slot is the gap between the sword's two rails; the tip is the sword's rounded end."
            )
        case .previousRingOff(let previous):
            LocalizedStringResource(
                "Ring \(ring) can’t move while ring \(previous) is off: ring \(previous)’s rod runs through ring \(ring), and that rod is out of the slot, so ring \(ring) can’t pass through the slot.",
                comment: "Why a ring cannot move. The first, fourth and fifth variables are the ring tapped; the second and third the ring just before it, which is off. A ring's rod is the wire that holds it; the slot is the gap between the sword's two rails."
            )
        }
    }

    /// A short reason, for a marker's spoken value.
    static func shortReason(_ block: PuzzleState.Block) -> LocalizedStringResource {
        switch block {
        case .earlierRingOn(let earlier):
            LocalizedStringResource("can’t move while ring \(earlier) is on", comment: "Part of a ring marker's spoken value. The variable is the earlier ring that is on.")
        case .previousRingOff(let previous):
            LocalizedStringResource("can’t move while ring \(previous) is off", comment: "Part of a ring marker's spoken value. The variable is the ring just before, which is off.")
        }
    }

    /// The stage's name, translated when the String Catalog has it; the motion code writes it in English.
    static func stageName(_ stage: Stage) -> String {
        String(localized: String.LocalizationValue(stage.name), table: "Stages")
    }
}
