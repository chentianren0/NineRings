import Motion
import SwiftUI

/// The toy in 3D with most of the space, and the controls under it, or beside it when the window is wide and
/// short. Which one follows the window's size as it changes, never the device. The toolbar holds the written
/// moves and the camera presets.
struct ContentView: View {
    /// The box the camera frames: the whole toy through every move, so the camera need not follow it.
    private let framing: ToyBounds
    /// The shadow's height, just under the lowest the toy goes during any move.
    private let floor: Float
    @State private var player: Player
    @State private var rig: CameraRig
    /// How much of the toy a plain cover hides, while the toy jumps to another state.
    @State private var cover = 0.0
    @State private var controlsHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    init() {
        let player = LaunchOptions.move.map { Player(move: $0, progress: LaunchOptions.startProgress ?? 0) } ?? Player()
        let framing = ContentView.framing
        self.framing = framing
        floor = framing.lower.y - 6
        self.player = player
        rig = CameraRig(framing: framing)
    }

    /// The box around the toy over every move that can be shown.
    static let framing: ToyBounds = {
        let poses = Player.moves.compactMap(MoveMotion.init).flatMap { motion in
            (0...40).map { motion.pose(at: Double($0) / 40) }
        }
        return ToyBounds(poses)
    }()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let beside = Self.placesControlsBeside(in: proxy.size)
                let layout = beside ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                // One layout or the other, with the same two children, so the 3D view is never rebuilt on a resize.
                layout {
                    ToyView(player: player, rig: rig, floor: floor, insets: EdgeInsets(top: proxy.safeAreaInsets.top, leading: 0, bottom: beside ? proxy.safeAreaInsets.bottom : 0, trailing: 0))
                        .overlay {
                            Backdrop.color(for: colorScheme)
                                .opacity(cover)
                                .allowsHitTesting(false)
                        }
                        .ignoresSafeArea(edges: beside ? [.top, .bottom, .leading] : [.top, .horizontal])
                    controls(beside: beside, in: proxy.size)
                }
            }
            .navigationTitle(Text("Nine Rings", comment: "The window's title."))
            .toolbar { toolbar }
                #if os(iOS)
                .toolbarTitleDisplayMode(.inline)
                #endif
        }
    }

    /// The controls go beside the toy only when the window is too short for them underneath and wide enough
    /// to spare a column; the toy is long and low, so it is better given the full width.
    static func placesControlsBeside(in size: CGSize) -> Bool {
        size.height < 520 && size.width >= 640 && size.width >= 1.4 * size.height
    }

    private func controls(beside: Bool, in size: CGSize) -> some View {
        ScrollView {
            PlayerControls(player: player, reset: { jump { player.reset() } })
                .padding(16)
                .frame(maxWidth: beside ? nil : 760)
                .frame(maxWidth: .infinity)
                .frame(minHeight: beside ? size.height : 0)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Underneath, the controls take what they need, up to a little over half the height; past that, they scroll.
        .frame(height: beside ? nil : min(controlsHeight, size.height * 0.55))
        .frame(width: beside ? min(max(size.width * 0.36, 320), 420) : nil)
        .background(.bar)
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(Player.moves, id: \.self) { move in
                    Button {
                        jump { player.begin(at: move) }
                    } label: {
                        Text("Ring \(move.ring) comes off", comment: "Menu item that sets the toy where this ring's written move begins and plays it. The variable is the ring's number.")
                    }
                }
            } label: {
                Label { Text("Written Moves", comment: "Menu of the moves the app can already show.") } icon: { Image(systemName: "list.bullet") }
            }
            .help(Text("Set the toy where a written move begins, and play it", comment: "Tooltip on the written moves menu."))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                ForEach(CameraPreset.allCases) { preset in
                    Button { rig.show(preset, framing: framing) } label: { Text(preset.name) }
                        .keyboardShortcut(preset.shortcut, modifiers: .command)
                        .help(Text(preset.help))
                }
            } label: {
                Label { Text("View", comment: "Menu of the camera's places.") } icon: { Image(systemName: "cube") }
            }
        }
    }
}

private extension CameraPreset {
    var name: LocalizedStringResource {
        switch self {
        case .side: LocalizedStringResource("Side", comment: "Camera place: the toy seen from the side.")
        case .top: LocalizedStringResource("Top", comment: "Camera place: the toy seen from above.")
        case .tip: LocalizedStringResource("Tip", comment: "Camera place: the toy seen from the sword's tip.")
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .side: LocalizedStringResource("View from the side", comment: "Tooltip on a camera place.")
        case .top: LocalizedStringResource("View from the top", comment: "Tooltip on a camera place.")
        case .tip: LocalizedStringResource("View from the tip", comment: "Tooltip on a camera place.")
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .side: "1"
        case .top: "2"
        case .tip: "3"
        }
    }
}

/// Options read from the launch arguments.
enum LaunchOptions {
    /// `-move 2` opens the app where ring 2's written move begins, with that move on the slider.
    static var move: Move? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-move"), index + 1 < arguments.count, let ring = Int(arguments[index + 1]) else { return nil }
        return Player.moves.first { $0.ring == ring }
    }

    /// `-start-progress 0.5` opens the app that far through that move, for checking a pose by hand.
    static var startProgress: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-start-progress"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }
}

#Preview {
    ContentView()
}
