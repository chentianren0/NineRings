import Motion
import SwiftUI

/// Everything under or beside the toy: the line that says what is happening, the ring markers, the slider with
/// the stages of the move playing or played last, and the buttons.
///
/// It follows the width it is given, never the device: the buttons lose their titles, then wrap onto a second
/// row, as the width shrinks, and the stage names give way to stage numbers.
struct PlayerControls: View {
    @Bindable var player: Player
    /// Covers the toy, returns every ring to on, and uncovers it.
    let reset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusLine(status: player.status)
            RingStrip(markers: player.markers) { ring in
                player.tap(ring)
            }
            .frame(maxWidth: .infinity)
            StageScrubber(progress: $player.progress, stages: player.stages) {
                player.pause()
            }
            .disabled(!player.hasMove)
            .opacity(player.hasMove ? 1 : 0.4)
            ControlButtons(player: player, reset: reset)
        }
    }
}

/// Play or pause, the speed, undo, reset and solve, and the count of moves made.
private struct ControlButtons: View {
    @Bindable var player: Player
    let reset: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                buttons
                Spacer(minLength: 0)
                count
            }
            HStack(spacing: 10) {
                buttons
                    .labelStyle(.iconOnly)
                Spacer(minLength: 0)
                count
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    buttons
                        .labelStyle(.iconOnly)
                }
                count
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    playButtons
                }
                HStack(spacing: 10) {
                    changeButtons
                    Spacer(minLength: 0)
                    count
                }
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var buttons: some View {
        playButtons
        changeButtons
    }

    /// Play or pause, and the speed.
    @ViewBuilder
    private var playButtons: some View {
        Button {
            player.togglePlay()
        } label: {
            if player.isPlaying {
                Label { Text("Pause", comment: "Button that stops the move playing.") } icon: { Image(systemName: "pause.fill") }
            } else {
                Label { Text("Play", comment: "Button that plays the move on the slider forward.") } icon: { Image(systemName: "play.fill") }
            }
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!player.isPlaying && !player.canPlay)
        .help(Text("Play the move forward, or pause it (Space)", comment: "Tooltip on the play button."))

        Picker(selection: $player.speed) {
            ForEach(PlaybackSpeed.allCases) { speed in
                Text(speed.title).tag(speed)
            }
        } label: {
            Label { Text("Speed", comment: "Menu that chooses how fast moves play.") } icon: { Image(systemName: "gauge.with.dots.needle.33percent") }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(Text("Playing speed", comment: "Tooltip on the speed menu."))
        // Without this the menu itself has no spoken name: the label is a separate image beside it.
        .accessibilityLabel(Text("Speed", comment: "Menu that chooses how fast moves play."))
    }

    /// Undo, reset and solve.
    @ViewBuilder
    private var changeButtons: some View {
        Button {
            player.undo()
        } label: {
            Label { Text("Undo", comment: "Button that plays the last move backwards.") } icon: { Image(systemName: "arrow.uturn.backward") }
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!player.canUndo)
        .help(Text("Play the last move backwards (⌘Z)", comment: "Tooltip on the undo button."))

        Button(action: reset) {
            Label { Text("Reset", comment: "Button that returns every ring to on.") } icon: { Image(systemName: "arrow.counterclockwise") }
        }
        .disabled(player.moveCount == 0 && !player.hasMove)
        .help(Text("Put every ring back on", comment: "Tooltip on the reset button."))

        Button {
            player.solve()
        } label: {
            Label { Text("Solve", comment: "Button that plays the shortest way to every ring off.") } icon: { Image(systemName: "flag.checkered") }
        }
        .disabled(!player.canSolve)
        .help(Text("Play the shortest way to every ring off", comment: "Tooltip on the solve button."))
    }

    private var count: some View {
        Text("Moves: \(player.moveCount)", comment: "How many moves have been made since the start. The variable is the count.")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

/// A scrubber for the progress of a move: a track with a mark where each stage begins, a thumb to drag, and
/// the stages' names under their stretches of the track.
struct StageScrubber: View {
    @Binding var progress: Double
    let stages: [Stage]
    /// Called when a drag begins, so that playing can stop.
    var onDragStart: () -> Void

    @State private var width: CGFloat = 0
    @State private var isDragging = false

    private static let thumbRadius: CGFloat = 9

    var body: some View {
        VStack(spacing: 6) {
            track
            if stages.isEmpty {
                // Holds the labels' place, so that the controls keep their height when the first move begins.
                Text("No move yet", comment: "Under the slider, before any move has been played.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                labels
            }
        }
        // The thumb's middle travels the whole width; the thumb itself may overhang the ends.
        .padding(.horizontal, Self.thumbRadius)
        .accessibilityRepresentation {
            Slider(value: $progress, in: 0...1) {
                Text("Progress", comment: "Spoken name of the slider that runs through the move.")
            }
        }
    }

    private var labels: some View {
        ViewThatFits(in: .horizontal) {
            StageLabels(spans: spans) {
                ForEach(stages, id: \.name) { stage in
                    Text(Sentences.stageName(stage))
                }
            }
            StageLabels(spans: spans) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, _ in
                    Text(index + 1, format: .number)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var spans: [ClosedRange<Double>] {
        stages.map { $0.start...$0.end }
    }

    private var track: some View {
        // The track's size comes from this flexible base alone. What is drawn on it is placed from the measured
        // width, and if it set the size too, the width could never shrink below the last one measured.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 2 * Self.thumbRadius)
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 6)
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(0, width * progress), height: 6)
                    ForEach(stages.dropFirst(), id: \.name) { stage in
                        Rectangle()
                            .fill(.secondary)
                            .frame(width: 1.5, height: 16)
                            .offset(x: width * stage.start - 0.75)
                    }
                    Circle()
                        .fill(.background)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .overlay(Circle().strokeBorder(.tint, lineWidth: 2))
                        .frame(width: 2 * Self.thumbRadius, height: 2 * Self.thumbRadius)
                        .offset(x: width * progress - Self.thumbRadius)
                }
            }
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !isDragging {
                        isDragging = true
                        onDragStart()
                    }
                    guard width > 0 else { return }
                    progress = min(max(drag.location.x / width, 0), 1)
                }
                .onEnded { _ in isDragging = false }
        )
    }
}

/// Lays out one label per stage, each centred under its stretch of the track. Its ideal width is the width at
/// which every label fits within its own stretch, so that `ViewThatFits` can choose shorter labels when narrow.
private struct StageLabels: SwiftUI.Layout {
    let spans: [ClosedRange<Double>]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let needed = zip(sizes, spans).map { size, span in
            (size.width + 8) / max(span.upperBound - span.lowerBound, 0.01)
        }.max() ?? 0
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: proposal.width ?? needed, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, span) in zip(subviews, spans) {
            let size = subview.sizeThatFits(.unspecified)
            let middle = bounds.minX + bounds.width * (span.lowerBound + span.upperBound) / 2
            let x = min(max(middle - size.width / 2, bounds.minX), bounds.maxX - size.width)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
        }
    }
}
