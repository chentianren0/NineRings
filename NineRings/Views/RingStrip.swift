import Puzzle
import Session
import SwiftUI

/// Nine markers, ring 1 on the left, on the tip's side as the toy is first seen. A filled disc is a ring that is
/// on, an outline one that is off; a bar under the number marks a ring that can move now. Tapping a marker asks to
/// move its ring.
///
/// The strip always runs left to right, even in a right-to-left language, because it mirrors the toy, which
/// does not turn round.
struct RingStrip: View {
    let markers: [PuzzleSession.Marker]
    let tap: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(markers) { marker in
                RingMarker(marker: marker) {
                    tap(marker.ring)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.snappy(duration: 0.25), value: markers)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Rings", comment: "Spoken name of the strip of nine ring markers."))
    }
}

/// One ring's marker.
private struct RingMarker: View {
    let marker: PuzzleSession.Marker
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledDiscSize: CGFloat = 22

    /// The disc grows with the text size, but only so far: nine markers must still fit across a narrow window.
    private var discSize: CGFloat { min(scaledDiscSize, 28) }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                disc
                    .frame(width: discSize, height: discSize)
                    .padding(5)
                Text(marker.ring, format: .number)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(marker.isBlocking ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                movable
            }
            .frame(minWidth: 28, maxWidth: 52, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(String(marker.ring))), modifiers: [])
        .help(Text("Move ring \(marker.ring) (\(marker.ring))", comment: "Tooltip on a ring marker. Both variables are the ring's number; the second is the key that moves it."))
        .accessibilityLabel(Text("Ring \(marker.ring)", comment: "Spoken name of a ring marker. The variable is the ring's number."))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text("Asks to move this ring.", comment: "Spoken hint on a ring marker."))
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(marker.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            Circle()
                .strokeBorder(marker.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary), lineWidth: 1.5)
            if marker.isMoving {
                Circle()
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .padding(-5)
            }
            if marker.isBlocking {
                Circle()
                    .strokeBorder(.orange, lineWidth: 3)
                    .padding(-5)
            }
            if marker.isRefused {
                Circle()
                    .strokeBorder(.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    .padding(-5)
            }
        }
    }

    /// A short bar for a ring that can move now.
    private var movable: some View {
        Capsule()
            .fill(marker.canMove ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            .frame(width: discSize * 0.8, height: 4)
    }

    private var value: LocalizedStringResource {
        switch (marker.isOn, marker.block) {
        case (true, nil):
            LocalizedStringResource("On, can move", comment: "Spoken value of a ring marker.")
        case (false, nil):
            LocalizedStringResource("Off, can move", comment: "Spoken value of a ring marker.")
        case (true, let block?):
            LocalizedStringResource("On, \(Sentences.shortReason(block))", comment: "Spoken value of a ring marker that is on and cannot move. The variable says why.")
        case (false, let block?):
            LocalizedStringResource("Off, \(Sentences.shortReason(block))", comment: "Spoken value of a ring marker that is off and cannot move. The variable says why.")
        }
    }
}
