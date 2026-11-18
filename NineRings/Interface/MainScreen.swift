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
        let player = StoreCapture.player() ?? LaunchOptions.move.map { Player(move: $0, progress: LaunchOptions.startProgress ?? 0) } ?? Player()
        #if DEBUG
        if let rings = LaunchOptions.settingRings {
            player.startSettingRings()
            player.setRings(to: rings)
        }
        #endif
        self.player = player
        rig = CameraRig(framing: Framing.rings)
    }

    var body: some View {
        PuzzleScreen(player: player, rig: rig)
            .accessibilityLaunchTaps(player)
            .accessibilitySettings()
            .onChange(of: tallView, initial: true) { _, tallView in
                rig.defaultAngles = StoreCapture.defaultAngles ?? Framing.defaultAngles(tallView: tallView)
                rig.showDefault()
            }
            .storeCapture(player: player, rig: rig)
            #if os(macOS)
            .frame(minHeight: 420)
            #endif
    }
}
