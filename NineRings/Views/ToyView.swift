import RealityKit
import SwiftUI

/// The toy in 3D, filling its space. Each frame it moves the player and the camera on and draws what changed.
struct ToyView: View {
    let player: Player
    let rig: CameraRig
    /// The shadow's height under the toy, in millimetres.
    let floor: Float
    /// How much of the top and bottom of the view bars and controls cover; the toy is framed between them.
    var insets = EdgeInsets()

    @Environment(\.colorScheme) private var colorScheme
    @State private var frameUpdates: EventSubscription?
    @State private var size: CGSize = .zero

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            guard let scene = try? await ToyScene.make() else { return }
            scene.setFloor(floor)
            let camera = Entity()
            camera.name = "camera"
            camera.components.set(OrbitCamera.component())
            content.add(scene.root)
            content.add(camera)
            let driver = FrameDriver(player: player, rig: rig, scene: scene, camera: camera)
            driver.step(by: 0)
            frameUpdates = content.subscribe(to: SceneEvents.Update.self) { event in
                driver.step(by: event.deltaTime)
            }
        }
        .background(Backdrop.color(for: colorScheme))
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .onChange(of: Viewport(size: size, topInset: insets.top, bottomInset: insets.bottom), initial: true) { _, viewport in
            rig.resize(to: viewport)
        }
        .cameraGestures(rig)
    }
}

/// Moves the player and the camera on by one frame, and passes what changed to the entities.
@MainActor
private final class FrameDriver {
    private let player: Player
    private let rig: CameraRig
    private let scene: ToyScene
    private let camera: Entity
    private var drawnProgress = -1.0
    private var drawnCamera = -1

    init(player: Player, rig: CameraRig, scene: ToyScene, camera: Entity) {
        self.player = player
        self.rig = rig
        self.scene = scene
        self.camera = camera
    }

    func step(by seconds: TimeInterval) {
        player.advance(by: seconds)
        rig.advance(by: seconds)
        // The pose depends on the progress alone, so it is drawn again only when the progress changes.
        if player.progress != drawnProgress {
            scene.apply(player.pose)
            drawnProgress = player.progress
        }
        if rig.revision != drawnCamera {
            camera.transform = rig.camera.transform
            drawnCamera = rig.revision
        }
    }
}
