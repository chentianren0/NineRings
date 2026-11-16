import Foundation
import Toy
import simd

/// A ring as its rod holds it: where the eye is, and which way the ring lies from there.
///
/// The eye's centre is a point of the ring's centreline, so the ring's wire runs through the middle of the eye.
/// From that point the ring's middle lies one radius away along ``towardCenter``, and the wire runs on through
/// the eye along ``alongWire``. These two directions are at right angles, and together they give the ring's
/// plane.
public struct HeldRing: Sendable, Equatable {
    /// The centre of the eye, which is also a point of the ring's centreline.
    public var eye: SIMD3<Double>
    /// Unit vector from the eye to the ring's middle.
    public var towardCenter: SIMD3<Double>
    /// Unit vector along the ring's wire where it runs through the eye.
    public var alongWire: SIMD3<Double>

    public init(eye: SIMD3<Double>, towardCenter: SIMD3<Double>, alongWire: SIMD3<Double>) {
        self.eye = eye
        self.towardCenter = simd_normalize(towardCenter)
        // Keep exactly at right angles, whatever rounding the caller's directions carry.
        let along = alongWire - simd_dot(alongWire, self.towardCenter) * self.towardCenter
        self.alongWire = simd_normalize(along)
    }

    /// The ring's pose. In the ring's local frame (see ``Dimensions/Ring``) the eye is at local (0, radius, 0),
    /// where the wire runs along local x.
    public var ringPose: PartPose {
        let x = alongWire
        let y = -towardCenter
        let z = simd_cross(x, y)
        let rotation = simd_quatd(simd_double3x3(columns: (x, y, z)))
        return PartPose(position: eye + Dimensions.Ring.radius * towardCenter, orientation: simd_normalize(rotation))
    }

    /// The rod's pose, by the rod rule.
    ///
    /// A rod is straight. Its eye is where the ring holds it, and its shaft runs through the middle of its hole in
    /// the bar, so the rod points from the eye to the hole. The rod may turn about its own axis: it turns so that
    /// the eye faces along the ring's wire as nearly as it can, which lets the wire run through the eye.
    public func rodPose(hole: SIMD3<Double>) -> PartPose {
        let down = simd_normalize(hole - eye)
        let y = -down
        let facing = alongWire - simd_dot(alongWire, y) * y
        precondition(simd_length(facing) > 1e-6, "the ring's wire runs along its rod, so the eye cannot face it")
        let z = simd_normalize(facing)
        let x = simd_cross(y, z)
        let rotation = simd_quatd(simd_double3x3(columns: (x, y, z)))
        return PartPose(position: eye, orientation: simd_normalize(rotation))
    }

    /// The angle between the ring's wire and the way the eye faces. The wire can run through the eye without
    /// touching it only while this stays well below a right angle.
    public func wireAngleInEye(hole: SIMD3<Double>) -> Double {
        let facing = rodPose(hole: hole).worldDirection(SIMD3(0, 0, 1))
        return acos(min(1, abs(simd_dot(facing, alongWire))))
    }
}
