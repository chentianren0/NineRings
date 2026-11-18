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
    @Environment(\.reducesMotion) private var reducesMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        // Escape, or VoiceOver's two-finger scrub, closes it as Done does.
        .accessibilityAction(.escape, onDone)
        .onAppear {
            // The seal bounces once as the card appears; with Reduce Motion it stays still.
            appeared = !reducesMotion
            // It does not hold the toy, so it is said rather than given the focus: the person stays where they were.
            let title = String(localized: "congratulation.title", table: "Screens")
            let text = String(localized: "congratulation.text", table: "Screens")
            Announcer.say("\(title). \(text)")
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

    /// A row whose words take two or three lines: on a short, wide screen, such as a phone held sideways, where the
    /// one-line row is too wide and the stacked card would reach down to the controls.
    private var wrappedRow: some View {
        HStack(spacing: 16) {
            seal
            words(alignment: .leading)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 12) { buttons }
                .fixedSize()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(maxWidth: 820)
    }

    /// One low row where the window is wide enough, so that it stays clear of the sword; stacked where it is not. At the
    /// accessibility text sizes always stacked, and scrolling: measured to fit a row, a scroll view would take its whole
    /// height and never scroll.
    @ViewBuilder
    private var layout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                row
                wrappedRow
                stacked
            }
        }
    }

    /// Stacked; at the accessibility text sizes, where it can be taller than the screen, it scrolls, and its buttons are
    /// rounded rectangles, which a label of two or three lines fits.
    @ViewBuilder
    private var stacked: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView { stackedContent }
                .scrollBounceBehavior(.basedOnSize)
                .clipShape(.rect(cornerRadius: 28))
                .buttonBorderShape(.roundedRectangle(radius: 16))
        } else {
            stackedContent
        }
    }

    private var stackedContent: some View {
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
                .supportingTextStyle()
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onPutBack) {
            // Wraps rather than truncates at the largest text sizes.
            Text("congratulation.putBack", tableName: "Screens")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
    /// on, covering the toy as Reset does. With `overlays` false the card is not drawn here, for a view that places
    /// it itself with `CongratulationCard(player:putBack:)`.
    func congratulation(_ player: Player, overlays: Bool = true, putBack: @escaping () -> Void) -> some View {
        modifier(CongratulationOverlay(player: player, overlays: overlays, putBack: putBack))
    }
}

extension CongratulationCard {
    /// The card for `player`: Done closes it, and "Put Every Ring Back On" closes it and calls `putBack`.
    init(player: Player, putBack: @escaping () -> Void) {
        self.init {
            player.dismissCongratulation()
            putBack()
        } onDone: {
            player.dismissCongratulation()
        }
    }
}

private struct CongratulationOverlay: ViewModifier {
    let player: Player
    let overlays: Bool
    let putBack: () -> Void
    @Environment(\.reducesMotion) private var reducesMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if overlays, player.isCongratulating {
                    CongratulationCard(player: player, putBack: putBack)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .appearingOverToy(reducesMotion: reducesMotion)
                }
            }
            .animation(ScreenMotion.card, value: player.isCongratulating)
            #if DEBUG
            .task {
                // `-play-last-move` opens the toy one move before every ring is off and plays that move, as a tap would.
                guard ScreenLaunchOptions.playsLastMove, let move = Move(ring: 1, from: PuzzleState("100000000")!) else { return }
                player.begin(at: move)
            }
            #endif
    }
}
