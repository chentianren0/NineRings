import Toy
import simd

/// The sword's one wire as a single path, in millimetres in the sword's frame: from the end of one grip loop,
/// along one side of the neck and its rail, round the tip, back along the other side, to the end of the other
/// grip loop.
///
/// It is `SwordShape.wire` exactly, the same points the checker checks, so add nothing here: a change to the
/// sword's shape belongs in `SwordShape`, where the package's tests check that the drawn wire stays inside the
/// checked one.
enum SwordPath {
    static func points() -> [SIMD3<Float>] {
        SwordShape.wire.map { SIMD3<Float>($0) }
    }
}
