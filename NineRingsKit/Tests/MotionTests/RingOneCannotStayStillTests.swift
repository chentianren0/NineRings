import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

/// Why ring 1 cannot simply stay where it is while ring 2 comes off: with ring 1 at rest, the sword cannot be drawn
/// back far enough for its tip to pass out of ring 1. Ring 1 is off only once the sword is drawn back 28.74 mm, and
/// two things stop it well before that. From about 10 mm, the tip end, which rises toward its end, comes up under
/// ring 1's wire just outside the rails beside the eye. And from about 28.7 mm the tip end runs into eye 1, which
/// faces along ring 1's wire, across the sword, and so lies along the sword, reaching 3.75 mm toward the tip from
/// rod 1. Turning ring 1 about its eye, as ring 2's move does, clears both.
@Suite struct RingOneCannotStayStillTests {
    @Test func theSwordCannotBeDrawnOutOfRingOneAtRest() {
        let atRest = PuzzleState.rings.map(RestPoses.on)
        func pose(_ slide: Double) -> ToyPose { RestPoses.pose(holding: atRest, swordSlide: slide) }
        func clear(_ slide: Double) -> Bool {
            let shapes = pose(slide).shapes.filter { $0.name != .bar }
            return (Gaps.smallest(in: shapes, involving: [.ring(1), .eye(1), .shaft(1)])?.distance ?? 10) >= smallestAllowedGap
        }
        // The furthest the sword can be drawn back with ring 1 at rest and clear of it.
        var furthest = 0.0
        while clear(furthest + 0.01) { furthest += 0.01 }
        let off = stride(from: 0.0, through: 32, by: 0.01).first { !Relations.isRoundTheRails(1, in: pose($0)) }
        for slide in [furthest + 0.01, 12, 15, 18, 21, 24, 27, 28.8] {
            let shapes = pose(slide).shapes.filter { $0.name != .bar }
            print("ring 1 at rest, slide \(slide): \(Gaps.smallest(in: shapes, involving: [.ring(1), .eye(1), .shaft(1)])!)")
        }
        print("ring 1 at rest: the sword can be drawn back \(String(format: "%.2f", furthest)) mm; ring 1 would be off the rails from \(off.map { String(format: "%.2f", $0) } ?? "never") mm")
        #expect(Relations.isRoundTheRails(1, in: pose(furthest)))
        if let off { #expect(off > furthest) }
    }
}
