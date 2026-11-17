import CoreGraphics
import Toy
import simd

/// Where a camera looks from: its turn about the vertical and its height, in radians, as `OrbitCamera` has them.
struct CameraAngles: Equatable {
    var yaw: Float
    var pitch: Float

    init(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = pitch
    }

    init(_ preset: CameraPreset) {
        (yaw, pitch) = preset.angles
    }

    /// Angles given in degrees.
    static func degrees(yaw: Float, pitch: Float) -> CameraAngles {
        CameraAngles(yaw: yaw * .pi / 180, pitch: pitch * .pi / 180)
    }
}

/// Holds the camera the 3D view draws from: gestures move it, presets fly it, and a change of view size
/// keeps the toy framed.
///
/// Until a gesture or a preset moves it, the camera shows the default view, which may depend on the shape of the
/// view (a tall one may be seen from higher up than a wide one): while it does, a change of size frames the toy
/// afresh from the default angles for the new shape, flying there when the angles change. Once moved, a change of
/// size only keeps the toy the same size.
///
/// With `followsMove` on, the camera drawn from is not always `camera` itself: while a move slides the sword, the
/// picture widens just enough to keep in view the part of the sword it shows at rest, wherever the sword has gone
/// (see `camera(for:)`). Gestures, presets and flights still move `camera`, the picture at rest.
///
/// The 3D view reads `camera(for:)` once a frame, after calling `advance(by:)`; nothing here is observed by SwiftUI.
@MainActor
final class CameraRig {
    private(set) var camera: OrbitCamera
    /// Goes up by one whenever `camera` changes, so a reader can skip frames where nothing moved.
    private(set) var revision = 0
    private(set) var viewport = Viewport(size: .zero)
    /// The default angles for a view of a given shape.
    var defaultAngles: (Viewport) -> CameraAngles
    /// Whether the camera shows the default view, unmoved by a gesture or a preset.
    private(set) var showsDefault = true
    /// A flight in progress, toward the given angles, or toward the default view for the present shape when nil.
    private var flight: (from: OrbitCamera, to: CameraAngles?, elapsed: Double)?
    private var hasBeenFramed = false
    /// The box the camera frames.
    private var box: ToyBounds
    /// Whether the picture follows the move, widening to keep the sword in view as it slides.
    var followsMove = false {
        didSet { if followsMove != oldValue { revision += 1 } }
    }
    /// The points of the sword, at home, that the picture at rest shows clear of its edges, worked out for a revision
    /// of `camera`.
    private var swordInView: (revision: Int, points: [SIMD3<Float>])?
    /// The camera last drawn from, so that a pan moves the toy as far as the finger in the picture as it is.
    private var shown: OrbitCamera?

    init(framing box: ToyBounds, defaultAngles: @escaping (Viewport) -> CameraAngles = { _ in CameraAngles(.side) }) {
        self.box = box
        self.defaultAngles = defaultAngles
        camera = OrbitCamera.framing(.side, of: box, in: viewport)
    }

    private static let flightDuration = 0.6

    /// Flies the camera to `preset`, framing `box`.
    func show(_ preset: CameraPreset, framing box: ToyBounds) {
        self.box = box
        fly(to: CameraAngles(preset))
        showsDefault = false
    }

    /// Flies the camera back to the default view for the present shape.
    func showDefault() {
        fly(to: nil)
        showsDefault = true
    }

    func resize(to newViewport: Viewport) {
        guard newViewport != viewport else { return }
        let old = viewport
        viewport = newViewport
        guard !newViewport.isEmpty else { return }
        if !hasBeenFramed {
            // The first size: nothing has been seen yet, so there is nothing to fly from.
            flight = nil
            camera = framing(showsDefault ? defaultAngles(newViewport) : CameraAngles(.side), in: newViewport)
        } else if flight == nil {
            if showsDefault {
                let angles = defaultAngles(newViewport)
                if !old.isEmpty, angles != defaultAngles(old) {
                    // The space has changed shape enough to want another view, as when a phone turns or a Duo
                    // opens: fly there rather than jump.
                    fly(to: nil)
                } else {
                    camera = framing(angles, in: newViewport)
                }
            } else {
                camera.refit(box, from: old, to: newViewport)
            }
        }
        // During a flight, its destination follows the new size.
        hasBeenFramed = true
        revision += 1
    }

    func orbit(by translation: CGSize) {
        change { $0.orbit(by: translation) }
    }

    func pan(by translation: CGSize) {
        let viewport = viewport
        // While following the move the picture may be wider than the camera's own: pan by what the finger sees.
        let widening = CGFloat((shown?.distance ?? camera.distance) / camera.distance)
        let seen = CGSize(width: translation.width * widening, height: translation.height * widening)
        change { $0.pan(by: seen, in: viewport) }
    }

    func zoom(by factor: CGFloat) {
        change { $0.zoom(by: factor) }
    }

    /// The camera to draw `pose` from: `camera` itself, or, following the move, `camera` moved back and over just
    /// enough to keep in view the part of the sword the picture shows at rest, slid and lowered as `pose` has it.
    ///
    /// It depends on the pose and on `camera` alone, so the same point of a move always gives the same picture,
    /// whether the move plays forward or back, is paused or is dragged; and with the sword at home it is `camera`.
    func camera(for pose: ToyPose) -> OrbitCamera {
        let offset = SIMD3<Float>(pose.swordOffset)
        guard followsMove, offset != .zero, !viewport.isEmpty else {
            shown = camera
            return camera
        }
        let held = swordPointsInView().map { $0 + offset }
        let following = camera.holding(held, in: viewport)
        shown = following
        return following
    }

    /// The sword's centreline at home, a point every millimetre or so, taken once.
    private static let swordPoints: [SIMD3<Float>] = {
        let points = SwordPath.points()
        guard var last = points.first else { return [] }
        var kept = [last]
        for point in points.dropFirst() where simd_distance(point, last) >= 1 {
            kept.append(point)
            last = point
        }
        return kept
    }()

    private func swordPointsInView() -> [SIMD3<Float>] {
        if let swordInView, swordInView.revision == revision { return swordInView.points }
        let points = Self.swordPoints.filter { camera.holds($0, in: viewport) }
        swordInView = (revision, points)
        return points
    }

    func advance(by seconds: Double) {
        guard var current = flight else { return }
        current.elapsed = min(current.elapsed + seconds, Self.flightDuration)
        let linear = Float(current.elapsed / Self.flightDuration)
        let destination = framing(current.to ?? defaultAngles(viewport), in: viewport)
        camera = current.from.blended(to: destination, t: linear * linear * (3 - 2 * linear))
        flight = current.elapsed < Self.flightDuration ? current : nil
        revision += 1
    }

    private func fly(to angles: CameraAngles?) {
        flight = (camera, angles, 0)
    }

    private func framing(_ angles: CameraAngles, in viewport: Viewport) -> OrbitCamera {
        OrbitCamera.framing(yaw: angles.yaw, pitch: angles.pitch, of: box, in: viewport)
    }

    /// A gesture takes over from any flight in progress.
    private func change(_ edit: (inout OrbitCamera) -> Void) {
        flight = nil
        showsDefault = false
        edit(&camera)
        revision += 1
    }
}
