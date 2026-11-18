import Foundation
import RealityKit
import Toy
import simd

/// The drawn toy: the sliding sword, the rings and rods, the still bar, the studio light and the shadow.
///
/// `root` is in RealityKit's metres. Everything of the toy hangs under one entity scaled from millimetres,
/// so poses, meshes and `Dimensions` are all used in millimetres as they are.
@MainActor
final class ToyScene {
    /// The one place where millimetres become RealityKit's metres.
    static let metresPerMillimetre: Float = 0.001

    let root = Entity()
    private let toy = Entity()
    private let rings: [ModelEntity]
    private let rods: [ModelEntity]
    private let bar: ModelEntity
    private let sword: ModelEntity
    private let shadow: ModelEntity
    /// Copies of parts left where they were before a jump, each fading out on its own.
    private var ghosts: [Ghost] = []
    /// Parts that jumped, each fading in on its own where it is now, by the part's object.
    private var arriving: [ObjectIdentifier: Arriving] = [:]

    private struct Ghost {
        let entity: Entity
        /// How much of the part showed where the copy was left: all of it, or less where the part was still fading in.
        let from: Float
        var elapsed: Double = 0
        let duration: Double
    }

    private struct Arriving {
        let part: ModelEntity
        var elapsed: Double = 0
        let duration: Double
    }

    static func make() async throws -> ToyScene {
        // The three are made at the same time: RealityKit does part of each away from the main actor, so made one after
        // another they wait for each other. This shortens the wait for the toy's first frame.
        async let meshes = Signposts.interval("Meshes") { try await ToyMeshes() }
        async let light = Signposts.interval("Light") { try await Studio.light() }
        async let shadow = Signposts.interval("Shadow") { try await Studio.shadow() }
        let parts = try await (meshes, light, shadow)
        return Signposts.interval("Entities") { ToyScene(meshes: parts.0, light: parts.1, shadow: parts.2) }
    }

    private init(meshes: ToyMeshes, light: Entity, shadow: ModelEntity) {
        let wire = ToyMaterials.wire
        // One material each, shared by every part that has it, rather than one per part.
        let wood = ToyMaterials.wood
        rings = (1...9).map { number in
            let ring = ModelEntity(mesh: meshes.ring, materials: [wire])
            ring.name = "ring \(number)"
            return ring
        }
        rods = (1...9).map { number in
            let rod = ModelEntity(mesh: meshes.rod, materials: [wire, wood])
            rod.name = "rod \(number)"
            return rod
        }
        bar = ModelEntity(mesh: meshes.bar, materials: [ToyMaterials.bar])
        bar.name = "bar"
        self.shadow = shadow
        sword = ModelEntity(mesh: meshes.sword, materials: [wire])
        sword.name = "sword"

        toy.name = "toy"
        toy.scale = SIMD3(repeating: Self.metresPerMillimetre)
        for part in [sword, bar] + rings + rods {
            part.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            toy.addChild(part)
        }
        toy.addChild(shadow)
        root.addChild(light)
        root.addChild(toy)
    }

    /// Places every part. This sets transforms only, so it is cheap enough to call every frame.
    func apply(_ pose: ToyPose) {
        for index in 0..<9 {
            place(rings[index], at: pose.rings[index])
            place(rods[index], at: pose.rods[index])
        }
        place(bar, at: pose.bar)
        place(sword, at: pose.sword)
    }

    /// Shows the jump from `old` to the pose now applied as the parts that changed place fading across, over `duration`
    /// seconds. Nothing fades where nothing changed place. Each part fades on its own: a part that jumps again while it
    /// fades leaves a copy as faint as it shows now and starts fading in afresh, and fades already under way go on.
    func crossFade(from old: ToyPose, to new: ToyPose, duration: Double) {
        let moved = new.parts(movedFrom: old)
        guard !moved.isEmpty, duration > 0 else { return }
        func leave(_ part: ModelEntity, at pose: PartPose) {
            let ghost = part.clone(recursive: false)
            ghost.name = ""
            // Only the part itself can be tapped, and the copy fades from what showed of the part.
            ghost.components.remove(CollisionComponent.self)
            ghost.components.remove(InputTargetComponent.self)
            ghost.components.remove(OpacityComponent.self)
            place(ghost, at: pose)
            toy.addChild(ghost)
            ghosts.append(Ghost(entity: ghost, from: shownOpacity(of: part), duration: duration))
            arriving[ObjectIdentifier(part)] = Arriving(part: part, duration: duration)
        }
        for number in moved.rings.sorted() { leave(rings[number - 1], at: old.ring(number)) }
        for number in moved.rods.sorted() { leave(rods[number - 1], at: old.rod(number)) }
        if moved.bar { leave(bar, at: old.bar) }
        if moved.sword { leave(sword, at: old.sword) }
        showFades()
    }

    /// Moves the fades on by `seconds`. Cheap when nothing fades, so it can be called every frame.
    func advanceFade(by seconds: Double) {
        guard !ghosts.isEmpty || !arriving.isEmpty else { return }
        for index in ghosts.indices { ghosts[index].elapsed += seconds }
        for key in arriving.keys { arriving[key]?.elapsed += seconds }
        for ghost in ghosts where ghost.elapsed >= ghost.duration { ghost.entity.removeFromParent() }
        ghosts.removeAll { $0.elapsed >= $0.duration }
        for (key, part) in arriving where part.elapsed >= part.duration {
            part.part.components.remove(OpacityComponent.self)
            arriving[key] = nil
        }
        showFades()
    }

    /// How much of `part` shows now: all of it, unless it is fading in.
    private func shownOpacity(of part: ModelEntity) -> Float {
        guard let fade = arriving[ObjectIdentifier(part)] else { return 1 }
        return CrossFadeStyle.current.opacities(at: Self.progress(fade.elapsed, fade.duration)).into
    }

    private func showFades() {
        let style = CrossFadeStyle.current
        for ghost in ghosts {
            let out = style.opacities(at: Self.progress(ghost.elapsed, ghost.duration)).out
            ghost.entity.components.set(OpacityComponent(opacity: ghost.from * out))
        }
        for fade in arriving.values {
            let into = style.opacities(at: Self.progress(fade.elapsed, fade.duration)).into
            fade.part.components.set(OpacityComponent(opacity: into))
        }
    }

    private static func progress(_ elapsed: Double, _ duration: Double) -> Float {
        Float(min(elapsed / duration, 1))
    }

    /// Lays the shadow on an imagined table at height `floor`, in millimetres; it stays there while the toy
    /// moves above it.
    func setFloor(_ floor: Float) {
        shadow.position.y = floor
    }

    private func place(_ entity: Entity, at pose: PartPose) {
        entity.transform = Transform(
            scale: .one,
            rotation: simd_quatf(vector: SIMD4<Float>(pose.orientation.vector)),
            translation: SIMD3<Float>(pose.position)
        )
    }

    /// A point given in millimetres in the toy's frame, in metres in `root`'s frame.
    static func metres(_ millimetres: SIMD3<Float>) -> SIMD3<Float> {
        millimetres * metresPerMillimetre
    }
}

/// How the two copies of a part that jumped share the fade: the old one going as the new one comes. `-motion.crossFade
/// dip`, in a debug build, has the old one gone before the new one comes, to compare.
enum CrossFadeStyle: String {
    case blend, dip

    static let current: CrossFadeStyle = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-motion.crossFade"), index + 1 < arguments.count,
           let style = CrossFadeStyle(rawValue: arguments[index + 1]) {
            return style
        }
        #endif
        return .blend
    }()

    /// The opacity of the old copy and of the new at `t`, from 0 to 1 through the fade.
    func opacities(at t: Float) -> (out: Float, into: Float) {
        let eased = t * t * (3 - 2 * t)
        switch self {
        case .blend:
            return (1 - eased, eased)
        case .dip:
            let out = min(t / 0.5, 1), into = max((t - 0.5) / 0.5, 0)
            return (1 - out * out * (3 - 2 * out), into * into * (3 - 2 * into))
        }
    }
}
