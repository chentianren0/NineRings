import SwiftUI

/// The welcome page, in the form of the system's own: the title, three points each with a symbol, and one button.
/// It is shown once, on first launch; after Continue it does not come back.
struct WelcomeSheet: View {
    let onContinue: () -> Void

    @ScaledMetric(relativeTo: .title) private var symbolWidth = 44

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // The Mac's text does not grow, so the sheet fits its content.
            content
            #else
            // Larger text can make the points taller than the screen.
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
            #endif
            Button(action: onContinue) {
                Text("welcome.continue", tableName: "Screens")
                    .frame(maxWidth: Self.buttonWidth)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private var content: some View {
        VStack(spacing: 40) {
            Text("welcome.title", tableName: "Screens")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 28) {
                point(
                    Self.moveSymbol,
                    title: LocalizedStringResource("welcome.move.title", table: "Screens"),
                    detail: LocalizedStringResource("welcome.move.detail", table: "Screens")
                )
                point(
                    "text.bubble",
                    title: LocalizedStringResource("welcome.why.title", table: "Screens"),
                    detail: LocalizedStringResource("welcome.why.detail", table: "Screens")
                )
                point(
                    "book",
                    title: LocalizedStringResource("welcome.learn.title", table: "Screens"),
                    detail: LocalizedStringResource("welcome.learn.detail", table: "Screens")
                )
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
    }

    /// One point. Its words come with their table named, so that Xcode files them in the screens' catalog.
    private func point(_ symbol: String, title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// A finger tapping on iPhone and iPad; a pointer clicking on the Mac.
    private static var moveSymbol: String {
        #if os(macOS)
        "cursorarrow.click"
        #else
        "hand.tap"
        #endif
    }

    private static var bottomPadding: CGFloat {
        #if os(macOS)
        32
        #else
        24
        #endif
    }

    private static var topPadding: CGFloat {
        #if os(macOS)
        40
        #else
        64
        #endif
    }

    /// The button fills the sheet's width on iPhone and iPad, as the system's welcome pages do; on the Mac it is a
    /// wide button, not a bar.
    private static var buttonWidth: CGFloat {
        #if os(macOS)
        240
        #else
        .infinity
        #endif
    }
}

/// Where the screens around the toy are kept as settings.
enum ScreenKey {
    /// Whether the welcome page has been closed with Continue.
    static let welcomeSeen = "welcome.seen"
    /// Whether the app makes sounds. The sound code reads this key.
    static let sounds = "settings.sounds"
    /// Whether the app makes haptics. The haptics code reads this key.
    static let haptics = "settings.haptics"
}

extension View {
    /// Shows the welcome page over this view on first launch, until it is closed with Continue. In a debug build on
    /// the Mac, it also applies the launch options for screenshots (see ``ScreenLaunchOptions``).
    func welcomeOnFirstLaunch() -> some View {
        modifier(WelcomeOnFirstLaunch())
    }
}

private struct WelcomeOnFirstLaunch: ViewModifier {
    @AppStorage(ScreenKey.welcomeSeen) private var welcomeSeen = false
    #if DEBUG && os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { !welcomeSeen }, set: { if !$0 { welcomeSeen = true } })) {
                WelcomeSheet { welcomeSeen = true }
            }
            #if DEBUG && os(macOS)
            .task {
                ScreenLaunchOptions.applyToApp()
                if ScreenLaunchOptions.opensSettings { openSettings() }
            }
            #endif
    }
}
