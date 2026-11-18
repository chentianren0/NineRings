import CoreGraphics
import RealityKit
import simd

/// The three views a person can jump to.
enum CameraPreset: String, CaseIterable, Identifiable {
    /// From the side, the tip on the left.
    case side
    /// From above, the tip on the left.
    case top
    /// Looking at the tip end on.
    case tip

    var id: Self { self }

    var title: String {
        switch self {
        case .side: "Side"
        case .top: "Top"
        case .tip: "Tip"
        }
    }

    var angles: (yaw: Float, pitch: Float) {
        switch self {
        case .side: (0, 0)
        case .top: (0, .pi / 2)
        case .tip: (-.pi / 2, 0)
        }
    }
}

/// The part of a view the toy is framed in, in points: its size, and how much of each edge is covered by bars
/// and controls.
struct Viewport: Equatable {
    var size: CGSize
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var leftInset: CGFloat = 0
    var rightInset: CGFloat = 0

    var isEmpty: Bool {
        size.width <= leftInset + rightInset + 1 || size.height <= topInset + bottomInset + 1
    }

    /// Whether the uncovered part differs from `other`'s by a step, as when a panel or a sheet arrives or goes, rather
    /// than by the few points a frame that a window being resized moves.
    func differsByAStep(from other: Viewport) -> Bool {
        let step: CGFloat = 24
        return abs(size.width - other.size.width) > step || abs(size.height - other.size.height) > step
            || abs(topInset - other.topInset) > step || abs(bottomInset - other.bottomInset) > step
            || abs(leftInset - other.leftInset) > step || abs(rightInset - other.rightInset) > step
    }

    /// The uncovered part's width over its height.
    var aspectRatio: CGFloat {
        isEmpty ? 1 : (size.width - leftInset - rightInset) / (size.height - topInset - bottomInset)
    }
}

/// A camera that circles a target point: everything about it is in millimetres in the toy's frame.
///
/// Yaw turns it around the vertical, with yaw 0 looking from +z so that the tip is on the left; pitch raises it,
/// up to looking straight down.
struct OrbitCamera: Equatable {
    var target: SIMD3<Float>
    var yaw: Float
    var pitch: Float
    var distance: Float

    /// The vertical field of view. A long lens keeps the toy's proportions, as a product photo does.
    static let fieldOfView: Float = 28 * .pi / 180
    /// Clipping planes, in millimetres. The near plane is far closer than the closest a person can zoom.
    static let near: Float = 0.5
    static let far: Float = 20_000
    private static let closest: Float = 20
    private static let pitchRange: ClosedRange<Float> = (-80 * .pi / 180)...(.pi / 2)

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
    }

    var position: SIMD3<Float> {
        target + rotation.act([0, 0, distance])
    }

    /// The camera's transform in RealityKit's metres.
    var transform: Transform {
        Transform(scale: .one, rotation: rotation, translation: ToyScene.metres(position))
    }

    static func component() -> PerspectiveCameraComponent {
        PerspectiveCameraComponent(
            near: near * ToyScene.metresPerMillimetre,
            far: far * ToyScene.metresPerMillimetre,
            fieldOfViewInDegrees: fieldOfView * 180 / .pi
        )
    }

    // MARK: Framing

    /// The camera for `preset`, placed so that `box` fits the uncovered part of `viewport`, centred in it.
    static func framing(_ preset: CameraPreset, of box: ToyBounds, in viewport: Viewport) -> OrbitCamera {
        framing(yaw: preset.angles.yaw, pitch: preset.angles.pitch, of: box, in: viewport)
    }

    /// The camera looking from `yaw` and `pitch`, placed so that `box` fits the uncovered part of `viewport`.
    static func framing(yaw: Float, pitch: Float, of box: ToyBounds, in viewport: Viewport) -> OrbitCamera {
        var camera = OrbitCamera(target: box.center, yaw: yaw, pitch: pitch, distance: 500)
        guard !viewport.isEmpty else { return camera }
        camera.distance = camera.fittingDistance(of: box, in: viewport)
        // Move the target so the toy sits in the middle of the uncovered part.
        let millimetresPerPoint = camera.distance * tan(fieldOfView / 2) / Float(viewport.size.height)
        let up = Float(viewport.bottomInset - viewport.topInset) * millimetresPerPoint
        let right = Float(viewport.leftInset - viewport.rightInset) * millimetresPerPoint
        camera.target -= camera.rotation.act([0, 1, 0]) * up + camera.rotation.act([1, 0, 0]) * right
        return camera
    }

    /// How far away the camera must be, looking the way it looks, for `box` to fit in `viewport`.
    func fittingDistance(of box: ToyBounds, in viewport: Viewport) -> Float {
        let tangent = tan(Self.fieldOfView / 2)
        let height = Float(viewport.size.height)
        let vertical = tangent * (height - Float(viewport.topInset + viewport.bottomInset)) / height
        let horizontal = tangent * Float(viewport.size.width - viewport.leftInset - viewport.rightInset) / height
        let right = rotation.act([1, 0, 0]), up = rotation.act([0, 1, 0]), back = rotation.act([0, 0, 1])
        let margin: Float = 1.08
        var distance: Float = 0
        for corner in 0..<8 {
            let pick = SIMD3<Float>(Float(corner & 1), Float((corner >> 1) & 1), Float((corner >> 2) & 1))
            let offset = box.size * (pick - 0.5)
            let depth = simd_dot(offset, back)
            distance = max(distance,
                           abs(simd_dot(offset, right)) * margin / horizontal + depth,
                           abs(simd_dot(offset, up)) * margin / vertical + depth)
        }
        return distance
    }

    /// Keeps `box` the same size relative to the view when the view changes size.
    mutating func refit(_ box: ToyBounds, from old: Viewport, to new: Viewport) {
        guard !old.isEmpty, !new.isEmpty else { return }
        distance *= fittingDistance(of: box, in: new) / fittingDistance(of: box, in: old)
    }

    // MARK: Gestures

    /// Turns the camera around the target by a drag of `translation` points.
    mutating func orbit(by translation: CGSize) {
        let radiansPerPoint: Float = 0.008
        yaw -= Float(translation.width) * radiansPerPoint
        pitch = min(max(pitch + Float(translation.height) * radiansPerPoint, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
    }

    /// Slides the camera and its target so that the toy follows a drag of `translation` points.
    mutating func pan(by translation: CGSize, in viewport: Viewport) {
        guard !viewport.isEmpty else { return }
        let millimetresPerPoint = 2 * distance * tan(Self.fieldOfView / 2) / Float(viewport.size.height)
        let right = rotation.act([1, 0, 0]), up = rotation.act([0, 1, 0])
        target += (-right * Float(translation.width) + up * Float(translation.height)) * millimetresPerPoint
    }

    /// Moves the camera toward the target, by `factor` (more than 1 to come closer).
    mutating func zoom(by factor: CGFloat) {
        guard factor > 0 else { return }
        distance = min(max(distance / Float(factor), Self.closest), 5_000)
    }

    // MARK: Following

    /// The middle of the uncovered part of `viewport` at the target's distance, as offsets from the target along the
    /// camera's right and up, and how far the view reaches from that middle there, sideways and up. All in millimetres,
    /// and all in proportion to `distance`.
    private func window(in viewport: Viewport) -> (right: Float, up: Float, halfWidth: Float, halfHeight: Float) {
        let perPoint = distance * tan(Self.fieldOfView / 2) / Float(viewport.size.height)
        return (
            right: Float(viewport.leftInset - viewport.rightInset) * perPoint,
            up: Float(viewport.bottomInset - viewport.topInset) * perPoint,
            halfWidth: Float(viewport.size.width - viewport.leftInset - viewport.rightInset) * perPoint,
            halfHeight: Float(viewport.size.height - viewport.topInset - viewport.bottomInset) * perPoint
        )
    }

    /// Where `point` falls on the plane through the target that faces the camera, seen from the camera, along its
    /// right and up from the middle of the uncovered part; nil when it is behind the camera.
    private func projection(of point: SIMD3<Float>, window: (right: Float, up: Float, halfWidth: Float, halfHeight: Float)) -> SIMD2<Float>? {
        let fromEye = point - position
        let depth = -simd_dot(fromEye, rotation.act([0, 0, 1]))
        guard depth > Self.near else { return nil }
        let scale = distance / depth
        return SIMD2(simd_dot(fromEye, rotation.act([1, 0, 0])) * scale - window.right,
                     simd_dot(fromEye, rotation.act([0, 1, 0])) * scale - window.up)
    }

    /// How much room a point held in view keeps from the edges of the uncovered part: it stays within the part
    /// shrunk by this factor about its middle.
    static let holdingMargin: Float = 1.04

    /// Whether `point` is in the uncovered part of `viewport`, clear of its edges by `holdingMargin`.
    func holds(_ point: SIMD3<Float>, in viewport: Viewport) -> Bool {
        guard !viewport.isEmpty else { return false }
        let window = window(in: viewport)
        guard let spot = projection(of: point, window: window) else { return false }
        return abs(spot.x) * Self.holdingMargin <= window.halfWidth && abs(spot.y) * Self.holdingMargin <= window.halfHeight
    }

    /// The camera looking the same way, moved back and over just enough that the uncovered part of `viewport` holds
    /// all it holds now and `points` as well, clear of its edges by `holdingMargin`. It is this camera itself when
    /// `points` are already held, and it changes smoothly as they move.
    ///
    /// The part of the view seen now is kept whole, and the new view is centred on it and the points together, so the
    /// toy moves over only as far as the points ask.
    func holding(_ points: [SIMD3<Float>], in viewport: Viewport) -> OrbitCamera {
        guard !viewport.isEmpty else { return self }
        let window = window(in: viewport)
        var lower = SIMD2(-window.halfWidth, -window.halfHeight)
        var upper = -lower
        for point in points {
            // A point behind the camera cannot be brought into view by moving back along the same direction alone, but
            // the camera is far from the toy, so this does not happen.
            guard let spot = projection(of: point, window: window) else { continue }
            lower = simd_min(lower, spot * Self.holdingMargin)
            upper = simd_max(upper, spot * Self.holdingMargin)
        }
        let needed = (upper - lower) / SIMD2(2 * window.halfWidth, 2 * window.halfHeight)
        let scale = max(needed.x, needed.y)
        guard scale > 1.000_01 else { return self }
        let right = rotation.act([1, 0, 0]), up = rotation.act([0, 1, 0]), back = rotation.act([0, 0, 1])
        let middle = (lower + upper) / 2
        // The middle of the uncovered part, on the target's plane: kept on that plane, moved over to the new middle.
        let centre = target + right * (window.right + middle.x) + up * (window.up + middle.y)
        var camera = self
        camera.distance = distance * scale
        // Seen from the new place, a point nearer or farther than the target's plane may fall a little differently
        // than it did from here: move back further if one would still be cut.
        // The middle of the uncovered part is off the camera's axis by a share of the distance, which shifts how a
        // point nearer than the plane falls.
        let tangentX = window.halfWidth / distance, tangentY = window.halfHeight / distance
        let shareX = window.right / distance, shareY = window.up / distance
        for point in points {
            let offset = point - centre
            let toward = simd_dot(offset, back)
            camera.distance = max(camera.distance,
                                  abs(simd_dot(offset, right) + shareX * toward) * Self.holdingMargin / tangentX + toward,
                                  abs(simd_dot(offset, up) + shareY * toward) * Self.holdingMargin / tangentY + toward)
        }
        let grown = camera.distance / distance
        camera.target = centre - right * window.right * grown - up * window.up * grown
        return camera
    }

    // MARK: Blending

    /// The camera a fraction `t` of the way from this one to `other`, turning the short way round.
    func blended(to other: OrbitCamera, t: Float) -> OrbitCamera {
        var turn = (other.yaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
        return OrbitCamera(
            target: simd_mix(target, other.target, SIMD3(repeating: t)),
            yaw: yaw + turn * t,
            pitch: pitch + (other.pitch - pitch) * t,
            distance: distance * pow(other.distance / distance, t)
        )
    }
}
