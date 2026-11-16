import Foundation
import simd

/// The rings that hang, one from the next, below the ring that steps aside: the rule that carries them along.
///
/// At rest every ring that is off hangs the same way, whatever it hangs from (see ``RestPoses/hanging(_:)``): its
/// rod upright, its eye just below the rails above its own hole, leaning toward the tip. So a chain of hanging rings
/// is a row of parallel rings, like plates leaning on one another, each with its eye in the bowl of the ring
/// behind it.
///
/// When the ring in front of a moving ring steps aside, the first ring that hangs from it is carried with it as one
/// piece while it starts to swing up (see ``carried(_:restingOn:now:)``), and then goes over to a path of its own,
/// which ends with its rod upright and the ring lifted clear above, drooping toward the tip. Every deeper ring keeps its place relative to that first ring: the rest of the
/// chain rises and falls with it, straight up and down, as one piece, every rod upright. A deeper rod has slid
/// further down at rest than the first, so it has the room to rise as far.
enum HangingChain {
    /// The first hanging ring carried with the ring it hangs from as one piece: it keeps the pose relative to that
    /// ring that it has at rest, so the two cannot cut into each other while that ring starts to swing up.
    static func carried(_ ring: HeldRing, restingOn carrierAtRest: HeldRing, now carrier: HeldRing) -> HeldRing {
        let before = carrierAtRest.ringPose, after = carrier.ringPose
        let turn = after.orientation * before.orientation.inverse
        return HeldRing(
            eye: after.position + turn.act(ring.eye - before.position),
            towardCenter: turn.act(ring.towardCenter),
            alongWire: turn.act(ring.alongWire)
        )
    }

    /// A ring part way, `fraction`, from one way of being held to another: its eye moved in a straight line, and
    /// the ring turned about it the shorter way round.
    static func blend(_ from: HeldRing, _ to: HeldRing, _ fraction: Double) -> HeldRing {
        let a = from.ringPose.orientation, b = to.ringPose.orientation
        let turn = simd_slerp(a, simd_dot(a.vector, b.vector) < 0 ? -b : b, fraction)
        return HeldRing(
            eye: from.eye + (to.eye - from.eye) * fraction,
            towardCenter: -turn.act(SIMD3(0, 1, 0)),
            alongWire: turn.act(SIMD3(1, 0, 0))
        )
    }

    /// The rings hanging below ring `first`, the next lower ring first, when ring `first`'s eye is at `eyeHeight`.
    static func below(_ first: Int, eyeHeight: Double) -> [HeldRing] {
        let rise = SIMD3(0, eyeHeight - Layout.eyeHeightHanging, 0)
        return stride(from: first - 1, through: 1, by: -1).map { ring in
            let rest = RestPoses.hanging(ring)
            return HeldRing(eye: rest.eye + rise, towardCenter: rest.towardCenter, alongWire: rest.alongWire)
        }
    }
}
