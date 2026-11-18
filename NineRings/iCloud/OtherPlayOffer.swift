import SwiftUI

/// The one quiet line that offers the other play, when the play has parted in two: neither toy was made knowing the
/// other, so neither replaces the other by itself. A play parts so rarely that the line says no more than that, with its
/// two choices: *Play That One* takes the other device's play up in place of this one; *Keep This One* keeps this one,
/// and the other device then follows by itself. It floats over the toy, above the controls, in the glass of the line
/// that says why a ring cannot move. It stays until the person chooses, or the other device settles it. VoiceOver hears
/// it as it appears.
struct OtherPlayOffer: View {
    let playThatOne: () -> Void
    let keepThisOne: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                line
                Spacer(minLength: 0)
                choices
            }
            VStack(alignment: .leading, spacing: 10) {
                line
                choices
            }
        }
        .font(.subheadline)
        .dynamicTypeSize(...ControlPanel.largestTextSize)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private var line: some View {
        Label {
            Text(Self.text)
        } icon: {
            Image(systemName: "icloud")
                .foregroundStyle(.tint)
        }
    }

    private var choices: some View {
        HStack(spacing: 8) {
            Button(action: playThatOne) {
                Text("offer.playThatOne", tableName: "Screens", comment: "A button beside the line saying another device has a different play: takes that play up here in place of this one.")
            }
            .accessibilityHint(Text("offer.playThatOne.hint", tableName: "Accessibility", comment: "VoiceOver's hint on the button that takes up the other device's play."))
            Button(action: keepThisOne) {
                Text("offer.keepThisOne", tableName: "Screens", comment: "A button beside the line saying another device has a different play: keeps the play on this device; the other device then follows.")
            }
            .accessibilityHint(Text("offer.keepThisOne.hint", tableName: "Accessibility", comment: "VoiceOver's hint on the button that keeps this device's play."))
        }
        .buttonStyle(.bordered)
        #if os(macOS)
        // The Mac's buttons keep their own font; at the small size it is the line's.
        .controlSize(.small)
        #endif
        .fixedSize()
    }

    /// The line, which VoiceOver also says as it appears.
    static let text = LocalizedStringResource(
        "offer.line", table: "Screens",
        comment: "The one line that shows when the person's play went on apart on two devices. Two buttons follow: play the other device's play here, or keep this one."
    )
}
