import Motion
import SwiftUI

/// The toy filling the window, the controls for the move over its bottom edge, and the choice of move and the
/// camera presets in the toolbar.
struct ContentView: View {
    /// The box the camera frames: the whole toy through every move, so the camera need not follow it.
    private let framing: ToyBounds
    /// The shadow's height, just under the lowest the toy goes during any move.
    private let floor: Float
    @State private var player: Player
    @State private var rig: CameraRig
    @State private var controlsHeight: CGFloat = 0

    init() {
        let player = Player(move: LaunchOptions.move, progress: LaunchOptions.startProgress ?? 0)
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
                // The toy is drawn under the bars, and framed in the part they and the controls leave uncovered.
                let insets = EdgeInsets(top: proxy.safeAreaInsets.top, leading: 0, bottom: proxy.safeAreaInsets.bottom + controlsHeight, trailing: 0)
                ToyView(player: player, rig: rig, floor: floor, insets: insets)
                    .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) {
                PlayerControls(player: player)
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
            }
            .navigationTitle("Ring \(player.move.ring)")
            .toolbar { toolbar }
                #if os(iOS)
                .toolbarTitleDisplayMode(.inline)
                #endif
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Move", selection: $player.move) {
                ForEach(Player.moves, id: \.self) { move in
                    Text("Ring \(move.ring)").tag(move)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Which ring's move to show")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                ForEach(CameraPreset.allCases) { preset in
                    Button(preset.title) { rig.show(preset, framing: framing) }
                        .keyboardShortcut(preset.shortcut, modifiers: .command)
                        .help("View from the \(preset.title.lowercased())")
                }
            } label: {
                Label("View", systemImage: "cube")
            }
        }
    }
}

private extension CameraPreset {
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
    /// `-move 2` opens the app on ring 2's move.
    static var move: Move? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-move"), index + 1 < arguments.count, let ring = Int(arguments[index + 1]) else { return nil }
        return Player.moves.first { $0.ring == ring }
    }

    /// `-start-progress 0.5` opens the app that far through the move, for checking a pose by hand.
    static var startProgress: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-start-progress"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }
}

#Preview {
    ContentView()
}
