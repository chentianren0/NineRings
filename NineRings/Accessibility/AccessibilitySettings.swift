import SwiftUI

extension EnvironmentValues {
    /// Whether to keep motion down: the system's Reduce Motion, or `-reduce-motion` in a debug build.
    @Entry var reducesMotion = false
    /// Whether to tell nothing by colour alone: the system's Differentiate Without Color, or
    /// `-differentiate-without-color` in a debug build.
    @Entry var differentiatesWithoutColor = false
    /// Whether to draw with more contrast: the system's Increase Contrast, or `-increase-contrast` in a debug build.
    @Entry var increasesContrast = false
}

extension View {
    /// Reads the system's accessibility settings into the app's own environment values (`reducesMotion` and the
    /// like), which the views read instead, so that a debug build can force a setting for its own process alone.
    func accessibilitySettings() -> some View {
        modifier(AccessibilitySettings())
    }
}

private struct AccessibilitySettings: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .environment(\.reducesMotion, reduceMotion || AccessibilityLaunchOptions.reducesMotion)
            .environment(\.differentiatesWithoutColor, differentiateWithoutColor || AccessibilityLaunchOptions.differentiatesWithoutColor)
            .environment(\.increasesContrast, contrast == .increased || AccessibilityLaunchOptions.increasesContrast)
            .debugOverrides()
    }
}

extension View {
    /// The debug build's forced settings, when a launch option asks for one (see ``AccessibilityLaunchOptions``).
    @ViewBuilder
    fileprivate func debugOverrides() -> some View {
        #if DEBUG
        if AccessibilityLaunchOptions.hasOverrides {
            modifier(AccessibilityLaunchOptions.Overrides())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension View {
    /// The transition for something that appears over the toy: it blurs in, or with Reduce Motion fades in.
    @ViewBuilder
    func appearingOverToy(reducesMotion: Bool) -> some View {
        if reducesMotion {
            transition(.opacity)
        } else {
            transition(.blurReplace)
        }
    }
}

extension View {
    /// Text that supports other text: quieter than it, with the contrast Apple asks for. The primary colour at 75%
    /// measures about 8:1 on the app's backgrounds in light and dark, where the system's secondary colour measured 3.5:1;
    /// with Increase Contrast it is the primary colour itself.
    func supportingTextStyle() -> some View {
        modifier(SupportingTextStyle())
    }
}

private struct SupportingTextStyle: ViewModifier {
    @Environment(\.increasesContrast) private var increasesContrast

    func body(content: Content) -> some View {
        content.foregroundStyle(increasesContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.75)))
    }
}
