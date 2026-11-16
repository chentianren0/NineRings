import Foundation
import simd

/// The rings that hang, one from the next, below a ring that moves: the rule that carries them along.
///
/// When a ring that is on steps aside, whatever hangs from it has to go with it: the next ring off hangs with its
/// eye in the moving ring's bowl, and any further rings off hang from that one in turn. The rule is that the whole
/// hanging chain moves as one piece with the ring it hangs from:
///
/// - Every ring of the chain keeps its pose relative to the moving ring, as it rests: it is carried round the
///   moving ring's eye just as the moving ring turns, so each still hangs from the next exactly as it did at rest.
/// - Each rod follows by the rod rule: it slides up or down in its hole and leans to reach its eye.
///
/// Nothing in the rule knows how many rings hang: a chain of one is ring 1 hanging from ring 2, a chain of two is
/// ring 2 hanging from ring 3 with ring 1 hanging from ring 2.
struct HangingChain: Sendable {
    /// The moving ring as it rests, before it moves.
    let carrierAtRest: HeldRing
    /// The hanging rings as they rest, the one that hangs from the moving ring first.
    let chainAtRest: [HeldRing]

    /// The hanging rings when the moving ring is held as `carrier`, in the same order as ``chainAtRest``.
    func chain(carriedBy carrier: HeldRing) -> [HeldRing] {
        let before = carrierAtRest.ringPose, after = carrier.ringPose
        let turn = after.orientation * before.orientation.inverse
        return chainAtRest.map { ring in
            HeldRing(
                eye: after.position + turn.act(ring.eye - before.position),
                towardCenter: turn.act(ring.towardCenter),
                alongWire: turn.act(ring.alongWire)
            )
        }
    }
}
