import Session
import SwiftUI

/// The controls of the puzzle: a line saying what is happening, the nine ring buttons, and a row with undo, play
/// or pause, the slider through the move, the speed and solve.
///
/// Floating over the toy, the panel keeps one height, so that the toy, framed above it, never jumps: the line keeps
/// its lines, and the reason a ring cannot move shows in a bubble above the panel. Where the panel is wide enough,
/// the ring buttons and the row of controls sit side by side under a one-line caption, so that the panel stays low:
/// the toy is long and low, and a wide, short window needs its height for it. In a column beside the toy, the line
/// takes as many lines as it needs and says the reason itself.
struct ControlPanel: View {
    enum Style {
        case floating
        case column
    }

    @Bindable var player: Player
    let style: Style
    @State private var width: CGFloat = 0

    /// The width the ring buttons take when they share a row with the controls.
    private static let ringsInRow: CGFloat = 356
    /// The least width the controls take beside them.
    private static let transportInRow: CGFloat = 300
    private static let rowSpacing: CGFloat = 20
    private static let padding: CGFloat = 16

    /// Whether the panel is wide enough for the ring buttons and the controls in one row.
    private var isOneRow: Bool {
        style == .floating && width >= Self.ringsInRow + Self.rowSpacing + Self.transportInRow + 2 * Self.padding
    }

    var body: some View {
        Group {
            if style == .column {
                VStack(alignment: .leading, spacing: 20) {
                    caption(lines: nil)
                    rings
                    transport
                    Spacer(minLength: 0)
                }
            } else if isOneRow {
                VStack(alignment: .leading, spacing: 10) {
                    caption(lines: 1)
                    HStack(spacing: Self.rowSpacing) {
                        rings
                            .frame(width: Self.ringsInRow)
                        transport
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    caption(lines: 2)
                    rings
                    transport
                }
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var rings: some View {
        RingButtons(markers: player.markers) { player.tap($0) }
    }

    /// Why the last ring asked for could not move, when that is the news.
    static func refusal(in status: PuzzleSession.Status) -> LocalizedStringResource? {
        if case .note = status { return Sentences.status(status) }
        return nil
    }

    private var refusal: LocalizedStringResource? { Self.refusal(in: player.status) }

    private var captionText: LocalizedStringResource {
        if style == .floating, refusal != nil {
            return Sentences.status(.resting(player.poseKey.state))
        }
        return Sentences.status(player.status)
    }

    /// The line that says what is happening, holding the place of `lines` lines, or as many as it needs when nil.
    private func caption(lines: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            if let lines {
                // Holds the lines' place, so that the panel keeps its height.
                Text(verbatim: String(repeating: "\n", count: lines - 1) + " ").hidden().accessibilityHidden(true)
            }
            Text(captionText)
                .foregroundStyle(style == .column && refusal != nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                .lineLimit(lines)
                .contentTransition(.opacity)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button(action: player.undo) {
                Label { Text("Undo", comment: "Button that takes back the last move.") } icon: { Image(systemName: "arrow.uturn.backward") }
            }
            .disabled(!player.canUndo)
            .keyboardShortcut("z", modifiers: .command)

            Button(action: player.togglePlay) {
                Label {
                    player.isPlaying
                        ? Text("Pause", comment: "Button that stops the move part way.")
                        : Text("Play", comment: "Button that plays the move on the slider.")
                } icon: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.title)
            }
            .disabled(!player.canPlay && !player.isPlaying)
            .keyboardShortcut(.space, modifiers: [])

            Slider(value: $player.progress, in: 0...1) {
                Text("Progress", comment: "Spoken name of the slider that runs through the move.")
            } onEditingChanged: { editing in
                if editing { player.pause() }
            }
            .labelsHidden()
            .disabled(!player.hasMove)

            Menu {
                Picker(selection: $player.speed) {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                } label: {
                    Text("Speed", comment: "Menu of the speeds moves play at.")
                }
                .pickerStyle(.inline)
            } label: {
                Text("\(player.speed.factor, format: .number)×", comment: "The speed button's label: how many times the normal speed moves play at, such as 0.5×.")
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 36)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Speed", comment: "Menu of the speeds moves play at."))

            Button(action: player.solve) {
                Label { Text("Solve", comment: "Button that plays the moves left to take every ring off.") } icon: { Image(systemName: "forward.end.fill") }
            }
            .disabled(!player.canSolve)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
        .controlSize(.large)
    }
}

/// The reason a ring cannot move, above the floating panel, until the next request.
struct RefusalBubble: View {
    let text: LocalizedStringResource

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
