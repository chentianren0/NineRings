import Accessibility
import Motion
import Puzzle
import SwiftUI

/// The congratulation, when the person's own move has taken the last ring off: a calm card floating over the top of
/// the toy, one low row where there is room, so that the toy with every ring off stays in view below it. It does not
/// hold the toy: a tap on a ring, or anything else done with the toy, closes it, as Done does. "Put Every Ring Back
/// On" starts again.
///
/// When it appears is ``Player/isCongratulating``, from the rule in `Session`'s `Congratulation`.
struct CongratulationCard: View {
    let onPutBack: () -> Void
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        // One low row where the window is wide enough, so that it stays clear of the sword; stacked where it is not.
        ViewThatFits(in: .horizontal) {
            row
            stacked
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .onAppear {
            appeared = true
            let title = String(localized: "congratulation.title", table: "Screens")
            let text = String(localized: "congratulation.text", table: "Screens")
            AccessibilityNotification.Announcement("\(title). \(text)").post()
        }
    }

    private var row: some View {
        HStack(spacing: 16) {
            seal
            words(alignment: .leading)
                .fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 12) { buttons }
                .fixedSize()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: 820)
    }

    private var stacked: some View {
        VStack(spacing: 12) {
            seal
            words(alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(spacing: 8) { buttons }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 440)
    }

    private var seal: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.largeTitle)
            .foregroundStyle(.tint)
            .symbolEffect(.bounce, value: appeared)
            .accessibilityHidden(true)
    }

    private func words(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("congratulation.title", tableName: "Screens")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("congratulation.text", tableName: "Screens")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onPutBack) {
            Text("congratulation.putBack", tableName: "Screens")
        }
        .buttonStyle(.glass)
        Button(action: onDone) {
            Text("congratulation.done", tableName: "Screens")
                .frame(minWidth: 60)
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
    }
}

extension View {
    /// Shows the congratulation over the top of this view while the player says so. `putBack` puts every ring back
    /// on, covering the toy as Reset does.
    func congratulation(_ player: Player, putBack: @escaping () -> Void) -> some View {
        modifier(CongratulationOverlay(player: player, putBack: putBack))
    }
}

private struct CongratulationOverlay: ViewModifier {
    let player: Player
    let putBack: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if player.isCongratulating {
                    CongratulationCard {
                        player.dismissCongratulation()
                        putBack()
                    } onDone: {
                        player.dismissCongratulation()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.4), value: player.isCongratulating)
            #if DEBUG
            .task {
                // `-play-last-move` opens the toy one move before every ring is off and plays that move, as a tap would.
                guard ScreenLaunchOptions.playsLastMove, let move = Move(ring: 1, from: PuzzleState("100000000")!) else { return }
                player.begin(at: move)
            }
            #endif
    }
}
