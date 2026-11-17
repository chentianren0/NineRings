import Motion
import RealityKit
import SwiftUI
import Toy

/// The toy in 3D, filling the whole window behind the bars and controls. Each frame it moves the player and the
/// camera on and draws what changed. A tap on a ring, its rod or its bead asks to move that ring.
///
/// The camera frames the toy in the part of the view nothing covers: the safe area's bars, and `cover`, the frame
/// of controls floating over the toy, in the global coordinate space. With the setting to follow the move on, the
/// picture widens while a move slides the sword, so as to keep the sword in view.
struct ToyCanvas: View {
    let player: Player
    let rig: CameraRig
    var cover: CGRect = .null
    let tapRing: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage(Framing.followsMoveKey) private var followsMove = false

    var body: some View {
        GeometryReader { proxy in
            ToyRealityView(player: player, rig: rig, tapRing: tapRing)
                .ignoresSafeArea()
                .onChange(of: viewport(proxy), initial: true) { _, viewport in
                    rig.resize(to: viewport)
                }
        }
        .background(Backdrop.color(for: colorScheme))
        .onChange(of: followsMove, initial: true) { _, followsMove in
            rig.followsMove = followsMove
        }
    }

    /// The whole view, and how much of each edge bars and controls cover.
    private func viewport(_ proxy: GeometryProxy) -> Viewport {
        let safe = proxy.safeAreaInsets
        let left = layoutDirection == .leftToRight ? safe.leading : safe.trailing
        let right = layoutDirection == .leftToRight ? safe.trailing : safe.leading
        let inner = proxy.frame(in: .global)
        let whole = CGRect(x: inner.minX - left, y: inner.minY - safe.top,
                           width: inner.width + left + right, height: inner.height + safe.top + safe.bottom)
        var viewport = Viewport(size: whole.size, topInset: safe.top, bottomInset: safe.bottom, leftInset: left, rightInset: right)
        let covered = whole.intersection(cover)
        guard !covered.isNull, covered.width > 1, covered.height > 1 else { return viewport }
        // Leave a little air between the toy and what covers it.
        let gap: CGFloat = 8
        if covered.width > whole.width / 2 {
            if covered.midY > whole.midY {
                viewport.bottomInset = max(viewport.bottomInset, whole.maxY - covered.minY + gap)
            } else {
                viewport.topInset = max(viewport.topInset, covered.maxY - whole.minY + gap)
            }
        } else if covered.height > whole.height / 3 {
            if covered.midX > whole.midX {
                viewport.rightInset = max(viewport.rightInset, whole.maxX - covered.minX + gap)
            } else {
                viewport.leftInset = max(viewport.leftInset, covered.maxX - whole.minX + gap)
            }
        }
        return viewport
    }
}

/// The RealityKit view itself, with the camera gestures and the tap on a ring.
private struct ToyRealityView: View {
    let player: Player
    let rig: CameraRig
    let tapRing: (Int) -> Void

    @State private var frameUpdates: EventSubscription?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            guard let scene = await SceneStore.shared.scene() else { return }
            let camera = Entity()
            camera.name = "camera"
            camera.components.set(OrbitCamera.component())
            content.add(scene.root)
            content.add(camera)
            let driver = CanvasDriver(player: player, rig: rig, scene: scene, camera: camera)
            driver.step(by: 0)
            frameUpdates = content.subscribe(to: SceneEvents.Update.self) { event in
                driver.step(by: event.deltaTime)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let ring = SceneStore.ring(of: value.entity) {
                        tapRing(ring)
                    }
                }
        )
        .cameraGestures(rig)
    }
}

/// The one drawn toy, made once and kept, so that a change of layout that makes a new 3D view does not build the
/// meshes again.
@MainActor
final class SceneStore {
    static let shared = SceneStore()

    private var making: Task<ToyScene?, Never>?

    func scene() async -> ToyScene? {
        if let making { return await making.value }
        let task = Task { () -> ToyScene? in
            guard let scene = try? await ToyScene.make() else { return nil }
            scene.setFloor(Framing.floor)
            Self.makeTappable(scene.root)
            return scene
        }
        making = task
        return await task.value
    }

    /// The ring a tapped part belongs to: the ring itself, or its rod and bead.
    static func ring(of entity: Entity) -> Int? {
        let words = entity.name.split(separator: " ")
        guard words.count == 2, words[0] == "ring" || words[0] == "rod", let ring = Int(words[1]) else { return nil }
        return ring
    }

    /// Gives every ring and rod a shape that a tap can hit: the box around its mesh, which for a ring is a flat box
    /// around its disc, and for a rod a thin one from its eye to its bead.
    private static func makeTappable(_ root: Entity) {
        for ring in 1...9 {
            for name in ["ring \(ring)", "rod \(ring)"] {
                guard let part = root.findEntity(named: name) as? ModelEntity, let bounds = part.model?.mesh.bounds else { continue }
                let shape = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
                part.components.set(CollisionComponent(shapes: [shape]))
                part.components.set(InputTargetComponent())
            }
        }
    }
}

/// Moves the player and the camera on by one frame, and passes what changed to the entities.
@MainActor
private final class CanvasDriver {
    private let player: Player
    private let rig: CameraRig
    private let scene: ToyScene
    private let camera: Entity
    private var drawn: Player.PoseKey?
    private var drawnPose: ToyPose?
    private var drawnCamera = -1

    init(player: Player, rig: CameraRig, scene: ToyScene, camera: Entity) {
        self.player = player
        self.rig = rig
        self.scene = scene
        self.camera = camera
    }

    func step(by seconds: TimeInterval) {
        player.update()
        rig.advance(by: seconds)
        // The pose depends on the move, the progress and the state alone, so it is drawn again only when one of
        // them changes.
        let key = player.poseKey
        var posed = false
        if key != drawn {
            let pose = player.pose
            scene.apply(pose)
            drawn = key
            drawnPose = pose
            posed = true
        }
        // Following the move, the camera depends on the pose too.
        if rig.revision != drawnCamera || (posed && rig.followsMove), let pose = drawnPose {
            camera.transform = rig.camera(for: pose).transform
            drawnCamera = rig.revision
        }
    }
}
