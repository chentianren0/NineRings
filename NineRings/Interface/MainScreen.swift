import SwiftUI

/// The app's one window: the puzzle, with the lesson and settings opening from its toolbar.
///
/// The player and the camera live here, so that they outlast any rebuilding of the screen below.
struct MainScreen: View {
    @State private var player: Player
    @State private var rig: CameraRig
    @Environment(\.scenePhase) private var scenePhase
    /// The screen's mode, and the one place it changes: the welcome page opens the lesson through it too.
    @State private var modes: ScreenModes
    #if DEBUG
    @AppStorage(DesignKey.tallView) private var tallView = TallViewDesign.standard
    #else
    private let tallView = TallViewDesign.standard
    #endif

    init() {
        let player = StoreCapture.player()
            ?? LaunchOptions.move.map { Player(move: $0, progress: LaunchOptions.startProgress ?? 0) }
            ?? Player(keeper: LaunchOptions.keepsToy ? Keeper() : nil)
        #if DEBUG
        if let rings = LaunchOptions.settingRings {
            player.startSettingRings()
            player.setRings(to: rings)
        }
        #endif
        let rig = CameraRig(framing: Framing.rings)
        self.player = player
        self.rig = rig
        modes = ScreenModes(player: player, rig: rig, showsLesson: LessonLaunchOptions.opensAtLaunch)
    }

    var body: some View {
        PuzzleScreen(modes: modes)
            .welcomeOnFirstLaunch(openLesson: modes.openLesson)
            .accessibilityLaunchTaps(player)
            .accessibilitySettings()
            .onChange(of: tallView, initial: true) { _, tallView in
                rig.defaultAngles = StoreCapture.defaultAngles ?? Framing.defaultAngles(tallView: tallView)
                rig.showDefault()
            }
            .storeCapture(player: player, rig: rig)
            .keepsPlay(player, scenePhase: scenePhase)
            .environment(modes)
            .onAppear { GameCenter.shared.start() }
            #if os(macOS)
            .frame(minHeight: 420)
            #endif
    }
}

extension View {
    /// Tells `player` when the app comes to the front and leaves it, so that the play counts its time there and the
    /// toy is kept as the app leaves. On iPhone and iPad that is the scene's phase. On the Mac a window stays active
    /// behind other apps, so it is the app being the active one, and quitting.
    func keepsPlay(_ player: Player, scenePhase: ScenePhase) -> some View {
        #if os(macOS)
        onAppear { if NSApplication.shared.isActive { player.cameToFront() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in player.cameToFront() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in player.leftFront() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in player.leftFront() }
        #else
        onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { player.cameToFront() } else { player.leftFront() }
        }
        #endif
    }
}
