import Motion
import Puzzle
import Session
import SwiftUI

/// The controls of the puzzle: a line saying what is happening, the nine ring buttons, and a row with undo, play
/// or pause, the slider through the move, the speed and solve.
///
/// Floating over the toy, the panel keeps one height, so that the toy, framed above it, never jumps: the line keeps
/// its lines, and the reason a ring cannot move shows in a bubble above the panel. Where the panel is wide enough,
/// the ring buttons and the row of controls sit side by side under a one-line caption, so that the panel stays low:
/// the toy is long and low, and a wide, short window needs its height for it.
///
/// Beside the toy, in a half of its own on a half-folded iPhone Duo, the controls have room: the buttons are larger,
/// and the line says the reason a ring cannot move itself.
///
/// While the person sets the rings by hand, the line says how, the ring buttons put rings on and take them off, and
/// in place of the row of controls, which move the toy and so do nothing then, two buttons set every ring on or every
/// ring off. They take the row's place exactly, so that the panel keeps its height and the toy does not move.
struct ControlPanel: View {
    enum Style {
        /// Over the toy, at the bottom of the window.
        case floating
        /// In a space of its own, beside the toy.
        case beside
    }

    @Bindable var player: Player
    let style: Style
    @State private var width: CGFloat = 0

    /// The largest text size the panel follows. Larger text would make the panel cover the toy on the smallest screens,
    /// the phone held sideways and the closed iPhone Duo; past it the panel keeps its size, and the ring buttons and
    /// the controls show their Large Content Viewer, as the system's bars do. The screens that are text (the lesson,
    /// the welcome page, settings, About, the congratulation) follow every size.
    static let largestTextSize = DynamicTypeSize.xxxLarge

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
            switch style {
            case .beside:
                VStack(alignment: .leading, spacing: 28) {
                    caption(lines: 3)
                    rings
                    controls
                }
            case .floating where isOneRow:
                VStack(alignment: .leading, spacing: 10) {
                    caption(lines: 1)
                    HStack(spacing: Self.rowSpacing) {
                        rings
                            .frame(width: Self.ringsInRow)
                        controls
                    }
                }
            case .floating:
                VStack(alignment: .leading, spacing: 12) {
                    caption(lines: 2)
                    rings
                    controls
                }
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .dynamicTypeSize(...Self.largestTextSize)
        .animation(.snappy(duration: 0.25), value: player.isSettingRings)
    }

    /// The ring buttons; dimmed while the lesson holds the toy, since asking for a ring then does nothing. (What is said
    /// aloud, a refusal among it, is the player's: see `Narration`.)
    private var rings: some View {
        RingButtons(markers: player.markers, diameter: style == .beside ? 52 : 40, settingRings: player.isSettingRings) { player.tap($0) }
            .disabled(player.lessonHoldsToy)
    }

    /// Why the last ring asked for could not move, when that is the news.
    static func refusal(in status: PuzzleSession.Status) -> LocalizedStringResource? {
        if case .note = status { return Sentences.status(status) }
        return nil
    }

    private var refusal: LocalizedStringResource? { Self.refusal(in: player.status) }

    /// What the line says: the status, or, floating while a refusal shows in the bubble, what it said before. At rest
    /// while the lesson's steps show the toy, it says so, rather than to tap a ring.
    private var captionText: LocalizedStringResource {
        if player.isSettingRings { return Sentences.settingRings }
        let status = style == .floating && refusal != nil ? PuzzleSession.Status.resting(player.poseKey.state) : player.status
        if player.lessonHoldsToy, case .resting = status {
            return Sentences.lessonHoldsToy
        }
        return Sentences.status(status)
    }

    /// The line that says what is happening, holding the place of `lines` lines, so that the panel keeps its height.
    /// Floating, it goes on saying what it said while a refusal shows in the bubble above; beside the toy, it says the
    /// refusal itself.
    private func caption(lines: Int) -> some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: String(repeating: "\n", count: lines - 1) + " ").hidden().accessibilityHidden(true)
            if style == .beside, let refusal {
                RefusalLabel(text: refusal)
                    .lineLimit(lines)
                    .transition(.opacity)
            } else {
                Text(captionText)
                    .lineLimit(lines)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
        }
        .font(style == .beside ? .body : .subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.25), value: refusal == nil)
        .accessibilityElement(children: .combine)
    }

    /// The row under the rings: the controls that move the toy, or, while the rings are set by hand, the buttons that
    /// set them all. The controls keep their place, hidden, so that the row keeps its height.
    private var controls: some View {
        transport
            .opacity(player.isSettingRings ? 0 : 1)
            .disabled(player.isSettingRings)
            .accessibilityHidden(player.isSettingRings)
            .overlay {
                if player.isSettingRings {
                    settingButtons
                        .transition(.opacity)
                }
            }
    }

    /// Every ring on, every ring off: the two arrangements a person most often starts from. Each is a capsule of its
    /// own, drawn here rather than by the bordered style, whose fill does not show on the glass panel on iPhone; the
    /// title is in the primary colour, since the tint, at this size, is under the contrast text needs.
    private var settingButtons: some View {
        HStack(spacing: 12) {
            settingButton(
                Text("All On", comment: "Button, while the rings are set by hand, that puts every ring on at once."),
                help: Text("Put every ring on", comment: "Tooltip on the All On button, while the rings are set by hand."),
                to: .allOn
            )
            settingButton(
                Text("All Off", comment: "Button, while the rings are set by hand, that takes every ring off at once."),
                help: Text("Take every ring off", comment: "Tooltip on the All Off button, while the rings are set by hand."),
                to: .allOff
            )
        }
        .font(.subheadline.weight(.semibold))
    }

    private func settingButton(_ title: Text, help: Text, to state: PuzzleState) -> some View {
        Button {
            player.setRings(to: state)
        } label: {
            title
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // The colour itself: inside a button, `.primary` is the button's own first level, the tint.
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: Self.settingButtonHeight)
                .background(.fill.secondary, in: .capsule)
                .contentShape(.capsule)
                // A borderless button keeps an explicit colour when it is disabled; fade it, as the system fades its own.
                .opacity(player.shownState == state ? 0.4 : 1)
        }
        .buttonStyle(.borderless)
        .disabled(player.shownState == state)
        .help(help)
    }

    /// As tall as the row of controls it takes the place of.
    private static var settingButtonHeight: CGFloat {
        #if os(iOS)
        40
        #else
        28
        #endif
    }

    private var transport: some View {
        HStack(spacing: Self.transportSpacing) {
            Button(action: player.undo) {
                Label { Text("Undo", comment: "Button that takes back the last move.") } icon: { Image(systemName: "arrow.uturn.backward") }
                    .touchTarget()
            }
            .disabled(!player.canUndo)
            .help(Text("Undo the last move", comment: "Tooltip on the Undo button."))

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
                .touchTarget()
            }
            .disabled(!player.canPlay && !player.isPlaying)
            .help(player.isPlaying
                ? Text("Pause the move", comment: "Tooltip on the Pause button.")
                : Text("Play the move", comment: "Tooltip on the Play button."))

            MoveSlider(player: player)

            Menu {
                Picker(selection: $player.speed) {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Text("\(speed.factor, format: .number)×", comment: "A playing speed: how many times the normal pace, such as 0.5× or 2×.").tag(speed)
                    }
                } label: {
                    Text("Speed", comment: "Menu of the speeds moves play at.")
                }
                .pickerStyle(.inline)
            } label: {
                Text("\(player.speed.factor, format: .number)×", comment: "The speed button's label: how many times the normal speed moves play at, such as 0.5×.")
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 36)
                    .touchTarget()
            }
            .menuIndicator(.hidden)
            // In the primary colour: the tint, at this text size, is under the contrast text needs.
            .tint(.primary)
            .fixedSize()
            .accessibilityLabel(Text("Speed", comment: "Menu of the speeds moves play at."))
            .help(Text("Choose how fast moves play", comment: "Tooltip on the speed button."))
            .accessibilityValue(Text(player.speed.spokenName))
            .accessibilityAdjustableAction { direction in
                let speeds = PlaybackSpeed.allCases
                guard let index = speeds.firstIndex(of: player.speed) else { return }
                switch direction {
                case .increment: player.speed = speeds[min(index + 1, speeds.count - 1)]
                case .decrement: player.speed = speeds[max(index - 1, 0)]
                @unknown default: break
                }
            }

            Button(action: player.solve) {
                Label { Text("Solve", comment: "Button that plays the moves left to take every ring off.") } icon: { Image(systemName: "forward.end.fill") }
                    .touchTarget()
            }
            .disabled(!player.canSolve)
            .help(Text("Play the moves left to take every ring off", comment: "Tooltip on the Solve button."))
        }
        .labelStyle(.iconOnly)
        .largeContentViewer()
        .buttonStyle(.borderless)
        .font(.title3)
        .controlSize(.large)
    }
}

/// The slider through the move. It is a view of its own because the progress changes every frame while a move plays:
/// only this view reads it, so the rest of the panel is not made again each frame.
private struct MoveSlider: View {
    @Bindable var player: Player

    var body: some View {
        Slider(value: $player.progress, in: 0...1) {
            Text("Progress", comment: "Spoken name of the slider that runs through the move.")
        } onEditingChanged: { editing in
            if editing { player.pause() }
        }
        .labelsHidden()
        .disabled(!player.hasMove || player.lessonHoldsToy)
        .help(Text("Drag to go through the move", comment: "Tooltip on the slider that runs through the move."))
        // Its spoken value is the stage's name rather than a number, and a swipe goes to the next or the previous
        // boundary between stages, as the menu bar's Next and Previous Stage do.
        .accessibilityValue(stageValue)
        .accessibilityAdjustableAction { direction in
            let boundary = switch direction {
            case .increment: ToyCommands.boundary(after: player.progress, in: player.stages)
            case .decrement: ToyCommands.boundary(before: player.progress, in: player.stages)
            @unknown default: Double?.none
            }
            if let boundary { player.progress = boundary }
        }
    }

    /// The slider's spoken value: the name of the stage it is in.
    private var stageValue: Text {
        let progress = player.progress
        guard let stage = player.stages.last(where: { $0.start <= progress }) ?? player.stages.first else {
            return Text(verbatim: "")
        }
        return Text(verbatim: Sentences.stageName(stage))
    }
}

extension PlaybackSpeed {
    /// The speed in words, as VoiceOver says it.
    var spokenName: LocalizedStringResource {
        switch self {
        case .quarter: LocalizedStringResource("speed.quarter", table: "Accessibility")
        case .half: LocalizedStringResource("speed.half", table: "Accessibility")
        case .normal: LocalizedStringResource("speed.normal", table: "Accessibility")
        case .double: LocalizedStringResource("speed.double", table: "Accessibility")
        case .quadruple: LocalizedStringResource("speed.quadruple", table: "Accessibility")
        }
    }
}

/// The reason a ring cannot move, with a raised hand.
private struct RefusalLabel: View {
    let text: LocalizedStringResource

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
        }
    }
}

extension ControlPanel {
    /// The space between the controls under the rings: less on iPhone and iPad, where each control has a touch target
    /// of 44 points around it.
    fileprivate static var transportSpacing: CGFloat {
        #if os(iOS)
        4
        #else
        14
        #endif
    }
}

private extension View {
    /// The least touch target Apple asks for on iPhone and iPad, 44 by 44 points, around a small control.
    @ViewBuilder
    func touchTarget() -> some View {
        #if os(iOS)
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        #else
        self
        #endif
    }

    /// The Large Content Viewer for the controls, on iPhone and iPad: past the panel's largest text size, a long press
    /// shows a control's symbol and name enlarged.
    @ViewBuilder
    func largeContentViewer() -> some View {
        #if os(iOS)
        accessibilityShowsLargeContentViewer()
        #else
        self
        #endif
    }
}

/// The reason a ring cannot move, above the floating panel, until the next request.
struct RefusalBubble: View {
    let text: LocalizedStringResource

    var body: some View {
        RefusalLabel(text: text)
            .font(.subheadline)
            .dynamicTypeSize(...ControlPanel.largestTextSize)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .accessibilityElement(children: .combine)
    }
}
