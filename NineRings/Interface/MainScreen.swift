import SwiftUI

/// The app's one window: the puzzle, with the lesson and settings opening from its toolbar.
///
/// The player and the camera live here, so that they outlast any rebuilding of the screen below.
struct MainScreen: View {
    @State private var player: Player
    @State private var rig: CameraRig
    #if DEBUG
    @AppStorage(DesignKey.tallView) private var tallView = TallViewDesign.standard
    #else
    private let tallView = TallViewDesign.standard
    #endif

    init() {
        player = LaunchOptions.move.map { Player(move: $0, progress: LaunchOptions.startProgress ?? 0) } ?? Player()
        rig = CameraRig(framing: Framing.rings)
    }

    var body: some View {
        PuzzleScreen(player: player, rig: rig)
            .welcomeOnFirstLaunch()
            .accessibilityLaunchTaps(player)
            .accessibilitySettings()
            .onChange(of: tallView, initial: true) { _, tallView in
                rig.defaultAngles = Framing.defaultAngles(tallView: tallView)
                rig.showDefault()
            }
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 420)
            #endif
    }
}
