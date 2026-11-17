import CoreGraphics
import Motion
import Puzzle

/// How the camera frames the toy.
enum Framing {
    /// The box the camera frames: the rings, rods, beads and bar, and the sword's tip end. The picture stays still
    /// while moves play; when the sword is drawn far back, its grip may leave the picture.
    ///
    /// It is measured over ring 1's and ring 2's moves from every ring on, ring 3's from where it first comes off,
    /// and ring 3's with every ring behind it off, whose beads go lowest as the sword takes them down.
    static let rings: ToyBounds = {
        let moves = [
            Move(ring: 1, from: .allOn),
            Move(ring: 2, from: .allOn),
            Move(ring: 3, from: PuzzleState(bits: 0b1_1111_1110)),
            Move(ring: 3, from: PuzzleState(bits: 0b110)),
        ].compactMap { $0 }
        let poses = moves.map(MoveMotion.init).flatMap { motion in
            (0...40).map { motion.pose(at: Double($0) / 40) }
        }
        return ToyBounds.rings(poses)
    }()

    /// The box around the whole toy, the sword drawn back included, over the moves of the first three rings, each from
    /// where it first comes off, and ring 3's with every ring behind it off. The capture mode frames its pictures on it.
    static let wholeToy: ToyBounds = {
        let moves = Array(Player.moves.prefix(3)) + [Move(ring: 3, from: PuzzleState(bits: 0b110))].compactMap { $0 }
        let poses = moves.map(MoveMotion.init).flatMap { motion in
            (0...40).map { motion.pose(at: Double($0) / 40) }
        }
        return ToyBounds(poses)
    }()

    /// The setting, kept under this key, that makes the picture follow the move: off at first, the picture stays still;
    /// on, it widens while a move slides the sword, to keep in view the part of the sword it shows at rest. A launch
    /// argument such as `-settings.followsMove YES` sets it.
    static let followsMoveKey = "settings.followsMove"

    /// The shadow's height, just under the lowest the toy goes.
    static var floor: Float { rings.lower.y - 6 }

    /// A space narrower than this, for its height, is tall.
    static let tallAspectRatio: CGFloat = 0.9

    /// The default view: from the side, unless the space is tall, where `tallView` says.
    static func defaultAngles(tallView: TallViewDesign) -> (Viewport) -> CameraAngles {
        { viewport in
            viewport.aspectRatio < tallAspectRatio ? tallView.angles : CameraAngles(.side)
        }
    }
}
