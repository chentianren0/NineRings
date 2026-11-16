import Motion
import SwiftUI

/// The controls for the move: play or pause, the speed, the stage the move is in, and a scrubber with the
/// stages marked and named.
///
/// Everything here follows the width it is given: the top row stacks when it is narrow, and the stage names
/// give way to stage numbers when they no longer fit their stretches of the scrubber.
struct PlayerControls: View {
    @Bindable var player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    playButton
                    stageTitle
                    Spacer(minLength: 0)
                    speedPicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        playButton
                        Spacer(minLength: 0)
                        speedPicker
                    }
                    stageTitle
                }
            }
            StageScrubber(progress: $player.progress, stages: player.motion.stages) {
                player.pause()
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var playButton: some View {
        Button {
            player.togglePlay()
        } label: {
            Label(player.nextAction, systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                .frame(minWidth: 150, alignment: .leading)
        }
        .keyboardShortcut(.space, modifiers: [])
        .help("Play the move, or pause it (Space)")
        .fixedSize()
    }

    private var stageTitle: some View {
        Text(player.stageName)
            .font(.headline)
            .contentTransition(.opacity)
            .lineLimit(1)
    }

    private var speedPicker: some View {
        Picker("Speed", selection: $player.speed) {
            ForEach(PlaybackSpeed.allCases) { speed in
                Text(speed.title).tag(speed)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Playing speed")
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
            ViewThatFits(in: .horizontal) {
                StageLabels(spans: spans) {
                    ForEach(stages, id: \.name) { stage in
                        Text(stage.name)
                    }
                }
                StageLabels(spans: spans) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        // The thumb's middle travels the whole width; the thumb itself may overhang the ends.
        .padding(.horizontal, Self.thumbRadius)
        .accessibilityRepresentation {
            Slider(value: $progress, in: 0...1) {
                Text("Progress")
            }
        }
    }

    private var spans: [ClosedRange<Double>] {
        stages.map { $0.start...$0.end }
    }

    private var track: some View {
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
        .frame(height: 2 * Self.thumbRadius)
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
