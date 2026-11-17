import SwiftUI

/// The app's one window: the puzzle, and, when the design has a tab bar, tabs for the lesson and settings beside it.
///
/// The player and the camera live here, so that switching the design keeps the puzzle where it is.
struct MainScreen: View {
    @State private var player: Player
    @State private var rig: CameraRig
    #if DEBUG
    @AppStorage(DesignKey.navigation) private var navigation = NavigationDesign.none
    @AppStorage(DesignKey.tallView) private var tallView = TallViewDesign.side
    #else
    private let navigation = NavigationDesign.none
    private let tallView = TallViewDesign.side
    #endif

    init() {
        player = LaunchOptions.move.map { Player(move: $0, progress: LaunchOptions.startProgress ?? 0) } ?? Player()
        rig = CameraRig(framing: Framing.rings)
    }

    var body: some View {
        Group {
            switch navigation {
            case .none:
                PuzzleScreen(player: player, rig: rig, hasTabs: false)
            case .tabBar:
                TabView {
                    Tab { PuzzleScreen(player: player, rig: rig, hasTabs: true) } label: {
                        Label { Text("Puzzle", comment: "Tab with the toy.") } icon: { Image(systemName: "circle.grid.3x3") }
                    }
                    Tab {
                        let lesson = LessonGuide(player: player, rig: rig)
                        NavigationStack { LessonPanel(player: player, guide: lesson) }
                            .onAppear { lesson.open() }
                            .onDisappear { lesson.close() }
                    } label: {
                        Label { Text("Lesson", comment: "Tab with the lesson on how the puzzle works.") } icon: { Image(systemName: "book") }
                    }
                    Tab {
                        NavigationStack { SettingsPlaceholder() }
                    } label: {
                        Label { Text("Settings", comment: "Tab with the app's settings.") } icon: { Image(systemName: "gear") }
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
            }
        }
        .onChange(of: tallView, initial: true) { _, tallView in
            rig.defaultAngles = Framing.defaultAngles(tallView: tallView)
            rig.showDefault()
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}
