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
    @State private var showsSettings = false
    @State private var showsAbout = false
    /// How much of the toy a plain cover hides, while the toy jumps to another state.
    @State private var cover = 0.0
    /// Where the floating controls are, in the global coordinate space, so that the toy is framed clear of them.
    @State private var panelFrame: CGRect = .null
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ArrangementView {
                Controls(player: player, panelFrame: $panelFrame)
                    .accessibilitySortPriority(1)
            } secondary: {
                // VoiceOver meets the toy first, then the controls.
                ToyCanvas(player: player, rig: rig, cover: panelFrame) { player.tap($0) }
                    .accessibilitySortPriority(2)
                    .overlay {
                        Backdrop.color(for: colorScheme)
                            .opacity(cover)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
            }
            .arrangementViewStyle(.overlay)
            .congratulation(player) { jump { player.reset() } }
            .navigationTitle(Text("Nine Rings", comment: "The window's title."))
            .toolbar(removing: .title)
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .inspector(isPresented: $showsLesson) {
                LessonPanel(player: player, guide: lesson) { showsLesson = false }
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
            }
            .onChange(of: showsLesson, initial: true) { _, shows in
                if shows { lesson.open() } else { lesson.close() }
            }
            #if os(iOS)
            .sheet(isPresented: $showsSettings) {
                NavigationStack { SettingsScreen() }
            }
            .sheet(isPresented: $showsAbout) {
                NavigationStack { AboutScreen() }
            }
            #endif
        }
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
        ToolbarItemGroup(placement: Self.trailing) {
            viewMenu
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
            .keyboardShortcut("0", modifiers: .command)
            Divider()
            ForEach(CameraPreset.allCases) { preset in
                Button {
                    rig.show(preset, framing: Framing.rings)
                } label: {
                    Text(preset.viewMenuTitle)
                }
                .keyboardShortcut(preset.viewShortcut, modifiers: .command)
            }
        } label: {
            Label { Text("View", comment: "Toolbar menu of the places to see the toy from.") } icon: { Image(systemName: "cube") }
        }
    }

    /// Covers the toy, makes a change that moves it to another state at once, and uncovers it, so that the jump
    /// is calm.
    private func jump(_ change: @escaping () -> Void) {
        player.pause()
        withAnimation(.easeIn(duration: 0.25)) {
            cover = 1
        } completion: {
            change()
            withAnimation(.easeOut(duration: 0.4)) { cover = 0 }
        }
    }
}

private extension CameraPreset {
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
    @Environment(\.overlayArrangementZIndex) private var zIndex
    @Environment(\.reducesMotion) private var reducesMotion

    var body: some View {
        if hasOwnSpace {
            ControlPanel(player: player, style: .beside)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { panelFrame = .null }
        } else {
            floatingPanel
        }
    }

    /// Whether the controls sit beside the toy rather than over it: the arrangement puts them over the toy, at a
    /// z-index above it, except on a half-folded Duo, where each view has its own half and the z-index is 0.
    private var hasOwnSpace: Bool {
        zIndex == 0
    }

    private var floatingPanel: some View {
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
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
