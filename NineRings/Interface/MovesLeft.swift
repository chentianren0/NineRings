import Puzzle
import SwiftUI

/// How many moves the toy is from every ring off, beside the status line: the toy's place on the one line of moves,
/// 341 with every ring on, and up to 511 the other way, toward ring 9 alone. It counts the rings the ring buttons show,
/// so that the two agree, and both change at the tap rather than when the move ends.
///
/// It reads "341 moves left", "341 left" or "341": the fullest of the three beside which the longest thing the status
/// says still fits in the status's lines, laid out as the status lays it out, in the language and at the text size in
/// use. Where none leaves it room, as with the largest text beside the toy on a half-folded iPhone Duo, the count steps
/// aside and the status has the whole line: what the status says comes first. The panel says what the longest thing
/// is; the form follows the panel and the text size alone, never what the status says now, so that it does not change
/// while moves play. VoiceOver says the count in full whatever its form. Each form holds the width of its widest
/// number, so that the status keeps its line breaks as the number changes.
struct MovesLeft<LongestStatus: View>: View {
    let state: PuzzleState
    /// The width the status line and the count share.
    let lineWidth: CGFloat
    /// How many lines the status line holds.
    let lines: Int
    /// The longest thing the status line says, as it shows it.
    @ViewBuilder let longestStatus: LongestStatus

    /// Each form's width at its widest, at the text size in use.
    @State private var widths: [Form: CGFloat] = [:]
    /// The height the longest status takes beside each form.
    @State private var statusHeights: [Form: CGFloat] = [:]
    /// The height of the status's lines.
    @State private var linesHeight: CGFloat = 0
    @Environment(\.reducesMotion) private var reducesMotion

    enum Form: CaseIterable {
        case full, short, number
    }

    /// The fullest form beside which the longest status fits in its lines; none where none does. It fits when it takes
    /// no more lines than the status has: within half a line of their height, since a label with a symbol stands a
    /// fraction of a point taller than plain text of as many lines.
    private var form: Form? {
        let limit = linesHeight + linesHeight / CGFloat(max(lines, 1)) / 2
        return Form.allCases.first { (statusHeights[$0] ?? .infinity) <= limit }
    }

    /// The space between the status and the count, when the count shows.
    private static var spacing: CGFloat { 12 }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let form {
                widest(form)
                    .hidden()
                Self.label(state.rank, form)
                    .contentTransition(reducesMotion ? .opacity : .numericText(value: Double(state.rank)))
            }
        }
        .padding(.leading, form == nil ? 0 : Self.spacing)
        .background(alignment: .topTrailing) { measures }
        .animation(ScreenMotion.small, value: state.rank)
        .supportingTextStyle()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.fullText(state.rank))
        .accessibilityAddTraits(.isStaticText)
        .accessibilityHidden(form == nil)
    }

    /// What the form is chosen from, measured out of sight: each form's width, the longest status laid out beside each,
    /// and the height of the status's lines.
    private var measures: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Form.allCases, id: \.self) { form in
                widest(form)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[form] = $0 }
                longestStatus
                    .frame(width: max(0, lineWidth - Self.spacing - (widths[form] ?? 0)), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statusHeights[form] = $0 }
            }
            Text(verbatim: String(repeating: "\n", count: max(lines, 1) - 1) + " ")
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { linesHeight = $0 }
        }
        .hidden()
    }

    /// The form at its widest: numbers that between them fall in every plural category a language gives a three-digit
    /// number. The digits themselves are all one width.
    private func widest(_ form: Form) -> some View {
        ZStack(alignment: .trailing) {
            ForEach([100, 101, 102, 103, 111], id: \.self) { Self.label($0, form) }
        }
    }

    private static func label(_ count: Int, _ form: Form) -> some View {
        Group {
            switch form {
            case .full:
                fullText(count)
            case .short:
                Text("\(count) left", comment: "In the control panel, where there is little room: how many moves the toy is from every ring off, such as 341 left with every ring on. In full it reads 341 moves left.")
            case .number:
                Text(count, format: .number)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    private static func fullText(_ count: Int) -> Text {
        Text("\(count) moves left", comment: "In the control panel, how many moves the toy is from every ring off, such as 341 moves left with every ring on. VoiceOver reads it so too.")
    }
}
