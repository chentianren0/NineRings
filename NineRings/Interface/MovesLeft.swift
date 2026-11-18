import Puzzle
import SwiftUI

/// How many moves the toy is from every ring off, beside the status line: the toy's place on the one line of moves,
/// 341 with every ring on, and up to 511 the other way, toward ring 9 alone. It counts the rings the ring buttons show,
/// so that the two agree, and both change at the tap rather than when the move ends.
///
/// It reads "341 moves left". Where the status line would not keep room beside those words for its longest sentences, it
/// is short; VoiceOver says it in full whatever its form. The form follows the panel and the text size alone, never the
/// status, so that it does not change while moves play. Each form holds the width of its widest number, so that the
/// status keeps its line breaks as the number changes.
struct MovesLeft: View {
    /// Where the setting is kept: whether the control panel shows the count. On at first.
    static let isShownKey = "settings.movesLeft"

    let state: PuzzleState
    /// The width the status line and the count share, less the space between them.
    let lineWidth: CGFloat
    /// How many lines the status line holds.
    let lines: Int

    /// The width of the full words at their widest, measured at the text size in use.
    @State private var fullWidth: CGFloat = 0
    @Environment(\.reducesMotion) private var reducesMotion

    /// The room the status line keeps beside the count, in widths of the count's full words: its longest sentences are
    /// about four times as long as "341 moves left", and a sentence that wraps leaves the end of a line empty.
    private static let statusRoom: CGFloat = 4.5

    /// Numbers that between them fall in every plural category a language gives a three-digit number, so that the
    /// width held is the widest the words take. The digits themselves are all one width.
    private static let widestNumbers = [100, 101, 102, 103, 111]

    private enum Form {
        case full, short
    }

    /// Short where the status, beside the full words, would not keep room for its longest sentences over its lines.
    private var form: Form {
        CGFloat(lines) * (lineWidth - fullWidth) >= Self.statusRoom * fullWidth ? .full : .short
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            widest(form)
            Self.label(state.rank, form)
                .contentTransition(reducesMotion ? .opacity : .numericText(value: Double(state.rank)))
        }
        .background(alignment: .trailing) {
            widest(.full)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
        }
        .animation(ScreenMotion.small, value: state.rank)
        .monospacedDigit()
        .supportingTextStyle()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.fullText(state.rank))
        .accessibilityAddTraits(.isStaticText)
    }

    /// The form at its widest, hidden: it holds the place.
    private func widest(_ form: Form) -> some View {
        ZStack(alignment: .trailing) {
            ForEach(Self.widestNumbers, id: \.self) { Self.label($0, form) }
        }
        .hidden()
    }

    @ViewBuilder
    private static func label(_ count: Int, _ form: Form) -> some View {
        switch form {
        case .full: fullText(count)
        case .short:
            Text("\(count) left", comment: "In the control panel, where there is little room: how many moves the toy is from every ring off, such as 341 left with every ring on. In full it reads 341 moves left.")
        }
    }

    private static func fullText(_ count: Int) -> Text {
        Text("\(count) moves left", comment: "In the control panel, how many moves the toy is from every ring off, such as 341 moves left with every ring on. VoiceOver reads it so too.")
    }
}
