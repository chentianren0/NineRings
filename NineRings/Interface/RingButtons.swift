import Session
import SwiftUI

/// Nine buttons, ring 1 on the left, on the tip's side as the toy is first seen. A filled disc is a ring that is
/// on, an outline one that is off; a short bar under it marks a ring that can move now; an orange outline marks the
/// ring in the way of the ring just refused. Pressing one, or its number key, asks to move its ring. The numbers and
/// outlines meet the contrast Apple asks for: the off rings' in the primary colour, the on rings' bold.
///
/// Nothing is told by colour alone: on and off are filled and outlined, and with Differentiate Without Color the ring
/// in the way also wears the raised hand the refusal shows. VoiceOver hears the same: "Ring 3, on, can come off", with
/// "in the way of ring 5" or "moving" after it.
///
/// While the person sets the rings by hand, each button is a switch for its ring: pressing it puts the ring on or takes
/// it off at once, with no rule, so the bar that marks a ring that can move goes, and VoiceOver hears a switch: "Ring 3,
/// on".
///
/// The row always runs left to right, even in a right-to-left language, because it mirrors the toy, which does not
/// turn round.
struct RingButtons: View {
    let markers: [PuzzleSession.Marker]
    /// The largest a button's disc grows to, in points; it shrinks when the row is narrower.
    var diameter: CGFloat = 40
    /// Whether the rings are being set by hand.
    var settingRings = false
    let tap: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(markers) { marker in
                RingButton(marker: marker, refused: refused, diameter: diameter, settingRings: settingRings) { tap(marker.ring) }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(ScreenMotion.small, value: markers)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Rings", comment: "Spoken name of the row of nine ring buttons."))
    }

    /// The ring just asked for that the rule refused, if any.
    private var refused: Int? { markers.first { $0.isRefused }?.ring }
}

private struct RingButton: View {
    let marker: PuzzleSession.Marker
    let refused: Int?
    let diameter: CGFloat
    let settingRings: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    @Environment(\.reducesMotion) private var reducesMotion
    @Environment(\.differentiatesWithoutColor) private var differentiatesWithoutColor
    @Environment(\.increasesContrast) private var increasesContrast
    @Environment(\.colorScheme) private var colorScheme

    /// The disc of a ring that is on: the tint darkened, so that its white number reads. On iPhone the tint over the
    /// glass measured #009DFF, 2.9:1 with white, and with Increase Contrast in dark a light blue, 1.9:1; darkened by
    /// 30% they measure about 5.6:1 and 3.9:1. The bar that marks a ring that can move takes it in light, where the tint
    /// itself measured 2.9:1 against the panel, and the tint in dark, where the tint is the lighter of the two.
    private static let onFill = Color.accentColor.mix(with: .black, by: 0.3)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(marker.isOn ? AnyShapeStyle(Self.onFill) : AnyShapeStyle(.clear))
                    Circle()
                        .strokeBorder(outline, lineWidth: marker.isBlocking ? 3 : 2)
                    Text(marker.ring, format: .number)
                        .font(.system(numberStyle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        // The disc does not grow with the text: at the largest sizes the number shrinks to fit, and
                        // the Large Content Viewer shows it.
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(2)
                        .foregroundStyle(marker.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: diameter)
                .overlay(alignment: .topTrailing) {
                    if marker.isBlocking && differentiatesWithoutColor {
                        Image(systemName: "hand.raised.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                            .font(.system(size: diameter * 0.4))
                            .offset(x: diameter * 0.12, y: -diameter * 0.12)
                            // A mark sized to the disc, not text: VoiceOver hears "in the way" in the button's value.
                            .accessibilityHidden(true)
                    }
                }
                .scaleEffect(marker.isMoving && !reducesMotion ? 1.12 : 1)
                Capsule()
                    .fill(colorScheme == .dark ? AnyShapeStyle(.tint) : AnyShapeStyle(Self.onFill))
                    .frame(width: 12, height: 3)
                    .opacity(marker.canMove && !settingRings ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
            // A plain button keeps its colours when it is disabled; fade it, as the system's buttons fade.
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(String(marker.ring))), modifiers: [])
        .help(tooltip)
        .accessibilityLabel(Text("Ring \(marker.ring)", comment: "Spoken name of a ring button. The variable is the ring's number."))
        .accessibilityValue(spokenValue)
        .accessibilityHint(settingRings ? Text(verbatim: "") : marker.block.map { Text(Sentences.shortReason($0)) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(settingRings ? .isToggle : [])
        #if os(iOS)
        .accessibilityShowsLargeContentViewer {
            Text(marker.ring, format: .number)
        }
        #endif
    }

    private var tooltip: Text {
        guard settingRings else {
            return Text("Move ring \(marker.ring)", comment: "Tooltip on a ring button. The variable is the ring's number.")
        }
        return marker.isOn
            ? Text("Take ring \(marker.ring) off", comment: "Tooltip on a ring button while the rings are set by hand: a click takes the ring off at once. The variable is the ring's number.")
            : Text("Put ring \(marker.ring) on", comment: "Tooltip on a ring button while the rings are set by hand: a click puts the ring on at once. The variable is the ring's number.")
    }

    private var outline: AnyShapeStyle {
        if marker.isBlocking { return AnyShapeStyle(.orange) }
        return marker.isOn ? AnyShapeStyle(Self.onFill) : offStyle
    }

    /// The outline of a ring that is off: the primary colour softened, about 5:1 against the panel in light and dark,
    /// or the primary colour itself with Increase Contrast. (The secondary colour gave 2.5:1 on the light panel.)
    private var offStyle: AnyShapeStyle {
        increasesContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.6))
    }

    /// The number's text style. White on the tint measures about 3.2:1, which suffices for large text only (bold, 14 pt
    /// and up), so the number is bold, and on the Mac, where the callout style is 12 pt, a size larger.
    private var numberStyle: Font.TextStyle {
        #if os(macOS)
        .title3
        #else
        diameter > 44 ? .title3 : .callout
        #endif
    }

    /// Whether the ring is on and can move, with a note after it when it is moving or in the way.
    private var spokenValue: Text {
        let note: String? = if marker.isMoving {
            String(localized: "ring.moving", table: "Accessibility")
        } else if marker.isBlocking, let refused {
            String(localized: "ring.inTheWay \(refused)", table: "Accessibility")
        } else {
            nil
        }
        guard let note else { return state }
        return Text("ring.valueWithNote \(String(localized: stateResource)) \(note)", tableName: "Accessibility")
    }

    private var state: Text { Text(stateResource) }

    private var stateResource: LocalizedStringResource {
        switch (marker.isOn, marker.canMove && !settingRings) {
        case (true, true): LocalizedStringResource("On, can come off", comment: "Spoken value of a ring button: the ring is on and can come off now.")
        case (true, false): LocalizedStringResource("On", comment: "Spoken value of a ring button: the ring is on and cannot move now.")
        case (false, true): LocalizedStringResource("Off, can go on", comment: "Spoken value of a ring button: the ring is off and can go on now.")
        case (false, false): LocalizedStringResource("Off", comment: "Spoken value of a ring button: the ring is off and cannot move now.")
        }
    }
}
