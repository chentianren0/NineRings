import SwiftUI

/// The welcome page, in the form of the system's own: the title, three points each with a symbol, and two ways in.
/// The lesson is the suggested one, the first button and the default; the second starts playing, so nobody has to
/// watch it. It is shown once, on first launch; after either button it does not come back.
struct WelcomeSheet: View {
    /// What the person chose.
    enum Choice {
        case lesson
        case play
    }

    let onChoice: (Choice) -> Void

    @ScaledMetric(relativeTo: .title) private var symbolWidth = 44
    #if os(iOS)
    /// A phone held sideways is short: the page tightens so that its three points and Continue fit.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isShort: Bool { verticalSizeClass == .compact }
    #else
    private let isShort = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // The Mac's text does not grow, so the sheet fits its content.
            content
            #else
            // Larger text can make the points taller than the screen.
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                // Where the points do not all fit, as with larger text, show at once that there is more.
                .scrollIndicatorsFlash(onAppear: true)
            #endif
            buttons
                .controlSize(.extraLarge)
                .padding(.horizontal, 40)
                .padding(.bottom, isShort ? 8 : 24)
                .padding(.top, 8)
        }
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    /// The two ways in. On iPhone and iPad they stand one above the other, the lesson first, as the system's welcome
    /// pages do; on the Mac they sit side by side at the trailing end of the row, the default last, as in a Mac sheet.
    @ViewBuilder
    private var buttons: some View {
        #if os(macOS)
        HStack(spacing: 12) {
            playButton
            lessonButton
        }
        .fixedSize()
        #else
        VStack(spacing: isShort ? 4 : 8) {
            lessonButton
            playButton
        }
        #endif
    }

    private var lessonButton: some View {
        Button {
            onChoice(.lesson)
        } label: {
            Text("welcome.startLesson", tableName: "Screens")
                .frame(maxWidth: Self.buttonWidth)
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
    }

    private var playButton: some View {
        Button {
            onChoice(.play)
        } label: {
            Text("welcome.startPlaying", tableName: "Screens")
                .frame(maxWidth: Self.buttonWidth)
        }
        .buttonStyle(.glass)
        .keyboardShortcut(.cancelAction)
    }

    private var content: some View {
        VStack(spacing: isShort ? 16 : 40) {
            Text("welcome.title", tableName: "Screens")
                .font(isShort ? .title.bold() : .largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: isShort ? 14 : 28) {
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
        .padding(.top, isShort ? 20 : Self.topPadding)
        .padding(.bottom, isShort ? 8 : Self.bottomPadding)
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
                    .supportingTextStyle()
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

    /// The buttons fill the sheet's width on iPhone and iPad, as the system's welcome pages do; on the Mac they are two
    /// wide buttons of one width, not bars.
    private static var buttonWidth: CGFloat {
        #if os(macOS)
        180
        #else
        .infinity
        #endif
    }
}

/// Where the screens around the toy are kept as settings.
enum ScreenKey {
    /// Whether the welcome page has been closed, by either of its buttons.
    static let welcomeSeen = "welcome.seen"
    /// Whether the app makes sounds. The sound code reads this key.
    static let sounds = "settings.sounds"
    /// Whether the app makes haptics. The haptics code reads this key.
    static let haptics = "settings.haptics"
}

extension View {
    /// Shows the welcome page over this view on first launch, until one of its buttons closes it. Where the person
    /// chose the lesson, `openLesson` is called once the page has gone, so that on a phone, where the lesson is a sheet
    /// too, it can be presented. In a debug build on the Mac, it also applies the launch options for screenshots (see
    /// ``ScreenLaunchOptions``).
    func welcomeOnFirstLaunch(openLesson: @escaping () -> Void) -> some View {
        modifier(WelcomeOnFirstLaunch(openLesson: openLesson))
    }
}

private struct WelcomeOnFirstLaunch: ViewModifier {
    let openLesson: () -> Void
    @AppStorage(ScreenKey.welcomeSeen) private var welcomeSeen = false
    /// The person's choice, kept until the page has gone.
    @State private var choice: WelcomeSheet.Choice?
    /// Whether the page has been closed in this run. The setting says so too, but a launch argument such as
    /// `-welcome.seen NO`, used to see the page again, outranks what is stored, and the page would never go.
    @State private var closed = false
    #if DEBUG && os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    #endif

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { !welcomeSeen && !closed }, set: { if !$0 { close() } }), onDismiss: {
                if choice == .lesson { openLesson() }
                choice = nil
            }) {
                WelcomeSheet { chosen in
                    choice = chosen
                    close()
                }
            }
            #if DEBUG && os(macOS)
            .task {
                ScreenLaunchOptions.applyToApp()
                if ScreenLaunchOptions.opensSettings { openSettings() }
                if ScreenLaunchOptions.opensHistory { openWindow(id: HistoryWindow.id) }
            }
            #endif
    }

    private func close() {
        closed = true
        welcomeSeen = true
    }
}
