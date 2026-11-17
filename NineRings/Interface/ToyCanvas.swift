import Motion
import Puzzle
import RealityKit
import Session
import SwiftUI
import Toy

/// The toy in 3D, filling the whole window behind the bars and controls. Each frame it moves the player and the
/// camera on and draws what changed. A tap on a ring, its rod or its bead asks to move that ring.
///
/// The camera frames the toy in the part of the view nothing covers: the safe area's bars, and `covers`, the frames
/// of what floats over the toy (the controls, the lesson's sheet on a phone), in the global coordinate space. With the
/// setting to follow the move on, the picture widens while a move slides the sword, so as to keep the sword in view;
/// with Reduce Motion it stays still, and the camera's flights cut instead of flying.
///
/// To VoiceOver the toy is one element, "Toy", whose value says which rings are on and which can move (see
/// ``ToySummary``), after the status line's sentence while a move is in hand. The rings are moved by their buttons.
struct ToyCanvas: View {
    let player: Player
    let rig: CameraRig
    var covers: [CGRect] = []
    let tapRing: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage(Framing.followsMoveKey) private var followsMove = false
    @Environment(\.reducesMotion) private var reducesMotion

    /// The view's frame in the global coordinate space and its safe area, as the last layout left them. Read with
    /// `onGeometryChange`, which reports every layout: a geometry reader's body was seen to miss a window growing on
    /// the Mac with the lesson open, which left the toy framed for the old size and cut off.
    @State private var space: Space?

    private nonisolated struct Space: Equatable, Sendable {
        var frame: CGRect
        var safeArea: EdgeInsets
    }

    var body: some View {
        ZStack {
            // Measured inside the safe area, as the 3D view behind it fills the whole window.
            Color.clear
                .onGeometryChange(for: Space.self) { proxy in
                    Space(frame: proxy.frame(in: .global), safeArea: proxy.safeAreaInsets)
                } action: { space = $0 }
            ToyRealityView(player: player, rig: rig, tapRing: tapRing)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .onChange(of: space.map(viewport), initial: true) { _, viewport in
            if let viewport { rig.resize(to: viewport) }
        }
        .background(Backdrop.color(for: colorScheme))
        .onChange(of: followsMove && !reducesMotion, initial: true) { _, follows in
            rig.followsMove = follows
        }
        .onChange(of: reducesMotion, initial: true) { _, reduces in
            rig.reducesMotion = reduces
        }
        .overlay {
            ToyDescription(player: player)
                .allowsHitTesting(false)
        }
    }

    /// The whole view, and how much of each edge bars and controls cover.
    private func viewport(_ space: Space) -> Viewport {
        let safe = space.safeArea
        let left = layoutDirection == .leftToRight ? safe.leading : safe.trailing
        let right = layoutDirection == .leftToRight ? safe.trailing : safe.leading
        let inner = space.frame
        let whole = CGRect(x: inner.minX - left, y: inner.minY - safe.top,
                           width: inner.width + left + right, height: inner.height + safe.top + safe.bottom)
        var viewport = Viewport(size: whole.size, topInset: safe.top, bottomInset: safe.bottom, leftInset: left, rightInset: right)
        // Leave a little air between the toy and what covers it.
        let gap: CGFloat = 8
        for covered in Self.blocks(covers.map { whole.intersection($0) }, across: whole.width) {
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
        }
        return viewport
    }

    /// The parts of the view that are covered, with covers that span the view and stand one on another, such as
    /// controls floating on top of a sheet, joined into one block, so that the block is seen to rise from the bottom.
    private static func blocks(_ covered: [CGRect], across width: CGFloat) -> [CGRect] {
        let parts = covered.filter { !$0.isNull && $0.width > 1 && $0.height > 1 }
        var wide = parts.filter { $0.width > width / 2 }.sorted { $0.minY < $1.minY }
        var joined: [CGRect] = []
        while let next = wide.first {
            wide.removeFirst()
            if let last = joined.last, next.minY - last.maxY <= 24 {
                joined[joined.count - 1] = last.union(next)
            } else {
                joined.append(next)
            }
        }
        return joined + parts.filter { $0.width <= width / 2 }
    }
}

/// The toy as VoiceOver has it: one element, "Toy", over the whole view. A view of its own, so that what it reads (the
/// status and the rings) redraws it alone, not the 3D view.
private struct ToyDescription: View {
    let player: Player

    var body: some View {
        Color.clear
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("toy.label", tableName: "Accessibility"))
            .accessibilityValue(Text(verbatim: spokenValue))
            .accessibilityAddTraits(.isImage)
    }

    /// The status line's sentence while a move is in hand, then which rings are on and, unless the lesson holds the toy
    /// so that no ring can be asked for, which can move.
    private var spokenValue: String {
        let summary = Spoken.summary(ToySummary(player.shownState), sayingWhichCanMove: !player.lessonHoldsToy)
        switch player.status {
        case .playing, .paused:
            return String(localized: "toy.valueWhileMoving \(String(localized: Sentences.status(player.status))) \(summary)", table: "Accessibility")
        case .note, .resting:
            return summary
        }
    }
}

/// The RealityKit view itself, with the camera gestures and the tap on a ring.
private struct ToyRealityView: View {
    let player: Player
    let rig: CameraRig
    let tapRing: (Int) -> Void

    @State private var frameUpdates: EventSubscription?
    /// With VoiceOver on, a double tap on the toy would land at its middle and ask for whichever ring is there: the
    /// rings are moved by their buttons instead.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            Signposts.event("RealityView made")
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
                #if MEASURE && os(macOS)
                MeasureLog.frame(delta: event.deltaTime)
                #endif
            }
            #if MEASURE && os(macOS)
            MeasureScript.start(player: player, rig: rig)
            #endif
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let ring = SceneStore.ring(of: value.entity) {
                        tapRing(ring)
                    }
                },
            isEnabled: !voiceOver
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
            await Signposts.interval("Scene") {
                guard let scene = try? await ToyScene.make() else { return nil }
                Signposts.interval("Floor") { scene.setFloor(Framing.floor) }
                Signposts.interval("Tap shapes") { Self.makeTappable(scene.root) }
                return scene
            }
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
    private var frames = 0

    init(player: Player, rig: CameraRig, scene: ToyScene, camera: Entity) {
        self.player = player
        self.rig = rig
        self.scene = scene
        self.camera = camera
    }

    func step(by seconds: TimeInterval) {
        // The first call is the one the RealityView's make closure makes itself, before any frame; the second is the
        // first frame's update, as the toy is first drawn. So the first frame is marked on the second call.
        if frames < 2 {
            frames += 1
            if frames == 2 { Signposts.event("First frame") }
        }
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
