import GameSave
import SwiftUI

/// The app's one window: the puzzle, with the lesson and settings opening from its toolbar.
///
/// The player and the camera live here, so that they outlast any rebuilding of the screen below. So does Apple's alert
/// for GameSave's folder, which needs a window: the keeper opens the folder as the app comes to the front, the alert
/// shows while it loads, and the toy read there comes to the player.
struct MainScreen: View {
    @State private var player: Player
    @State private var rig: CameraRig
    @Bindable private var keeper: Keeper
    @Environment(\.scenePhase) private var scenePhase
    /// The screen's mode, and the one place it changes: the welcome page opens the lesson through it too.
    @State private var modes: ScreenModes
    #if DEBUG
    @AppStorage(DesignKey.tallView) private var tallView = TallViewDesign.standard
    #else
    private let tallView = TallViewDesign.standard
    #endif

    /// The screen over the launch's one keeper, which the player brings the toy back from, keeps it in, and records
    /// finished plays in. A window made again, as the Mac's Dock makes it, gets the same keeper, and the toy it kept.
    init(keeper: Keeper) {
        self.keeper = keeper
        let player = StoreCapture.player(keeper: keeper)
            ?? LaunchOptions.move.map { Player(move: $0, progress: LaunchOptions.startProgress ?? 0, keeper: keeper) }
            ?? Player(keeper: keeper)
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
            .keepsPlay(player, keeper: keeper, scenePhase: scenePhase)
            .gameSaveSyncingAlert(directory: $keeper.loading) {
                if let toy = keeper.finishLoading() { modes.take(toy) }
            }
            .environment(modes)
            .onAppear { GameCenter.shared.start() }
            #if os(macOS)
            .frame(minHeight: 420)
            #endif
    }
}

extension View {
    /// Tells `player` and `keeper` when the app comes to the front and leaves it: the play counts its time there and
    /// the toy is kept as the app leaves, and the keeper opens GameSave's folder again when the app comes back. On the
    /// Mac a window stays active behind other apps, so it is the app being the active one, and quitting; and closing
    /// the window, which leaves the app running, so that the window the Dock opens next brings the toy back as it was
    /// and opens the folder again. On iPhone and iPad it is the scene's phase: the play counts only while it is active,
    /// and the folder opens again only after the app was in the background, not after a short interruption such as
    /// Control Center.
    func keepsPlay(_ player: Player, keeper: Keeper, scenePhase: ScenePhase) -> some View {
        #if os(macOS)
        onAppear {
            guard NSApplication.shared.isActive else { return }
            player.cameToFront()
            keeper.cameToFront()
        }
        .onDisappear {
            player.leftFront()
            keeper.windowClosed()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            player.cameToFront()
            keeper.cameToFront()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            player.leftFront()
            keeper.leftFront()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in player.leftFront() }
        #else
        onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                player.cameToFront()
                keeper.cameToFront()
            case .background:
                player.leftFront()
                keeper.leftFront()
            default:
                player.leftFront()
            }
        }
        #endif
    }
}
