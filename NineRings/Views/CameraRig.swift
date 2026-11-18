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
/// size only keeps the toy the same size. Where the space changes by a step, as when the lesson's panel arrives, the
/// framing eases into the new space with the screen's change (`ScreenMotion.framing`); a window resized by hand is
/// followed frame by frame.
///
/// With `followsMove` on, the camera drawn from is not always `camera` itself: while a move slides the sword, the
/// picture widens to keep the sword in view, wherever it has gone (see `camera(for:)`). Gestures, presets and flights
/// still move `camera`, the picture at rest.
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
    /// A flight in progress, toward the given angles, or toward the default view for the present shape when nil, over
    /// `duration` seconds.
    private var flight: (from: OrbitCamera, to: CameraAngles?, elapsed: Double, duration: Double)?
    private var hasBeenFramed = false
    /// A flight toward this camera rather than toward angles: back to one kept by `remember()`.
    private var flightCamera: OrbitCamera?
    /// The camera as it was when `remember()` kept it, whether it showed the default view, and the view's size then.
    private var remembered: (camera: OrbitCamera, showsDefault: Bool, viewport: Viewport)?
    /// The box the camera frames.
    private var box: ToyBounds
    /// Whether flights cut to where they go rather than fly there, as Reduce Motion asks: the camera moves at once, on
    /// the next frame, wherever a flight would have taken it.
    var reducesMotion = false
    /// Whether the picture follows the move, widening to keep the sword in view as it slides.
    var followsMove = false {
        didSet { if followsMove != oldValue { revision += 1 } }
    }
    /// The points of the sword, at home, that the picture at rest shows clear of its edges, worked out for a revision
    /// of `camera`.
    private var swordInView: (revision: Int, points: [SIMD3<Float>])?
    /// The camera last drawn from, so that a pan moves the toy as far as the finger in the picture as it is.
    private var shown: OrbitCamera?
    /// Following the move, the picture easing from where it was drawn before a jump to where it follows the toy now,
    /// over the jump's fade.
    private var jumpEase: (from: OrbitCamera, elapsed: Double, duration: Double)?

    init(framing box: ToyBounds, defaultAngles: @escaping (Viewport) -> CameraAngles = { _ in CameraAngles(.side) }) {
        self.box = box
        self.defaultAngles = defaultAngles
        camera = OrbitCamera.framing(.side, of: box, in: viewport)
    }

    private static var flightDuration: Double { ScreenMotion.flight }

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
        let wasFlying = flight != nil
        // A space that changes by a step eases the framing into it, where the change would otherwise be seen as a jump.
        let eases = !old.isEmpty && newViewport.differsByAStep(from: old)
        let easing = ScreenMotion.framing(reducesMotion: reducesMotion)
        if !hasBeenFramed {
            // The first size: nothing has been seen yet, so there is nothing to fly from.
            flight = nil
            camera = framing(showsDefault ? defaultAngles(newViewport) : CameraAngles(.side), in: newViewport)
        } else if !wasFlying {
            if showsDefault {
                let angles = defaultAngles(newViewport)
                if !old.isEmpty, angles != defaultAngles(old) {
                    // The space has changed shape enough to want another view, as when a phone turns or a Duo
                    // opens: fly there rather than jump.
                    fly(to: nil)
                } else if eases {
                    fly(to: nil, duration: easing)
                } else {
                    camera = framing(angles, in: newViewport)
                }
            } else {
                var refitted = camera
                refitted.refit(box, from: old, to: newViewport)
                if eases {
                    flight = (camera, nil, 0, easing)
                    flightCamera = refitted
                } else {
                    camera = refitted
                }
            }
        }
        // During a flight, its destination follows the new size; a camera flown back to is kept the same size too. Where
        // the size changes by a step, the flight starts again from where the camera is, so that the destination's step
        // is eased rather than seen.
        if wasFlying, !old.isEmpty {
            flightCamera?.refit(box, from: old, to: newViewport)
            if eases, let current = flight {
                flight = (camera, current.to, 0, max(easing, current.duration - current.elapsed))
            }
        }
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

    /// The camera to draw `pose` from: `camera` itself, or, following the move, `camera` moved back and over to keep
    /// the sword in view where `pose` has slid and lowered it.
    ///
    /// The picture at rest may cut the sword's grip at its edge. As the sword starts to slide, the picture holds the
    /// part of the sword it shows at rest; over the first `wholeSwordSlide` of the slide it comes to hold the whole
    /// sword, so that in a far move the grip is in view wherever the edge cut it at rest.
    ///
    /// It depends on the pose and on `camera` alone, so the same point of a move always gives the same picture,
    /// whether the move plays forward or back, is paused or is dragged; and with the sword at home it is `camera`. Only
    /// across a jump does it ease, over the jump's fade, from the picture drawn before (see `toyJumped(fadingOver:)`).
    func camera(for pose: ToyPose) -> OrbitCamera {
        let following = followingCamera(for: pose)
        guard let ease = jumpEase else {
            shown = following
            return following
        }
        let linear = ease.duration > 0 ? Float(min(ease.elapsed / ease.duration, 1)) : 1
        let eased = ease.from.blended(to: following, t: linear * linear * (3 - 2 * linear))
        shown = eased
        return eased
    }

    /// The toy has jumped to another arrangement, its parts fading across over `duration` seconds. Following the move
    /// the picture depends on the pose, so it eases from where it was drawn to where it follows the toy now, rather than
    /// cut; otherwise nothing changes.
    func toyJumped(fadingOver duration: Double) {
        guard followsMove, let shown, duration > 0 else { return }
        jumpEase = (shown, 0, duration)
        revision += 1
    }

    private func followingCamera(for pose: ToyPose) -> OrbitCamera {
        let offset = SIMD3<Float>(pose.swordOffset)
        guard followsMove, offset != .zero, !viewport.isEmpty else {
            return camera
        }
        var following = camera.holding(swordPointsInView().map { $0 + offset }, in: viewport)
        let reach = min(abs(offset.x) / Self.wholeSwordSlide, 1)
        if reach > 0 {
            let whole = camera.holding(Self.swordPoints.map { $0 + offset }, in: viewport)
            following = following.blended(to: whole, t: reach * reach * (3 - 2 * reach))
        }
        return following
    }

    /// How far the sword slides, in millimetres, before the picture holds the whole of it: four holes. Ring 1's move
    /// slides it about 12 mm and ring 2's about 24, so near moves change the picture little; ring 5's slides it about
    /// 69 and ring 9's about 129.
    private static let wholeSwordSlide: Float = 60

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
        if var ease = jumpEase {
            ease.elapsed += seconds
            jumpEase = ease.elapsed < ease.duration ? ease : nil
            revision += 1
        }
        guard var current = flight else { return }
        let duration = reducesMotion ? 0 : current.duration
        current.elapsed = min(current.elapsed + seconds, duration)
        let linear = duration > 0 ? Float(current.elapsed / duration) : 1
        let destination = flightCamera ?? framing(current.to ?? defaultAngles(viewport), in: viewport)
        camera = current.from.blended(to: destination, t: linear * linear * (3 - 2 * linear))
        flight = current.elapsed < duration ? current : nil
        if flight == nil { flightCamera = nil }
        revision += 1
    }

    private func fly(to angles: CameraAngles?, duration: Double = flightDuration) {
        flight = (camera, angles, 0, duration)
        flightCamera = nil
    }

    /// Keeps the camera as it is now, so that `flyBack()` can return to it, as the lesson does when it closes.
    func remember() {
        remembered = (camera, showsDefault, viewport)
    }

    /// Flies back to the camera kept by `remember()`: to the default view if it showed that, or else to where it was,
    /// kept the same size for the view's size now.
    func flyBack() {
        guard let remembered else { return }
        self.remembered = nil
        if remembered.showsDefault {
            showDefault()
            return
        }
        var destination = remembered.camera
        if !remembered.viewport.isEmpty, !viewport.isEmpty {
            destination.refit(box, from: remembered.viewport, to: viewport)
        }
        flight = (camera, nil, 0, Self.flightDuration)
        flightCamera = destination
        showsDefault = false
    }

    private func framing(_ angles: CameraAngles, in viewport: Viewport) -> OrbitCamera {
        OrbitCamera.framing(yaw: angles.yaw, pitch: angles.pitch, of: box, in: viewport)
    }

    /// A gesture takes over from any flight in progress.
    private func change(_ edit: (inout OrbitCamera) -> Void) {
        flight = nil
        flightCamera = nil
        showsDefault = false
        edit(&camera)
        revision += 1
    }
}
