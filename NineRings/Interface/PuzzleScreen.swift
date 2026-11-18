import Session
import SwiftUI

/// The puzzle: the toy filling the window with the controls floating over it, and the toolbar.
///
/// The controls and the toy are an overlay arrangement, so that on a half-folded iPhone Duo the system puts the toy
/// on one half and the controls on the other. On a wide screen the room goes to the toy, and the lesson opens beside
/// it, as an inspector, rather than over it.
struct PuzzleScreen: View {
    let player: Player
    let rig: CameraRig

    @State private var showsLesson = LessonLaunchOptions.opensAtLaunch
    /// Whether the screen has appeared, after which the lesson opens only when asked.
    @State private var hasAppeared = false
    /// When the inspector's binding last set the lesson closed, to tell the system presenting it again from opening it.
    @State private var inspectorClosedAt: ContinuousClock.Instant?
    // In a debug build, `-open-settings` and `-about-panel` open these sheets at launch on iPhone and iPad too, to see
    // them, as they open the Settings window and the About panel on the Mac.
    @State private var showsSettings = ScreenLaunchOptions.opensSettings
    @State private var showsAbout = ScreenLaunchOptions.opensAbout
    /// How much of the toy a plain cover hides, while the toy jumps to another state.
    @State private var cover = 0.0
    /// Where the floating controls are, in the global coordinate space, so that the toy is framed clear of them.
    @State private var panelFrame: CGRect = .null
    /// Where the lesson's panel is, in the global coordinate space: a column beside the toy on a wide screen, a sheet
    /// over the bottom of the toy on a phone.
    @State private var lessonFrame: CGRect = .null
    /// Whether the controls have a half of their own, as on a half-folded iPhone Duo.
    @State private var isHalfFolded = false
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The window's size: a half-folded Duo is held with the fold across, as a laptop, when the window is taller than
    /// wide.
    @State private var windowSize: CGSize = .zero
    /// How high the lesson's sheet stands on a phone.
    @State private var lessonDetent: PresentationDetent = Self.halfDetent
    /// The lesson's sheet on a phone stops half way up, and never lower than about 400 points, where the screen allows,
    /// so that on a small screen, such as the closed iPhone Duo's, the step's text has room.
    private static let halfDetent = PresentationDetent.custom(LessonSheetDetent.self)
    #endif

    var body: some View {
        NavigationStack {
            ArrangementView {
                Controls(player: player, panelFrame: $panelFrame, hasOwnHalf: $isHalfFolded, lessonSheet: lessonSheet,
                         stepsAside: controlsStepAside) {
                    jump { player.reset() }
                }
                .accessibilitySortPriority(1)
            } secondary: {
                // VoiceOver meets the toy first, then the controls.
                ToyCanvas(player: player, rig: rig, covers: [panelFrame, lessonFrame]) { player.tap($0) }
                    .accessibilitySortPriority(2)
                    .overlay {
                        Backdrop.color(for: colorScheme)
                            .opacity(cover)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
            .arrangementViewStyle(.overlay)
            .puzzleCommands(PuzzleActions(player: player, rig: rig, showsLesson: $showsLesson, lesson: lesson,
                                          reset: { jump { player.reset() } }, settingRings: settingRings))
            .navigationTitle(Text("Nine Rings", comment: "The window's title."))
            .toolbar(removing: .title)
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            // Only the person opens the lesson (the toolbar's button, the menu bar, Help). The inspector's own binding
            // closes it, as a swipe down closes the sheet. It may set it open only straight after setting it closed,
            // which is the system presenting it again in another form, as when a half-folded Duo turns the column
            // into a sheet; a binding that opens it by itself, as the system restoring an inspector's state from the
            // last run would, is refused.
            .inspector(isPresented: Binding(get: { showsLesson }, set: { presented in
                if presented {
                    if let closed = inspectorClosedAt, closed.duration(to: .now) < .seconds(1) { showsLesson = true }
                    inspectorClosedAt = nil
                } else {
                    inspectorClosedAt = .now
                    showsLesson = false
                }
            })) {
                LessonPanel(player: player, guide: lesson) { showsLesson = false }
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
                    #if os(iOS)
                    // On a phone the inspector is a sheet. It stops half way up, so that the toy the text speaks of
                    // stays in view above it and can still be turned and tapped; it can be pulled up to read.
                    .presentationDetents([tryingDetent, Self.halfDetent, .large], selection: $lessonDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: Self.halfDetent))
                    .presentationContentInteraction(.scrolls)
                    // When the last step gives the toy back to try, the sheet steps down to leave room for it.
                    .onChange(of: player.lessonHoldsToy, initial: true) { _, holds in
                        lessonDetent = holds ? Self.halfDetent : tryingDetent
                    }
                    #endif
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { lessonFrame = $0 }
                    .onDisappear { lessonFrame = .null }
            }
            #if os(macOS)
            // The window's least width: room for the toy, and with the lesson open, for the toy beside it (360 and the
            // lesson's least, 300), so that the lesson never covers the toy it is about.
            .frame(minWidth: showsLesson ? 660 : 360)
            #endif
            .onChange(of: showsLesson, initial: true) { _, shows in
                // The lesson never shows by default. The system restores an inspector's state from the last run, so a
                // lesson left open would come back at launch: until the screen has appeared, keep it closed, unless a
                // debug option asked for it.
                guard hasAppeared || !shows || LessonLaunchOptions.opensAtLaunch else {
                    showsLesson = false
                    return
                }
                if shows { lesson.open() } else { lesson.close() }
            }
            .onAppear { hasAppeared = true }
            .welcomeOnFirstLaunch { showsLesson = true }
            // The toy is the lesson's only while its panel is open. Should the panel go without closing the lesson, as
            // when it goes in the middle of the cover's change, the toy comes back to the person at once.
            .onChange(of: player.lessonPage != nil) { _, inLesson in
                if inLesson, !showsLesson { lesson.closeNow() }
            }
            #if os(iOS)
            // Settings hold little: on a phone the sheet stops at half height. About, with its text and links, is a
            // full sheet. On an iPad each is the system's form sheet.
            .sheet(isPresented: $showsSettings) {
                NavigationStack { SettingsScreen() }
                    .presentationDetents(lessonHasColumn ? [.large] : [.medium, .large])
            }
            .sheet(isPresented: $showsAbout) {
                NavigationStack { AboutScreen() }
            }
            #endif
        }
        #if os(iOS)
        // A phone held sideways is short but wide: there the lesson is a column beside the toy, as on an iPad, since a
        // sheet in a short window stands the whole height and would hide the toy the lesson speaks of.
        .environment(\.horizontalSizeClass, lessonHasColumn ? .regular : .compact)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        #endif
    }

    #if os(iOS)
    /// The sheet's height on the step that gives the toy back, low enough to leave room for the toy and its controls
    /// on a phone. (On a half-folded Duo the system sizes the sheet to the half below the fold itself.)
    private var tryingDetent: PresentationDetent { .height(300) }

    /// Whether the lesson is a column beside the toy rather than a sheet over it: on a wide screen, and on a phone held
    /// sideways. On a half-folded Duo held as a laptop, a column would run across the fold, so the lesson is a sheet,
    /// which the system keeps below the fold, under the toy.
    private var lessonHasColumn: Bool {
        if isHalfFolded, windowSize.height > windowSize.width { return false }
        return horizontalSizeClass == .regular || verticalSizeClass == .compact
    }
    #endif

    /// Whether the toy's controls step aside for the lesson: on a phone, while the lesson's steps show the toy, since
    /// its controls do nothing then and the toy needs the room. They come back when the last step gives the toy back.
    private var controlsStepAside: Bool {
        #if os(iOS)
        !lessonHasColumn && showsLesson && player.lessonHoldsToy
        #else
        false
        #endif
    }

    /// The lesson's panel when it is a sheet over the bottom of the toy, as on a phone; null when it is a column beside
    /// the toy, or closed.
    private var lessonSheet: CGRect {
        #if os(iOS)
        !lessonHasColumn && showsLesson ? lessonFrame : .null
        #else
        .null
        #endif
    }

    private var lesson: LessonGuide {
        LessonGuide(player: player, rig: rig, cover: jump, isWanted: { showsLesson })
    }

    /// Where the puzzle's toolbar items go: the trailing end, on every device.
    private static var trailing: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .primaryAction
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if DEBUG
        if !StoreCapture.isActive {
            ToolbarItem(placement: .navigation) {
                DesignMenu()
            }
        }
        #endif
        #if os(macOS)
        // With no title in the window's toolbar, items gather at the leading end unless something pushes them over.
        ToolbarSpacer(.flexible)
        #endif
        if player.isSettingRings {
            // Setting the rings is a mode, as editing is in Apple's apps: the toolbar offers only the way out, Cancel to
            // give the toy back as it was, Done to keep the rings as set, and the View menu, to see them from anywhere.
            ToolbarItem(placement: Self.trailing) {
                viewMenu
            }
            ToolbarSpacer(.fixed, placement: Self.trailing)
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    settingRings.cancel()
                }
                .keyboardShortcut(.cancelAction)
                .help(Text("Put the rings back as they were", comment: "Tooltip on the Cancel button while the rings are set by hand."))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    settingRings.finish()
                }
                .keyboardShortcut(.defaultAction)
                .help(Text("Keep the rings as set", comment: "Tooltip on the Done button while the rings are set by hand."))
            }
        } else {
            ToolbarItemGroup(placement: Self.trailing) {
                viewMenu
                Button {
                    settingRings.start()
                } label: {
                    Label { Text("Set Rings", comment: "Toolbar button that starts setting the rings by hand: each ring button then puts its ring on or takes it off at once.") } icon: { Image(systemName: "pencil") }
                }
                .disabled(showsLesson)
                .help(Text("Choose which rings are on", comment: "Tooltip on the Set Rings button."))
                Button {
                    jump { player.reset() }
                } label: {
                    Label { Text("Reset", comment: "Toolbar button that puts every ring back on.") } icon: { Image(systemName: "arrow.counterclockwise") }
                }
                .help(Text("Put every ring back on", comment: "Tooltip on the Reset button."))
            }
            ToolbarSpacer(.fixed, placement: Self.trailing)
            ToolbarItem(placement: Self.trailing) {
                Button {
                    showsLesson.toggle()
                } label: {
                    Label { Text("Lesson", comment: "Toolbar button that shows or hides the lesson on how the puzzle works.") } icon: { Image(systemName: "book") }
                }
                .accessibilityAddTraits(showsLesson ? .isSelected : [])
                .help(Text("Show how the puzzle works", comment: "Tooltip on the Lesson button."))
                .lessonTip(player: player, lessonShown: showsLesson)
            }
        }
        #if os(iOS)
        ToolbarOverflowMenu {
            Button {
                showsSettings = true
            } label: {
                Label { Text("Settings", comment: "Menu item that opens the app's settings.") } icon: { Image(systemName: "gear") }
            }
            Button {
                showsAbout = true
            } label: {
                Label { Text("menu.about", tableName: "Screens") } icon: { Image(systemName: "info.circle") }
            }
        }
        #endif
    }

    private var viewMenu: some View {
        Menu {
            Button {
                rig.showDefault()
            } label: {
                Text("Standard View", comment: "View menu item: back to the view the toy is first seen from.")
            }
            Divider()
            ForEach(CameraPreset.allCases) { preset in
                Button {
                    rig.show(preset, framing: Framing.rings)
                } label: {
                    Text(preset.viewMenuTitle)
                }
            }
        } label: {
            Label { Text("View", comment: "Toolbar menu of the places to see the toy from.") } icon: { Image(systemName: "cube") }
        }
    }

    /// Setting the rings by hand, with a cover over the toy where it jumps.
    private var settingRings: SettingRings {
        SettingRings(player: player, cover: jump)
    }

    /// Covers the toy, makes a change that moves it to another state at once, and uncovers it, so that the jump
    /// is calm.
    private func jump(_ change: @escaping () -> Void) {
        // Quietly: the jump says what the toy has become, and "Paused" would only come before it.
        player.pause(quiet: true)
        withAnimation(.easeIn(duration: 0.25)) {
            cover = 1
        } completion: {
            change()
            withAnimation(.easeOut(duration: 0.4)) { cover = 0 }
        }
    }
}

/// Starting, finishing and cancelling the setting of the rings, as the toolbar and the menu bar do them: where the toy
/// jumps, to rest from a move in hand or back to how it was, under the screen's cover.
struct SettingRings {
    let player: Player
    let cover: (@escaping () -> Void) -> Void

    func start() {
        guard !player.isSettingRings else { return }
        if player.settingRingsStartJumps {
            cover { player.startSettingRings() }
        } else {
            player.startSettingRings()
        }
    }

    func finish() {
        player.finishSettingRings()
    }

    func cancel() {
        if player.settingRingsCancelJumps {
            cover { player.cancelSettingRings() }
        } else {
            player.cancelSettingRings()
        }
    }
}

/// The places to see the toy from, as the toolbar's View menu and the menu bar's View menu name them.
extension CameraPreset {
    var viewMenuTitle: LocalizedStringResource {
        switch self {
        case .side: LocalizedStringResource("From the Side", comment: "View menu item: the toy seen from the side.")
        case .top: LocalizedStringResource("From Above", comment: "View menu item: the toy seen from above.")
        case .tip: LocalizedStringResource("From the Tip", comment: "View menu item: the toy seen end on, from the sword's tip.")
        }
    }

    var viewShortcut: KeyEquivalent {
        switch self {
        case .side: "1"
        case .top: "2"
        case .tip: "3"
        }
    }
}

/// The controls, floating at the bottom over the toy, or, when the arrangement gives them a half of the screen to
/// themselves on a half-folded iPhone Duo, filling it.
private struct Controls: View {
    let player: Player
    /// Where the floating panel is, in the global coordinate space, or null when the controls cover no part of the toy.
    @Binding var panelFrame: CGRect
    /// Set to whether the controls have a half of their own, for the screen to place the lesson.
    @Binding var hasOwnHalf: Bool
    /// The lesson's sheet over the bottom of the toy, in the global coordinate space, or null.
    let lessonSheet: CGRect
    /// Whether the controls step aside for the lesson.
    let stepsAside: Bool
    /// Puts every ring back on, from the congratulation.
    let putBack: () -> Void
    @Environment(\.overlayArrangementZIndex) private var zIndex
    @Environment(\.reducesMotion) private var reducesMotion

    /// The congratulation goes with the controls: over the top of the whole window where they float over the toy, and
    /// in the controls' own half above them on a half-folded Duo, clear of the fold and of the toy.
    var body: some View {
        content
            .congratulation(player, overlays: !hasOwnSpace, putBack: putBack)
            .onChange(of: hasOwnSpace, initial: true) { _, own in hasOwnHalf = own }
    }

    @ViewBuilder
    private var content: some View {
        if stepsAside {
            // While the lesson's steps show the toy, the lesson takes the controls' place, where it is a sheet; they
            // come back, above the sheet, when the last step gives the toy back.
            Color.clear
                .onAppear { panelFrame = .null }
        } else if hasOwnSpace {
            VStack(spacing: 20) {
                if player.isCongratulating {
                    CongratulationCard(player: player, putBack: putBack)
                        .transition(.blurReplace)
                }
                ControlPanel(player: player, style: .beside)
            }
            .animation(.smooth(duration: 0.4), value: player.isCongratulating)
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .padding(.top, lessonSheet.isNull ? 0 : 12)
            // Above the lesson's sheet, where it shares the half.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: lessonSheet.isNull ? .center : .top)
            .onAppear { panelFrame = .null }
        } else {
            // The space is read from a geometry reader, which does not grow with the panel lifted inside it.
            GeometryReader { space in
                floatingPanel(lift: sheetOverlap(over: space.frame(in: .global)))
            }
        }
    }

    /// Whether the controls sit beside the toy rather than over it: the arrangement puts them over the toy, at a
    /// z-index above it, except on a half-folded Duo, where each view has its own half and the z-index is 0.
    private var hasOwnSpace: Bool {
        zIndex == 0
    }

    /// How far the lesson's sheet reaches up over the controls' space, so that the panel can float above it, as
    /// floating controls ride above a sheet in Apple's own apps. Never more than most of the space: a sheet pulled up
    /// to the top covers the panel, as it covers the toy.
    private func sheetOverlap(over space: CGRect) -> CGFloat {
        guard !lessonSheet.isNull else { return 0 }
        return min(max(0, space.maxY - lessonSheet.minY), space.height * 0.6)
    }

    private func floatingPanel(lift: CGFloat) -> some View {
        ControlPanel(player: player, style: .floating)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
            .overlay(alignment: .top) {
                // The reason a ring cannot move floats above the panel, over the toy, taking no room, so that the
                // panel keeps its height and the toy does not move.
                if let refusal = ControlPanel.refusal(in: player.status) {
                    RefusalBubble(text: refusal)
                        .fixedSize(horizontal: false, vertical: true)
                        .visualEffect { content, proxy in
                            content.offset(y: -proxy.size.height - 10)
                        }
                        .appearingOverToy(reducesMotion: reducesMotion)
                }
            }
            .animation(.snappy(duration: 0.25), value: ControlPanel.refusal(in: player.status) == nil)
            .frame(maxWidth: 720)
            .padding(.horizontal, 12)
            .padding(.bottom, 8 + lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

#if os(iOS)
/// Half the screen, or about 400 points where half is less, but never more than about two thirds.
private struct LessonSheetDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        max(context.maxDetentValue / 2, min(400, context.maxDetentValue * 0.62))
    }
}
#endif
