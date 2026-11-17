import Foundation
import Motion
import Puzzle
import Session

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
        case .resting(let state):
            if state == .allOff {
                return LocalizedStringResource("All rings are off.", comment: "Status when every ring is off the sword. The congratulation says the rest.")
            }
            #if os(macOS)
            if state == .allOn {
                return LocalizedStringResource("All nine rings are on the sword. Click a ring to move it.", comment: "Status at the start, with every ring on, on the Mac. A ring is clicked in the 3D view or by its numbered button.")
            }
            return LocalizedStringResource("Click a ring to move it.", comment: "Status when nothing is moving, on the Mac. A ring is clicked in the 3D view or by its numbered button.")
            #else
            if state == .allOn {
                return LocalizedStringResource("All nine rings are on the sword. Tap a ring to move it.", comment: "Status at the start, with every ring on. A ring is tapped in the 3D view or by its numbered button.")
            }
            return LocalizedStringResource("Tap a ring to move it.", comment: "Status when nothing is moving. A ring is tapped in the 3D view or by its numbered button.")
            #endif
        }
    }

    /// Why `ring` cannot move, from the rule: ring k needs ring k−1 on and rings 1 to k−2 off.
    static func blocked(_ ring: Int, by block: PuzzleState.Block) -> LocalizedStringResource {
        switch block {
        case .earlierRingOn(let earlier):
            LocalizedStringResource(
                "Ring \(ring) can’t move while ring \(earlier) is on: ring \(earlier)’s rod stands in the slot between ring \(ring) and the tip.",
                comment: "Why a ring cannot move. The first and fourth variables are the ring tapped; the second and third a ring before it (a lower number) that is on. A ring's rod is the wire that holds it; the slot is the gap between the sword's two rails; the tip is the sword's rounded end."
            )
        case .previousRingOff(let previous):
            LocalizedStringResource(
                "Ring \(ring) can’t move while ring \(previous) is off: ring \(previous)’s rod runs through ring \(ring), and that rod is out of the slot, so ring \(ring) can’t pass through the slot.",
                comment: "Why a ring cannot move. The first, fourth and fifth variables are the ring tapped; the second and third the ring just before it, which is off. A ring's rod is the wire that holds it; the slot is the gap between the sword's two rails."
            )
        }
    }

    /// A short reason, for a ring button's spoken hint.
    static func shortReason(_ block: PuzzleState.Block) -> LocalizedStringResource {
        switch block {
        case .earlierRingOn(let earlier):
            LocalizedStringResource("can’t move while ring \(earlier) is on", comment: "Spoken hint on a ring button that cannot move. The variable is a ring before it (a lower number) that is on.")
        case .previousRingOff(let previous):
            LocalizedStringResource("can’t move while ring \(previous) is off", comment: "Spoken hint on a ring button that cannot move. The variable is the ring just before it, which is off.")
        }
    }

    /// The stage's name, translated when the stage names' String Catalog has it, with the ring's number filled in
    /// where it holds one. The motion code keys it in English.
    static func stageName(_ stage: Stage) -> String {
        let name = String(localized: String.LocalizationValue(stage.key), table: "Stages")
        guard let ring = stage.ring else { return name }
        return String.localizedStringWithFormat(name, ring)
    }
}
