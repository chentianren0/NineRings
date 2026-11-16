import Session
import SwiftUI

/// Nine buttons, ring 1 on the left, on the tip's side as the toy is first seen. A filled disc is a ring that is
/// on, an outline one that is off; a short bar under it marks a ring that can move now; an orange outline marks the
/// ring in the way of the ring just refused. Pressing one, or its number key, asks to move its ring.
///
/// The row always runs left to right, even in a right-to-left language, because it mirrors the toy, which does not
/// turn round.
struct RingButtons: View {
    let markers: [PuzzleSession.Marker]
    let tap: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(markers) { marker in
                RingButton(marker: marker) { tap(marker.ring) }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(.snappy(duration: 0.25), value: markers)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Rings", comment: "Spoken name of the row of nine ring buttons."))
    }
}

private struct RingButton: View {
    let marker: PuzzleSession.Marker
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(marker.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    Circle()
                        .strokeBorder(outline, lineWidth: marker.isBlocking ? 3 : 2)
                    Text(marker.ring, format: .number)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(marker.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 40)
                .scaleEffect(marker.isMoving ? 1.12 : 1)
                Capsule()
                    .fill(.tint)
                    .frame(width: 12, height: 3)
                    .opacity(marker.canMove ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(String(marker.ring))), modifiers: [])
        .help(Text("Move ring \(marker.ring)", comment: "Tooltip on a ring button. The variable is the ring's number."))
        .accessibilityLabel(Text("Ring \(marker.ring)", comment: "Spoken name of a ring button. The variable is the ring's number."))
        .accessibilityValue(spokenValue)
        .accessibilityHint(marker.block.map { Text(Sentences.shortReason($0)) } ?? Text(verbatim: ""))
    }

    private var outline: AnyShapeStyle {
        if marker.isBlocking { return AnyShapeStyle(.orange) }
        return marker.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    private var spokenValue: Text {
        switch (marker.isOn, marker.canMove) {
        case (true, true): Text("On, can come off", comment: "Spoken value of a ring button: the ring is on and can come off now.")
        case (true, false): Text("On", comment: "Spoken value of a ring button: the ring is on and cannot move now.")
        case (false, true): Text("Off, can go on", comment: "Spoken value of a ring button: the ring is off and can go on now.")
        case (false, false): Text("Off", comment: "Spoken value of a ring button: the ring is off and cannot move now.")
        }
    }
}
