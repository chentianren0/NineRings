import Foundation
@testable import Motion
import Toy

/// The poses of a move's moving parts as points of a few numbers, the same numbers its curves write: for ring 1's
/// drop the ring's tip, tilt, swing and eye height. A path planner searches these points; a fit turns the path it
/// finds into curve keys.
struct ConfigSpace: Sendable {
    /// The curves' names, one per number.
    var names: [String]
    /// How much of each number makes one unit of distance: 10° of an angle weighs as 1 mm of the eye's height.
    var scales: [Double]
    var lower: [Double]
    var upper: [Double]
    var room: FastRoom
    /// The toy with the moving parts at a point.
    var pose: @Sendable ([Double]) -> ToyPose
    /// The largest step, in units, between two points checked along an edge.
    var resolution = 0.05
    /// Which part each number belongs to, such as ring 1, ring 2 or the sword. A part whose numbers are the same
    /// at both ends of a leg is first held still there (see ``Planner/plan``). Empty: every number its own part.
    var parts: [Int] = []

    /// A move for the tuner made of one curve per number of this space, through keys such as `CurveFit` writes:
    /// every key free but the first and last, and every value kept inside the space's ranges.
    func keyedMove(span: ClosedRange<Double>, keys: KeyedMove.Keys) -> KeyedMove {
        let names = names, pose = pose
        return KeyedMove(
            channels: names.indices.map { index in
                let count = keys[names[index]]!.count
                let interior = (0..<count).map { $0 != 0 && $0 != count - 1 }
                return KeyedMove.Channel(name: names[index], freeProgress: interior, freeValue: interior, valueStep: 0.8 * scales[index])
            },
            span: span,
            room: room,
            bounds: Dictionary(uniqueKeysWithValues: names.indices.map { (names[$0], lower[$0]...upper[$0]) }),
            path: { keys in
                let curves = names.map { Curve(keys[$0]!.map { Curve.Key($0.0, $0.1) }) }
                return { parameter in pose(curves.map { $0.value(at: parameter) }) }
            }
        )
    }

    /// This space with the parts that are the same at `start` and `goal` held where they are.
    func holdingStill(between start: [Double], and goal: [Double]) -> (ConfigSpace, held: [String]) {
        let parts = parts.isEmpty ? Array(names.indices) : parts
        var space = self
        var held: [String] = []
        for part in Set(parts) {
            let numbers = names.indices.filter { parts[$0] == part }
            guard numbers.allSatisfy({ abs(start[$0] - goal[$0]) < 1e-9 }) else { continue }
            for index in numbers {
                (space.lower[index], space.upper[index]) = (start[index], start[index])
                held.append(names[index])
            }
        }
        return (space, held)
    }

    var dimension: Int { names.count }

    func distance(_ a: [Double], _ b: [Double]) -> Double {
        var total = 0.0
        for i in a.indices {
            let d = (a[i] - b[i]) / scales[i]
            total += d * d
        }
        return total.squareRoot()
    }

    /// The room at a point: the fast room's value, below zero when a relation fails.
    func clearance(_ q: [Double]) -> Double {
        room.room(pose(q)).value
    }

    /// Whether the straight edge from `a` to `b` keeps at least `need` everywhere it is checked, and no ring
    /// leaves or joins the rails away from the tip end along it. The points of a longer edge are checked side by
    /// side, one per core.
    func edgeIsClear(_ a: [Double], _ b: [Double], need: Double) -> Bool {
        let steps = max(1, Int((distance(a, b) / resolution).rounded(.up)))
        let rings = room.swordMoves ? Array(1...9) : room.moving
        let space = self
        // For each point: whether it keeps the room, and which rings go round the rails there.
        let points = (0...steps).map { step in a.indices.map { a[$0] + Double(step) / Double(steps) * (b[$0] - a[$0]) } }
        let checks = Sweep.inParallel(points.count) { index -> (Bool, [Bool]) in
            let pose = space.pose(points[index])
            let clear = index == 0 || space.room.room(pose).value >= need
            return (clear, rings.map { Relations.isRoundTheRails($0, in: pose) })
        }
        guard checks.allSatisfy(\.0) else { return false }
        for index in 1..<checks.count where checks[index].1 != checks[index - 1].1 {
            if !room.railChanges(from: pose(points[index - 1]), to: pose(points[index])).isEmpty { return false }
        }
        return true
    }
}

/// Finds a way between two points of a configuration space that keeps a given room everywhere: bidirectional
/// RRT-Connect (Kuffner and LaValle, 2000).
///
/// Two trees grow, one from each end. Each round draws a random point, grows one tree a step toward it, then
/// grows the other tree straight toward the new point for as long as the way is clear; when they meet, the path
/// is found. Then the trees swap roles. Random points let it find its way through spaces a grid is too coarse
/// for, and growing straight toward the other tree makes it quick when the way is open. A path found is then
/// shortened by trying straight edges between points of it.
enum Planner {
    struct Result {
        var path: [[Double]]
        var need: Double
        var nodes: Int
        var seconds: Double
    }

    /// Tries each room in `needs`, largest first, until a path is found.
    static func plan(
        _ space: ConfigSpace, from start: [Double], to goal: [Double], needs: [Double],
        step: Double = 0.5, nodes: Int = 20000, seconds: Double = .infinity, seed: UInt64 = 1, log: (String) -> Void = { print($0); fflush(stdout) }
    ) -> Result? {
        log(String(format: "room at the start %.3f, at the goal %.3f", space.clearance(start), space.clearance(goal)))
        // The simplest way first: parts that need not move in this leg stay still, unless no way is found so.
        let (still, held) = space.holdingStill(between: start, and: goal)
        if !held.isEmpty {
            log("holding still: \(held.joined(separator: ", "))")
            if let result = plan(still, from: start, to: goal, needs: needs.filter { $0 >= 0.2 }, step: step, nodes: nodes,
                                 seconds: seconds, seed: seed, simplestFirst: false, log: log) {
                return result
            }
            log("nothing found holding them still; freeing every part")
        }
        return plan(space, from: start, to: goal, needs: needs, step: step, nodes: nodes, seconds: seconds, seed: seed, simplestFirst: false, log: log)
    }

    private static func plan(
        _ space: ConfigSpace, from start: [Double], to goal: [Double], needs: [Double],
        step: Double, nodes: Int, seconds: Double, seed: UInt64, simplestFirst: Bool, log: (String) -> Void
    ) -> Result? {
        let clock = DispatchTime.now().uptimeNanoseconds
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - clock) / 1e9 }
        for need in needs {
            var random = SeededRandom(seed: seed)
            let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(min(seconds, 1e6) * 1e9)
            if let (path, count) = connect(space, start, goal, need: need, step: step, nodes: nodes, deadline: deadline, random: &random) {
                log(String(format: "%6.1f s  path with room %.2f found: %d points, %d nodes", elapsed(), need, path.count, count))
                let short = shortcut(space, path, need: need, tries: 600, random: &random)
                log(String(format: "%6.1f s  shortened to %d points", elapsed(), short.count))
                return Result(path: short, need: need, nodes: count, seconds: elapsed())
            }
            log(String(format: "%6.1f s  no path with room %.2f in %d nodes or %.0f s", elapsed(), need, nodes, seconds))
        }
        return nil
    }

    private struct Tree {
        var points: [[Double]]
        var parents: [Int]

        func nearest(to q: [Double], in space: ConfigSpace) -> Int {
            var best = 0, bestDistance = Double.infinity
            for (index, point) in points.enumerated() {
                let d = space.distance(point, q)
                if d < bestDistance { (best, bestDistance) = (index, d) }
            }
            return best
        }

        func pathToRoot(from index: Int) -> [[Double]] {
            var path: [[Double]] = []
            var cursor = index
            while cursor >= 0 {
                path.append(points[cursor])
                cursor = parents[cursor]
            }
            return path
        }
    }

    private enum Growth { case trapped, advanced(Int), reached(Int) }

    private static func extend(_ tree: inout Tree, toward q: [Double], _ space: ConfigSpace, need: Double, step: Double) -> Growth {
        let near = tree.nearest(to: q, in: space)
        let from = tree.points[near]
        let d = space.distance(from, q)
        let reaches = d <= step
        let target = reaches ? q : from.indices.map { from[$0] + (q[$0] - from[$0]) * step / d }
        guard space.edgeIsClear(from, target, need: need) else { return .trapped }
        tree.points.append(target)
        tree.parents.append(near)
        return reaches ? .reached(tree.points.count - 1) : .advanced(tree.points.count - 1)
    }

    private static func connect(
        _ space: ConfigSpace, _ start: [Double], _ goal: [Double], need: Double, step: Double, nodes: Int,
        deadline: UInt64, random: inout SeededRandom
    ) -> ([[Double]], Int)? {
        var a = Tree(points: [start], parents: [-1])
        var b = Tree(points: [goal], parents: [-1])
        var aIsStart = true
        while a.points.count + b.points.count < nodes && DispatchTime.now().uptimeNanoseconds < deadline {
            let sample = (0..<space.dimension).map { space.lower[$0] + random.uniform() * (space.upper[$0] - space.lower[$0]) }
            if case .trapped = extend(&a, toward: sample, space, need: need, step: step) {} else {
                let newIndex = a.points.count - 1
                let newPoint = a.points[newIndex]
                // Grow the other tree straight toward the new point while it can.
                while true {
                    let growth = extend(&b, toward: newPoint, space, need: need, step: step)
                    if case .reached(let bIndex) = growth {
                        let fromA = a.pathToRoot(from: newIndex).reversed()
                        let fromB = b.pathToRoot(from: bIndex).dropFirst()
                        let path = Array(fromA) + Array(fromB)
                        return (aIsStart ? path : path.reversed(), a.points.count + b.points.count)
                    }
                    if case .trapped = growth { break }
                }
            }
            swap(&a, &b)
            aIsStart.toggle()
        }
        return nil
    }

    /// Replaces stretches of the path by straight edges where those are clear.
    static func shortcut(_ space: ConfigSpace, _ path: [[Double]], need: Double, tries: Int, random: inout SeededRandom) -> [[Double]] {
        var path = path
        for _ in 0..<tries where path.count > 2 {
            let i = Int(random.uniform() * Double(path.count))
            let j = Int(random.uniform() * Double(path.count))
            let (low, high) = (min(i, j), max(i, j))
            guard high - low > 1, space.edgeIsClear(path[low], path[high], need: need) else { continue }
            path.removeSubrange((low + 1)..<high)
        }
        return path
    }
}

/// Turns a path of points into curve keys.
///
/// The path's places along the move run from the start of `span` to its end in proportion to the distance along
/// the path. For each number, the fewest keys are kept such that straight lines through them stay within
/// `tolerance` of the path (the Douglas–Peucker simplification); the curves then pass through those keys.
enum CurveFit {
    static func keys(_ path: [[Double]], space: ConfigSpace, span: ClosedRange<Double>, tolerance: Double = 0.15, samples: Int = 400) -> KeyedMove.Keys {
        keys(legs: [(path, span)], space: space, tolerance: tolerance, samples: samples)
    }

    /// Keys for several paths one after another, each over its own span of the move.
    static func keys(legs: [([[Double]], ClosedRange<Double>)], space: ConfigSpace, tolerance: Double = 0.15, samples: Int = 400) -> KeyedMove.Keys {
        var dense: [(Double, [Double])] = []
        for (index, (path, span)) in legs.enumerated() {
            let points = evenly(path, space: space, span: span, samples: samples)
            dense += index == 0 ? points : Array(points.dropFirst())
        }
        var keys: KeyedMove.Keys = [:]
        for (channel, name) in space.names.enumerated() {
            let points = dense.map { ($0.0, $0.1[channel]) }
            let kept = simplify(points, tolerance: tolerance * space.scales[channel])
            keys[name] = kept.map { (($0.0 * 10000).rounded() / 10000, ($0.1 * 1000).rounded() / 1000) }
        }
        return keys
    }

    /// The path at even steps of distance along it, each point with its place in `span`.
    static func evenly(_ path: [[Double]], space: ConfigSpace, span: ClosedRange<Double>, samples: Int) -> [(Double, [Double])] {
        guard path.count > 1 else { return [(span.lowerBound, path[0]), (span.upperBound, path[0])] }
        var lengths = [0.0]
        for (a, b) in zip(path, path.dropFirst()) { lengths.append(lengths.last! + space.distance(a, b)) }
        let total = max(lengths.last!, 1e-12)
        var dense: [(Double, [Double])] = []
        var segment = 0
        for index in 0...samples {
            let along = total * Double(index) / Double(samples)
            while segment < path.count - 2 && lengths[segment + 1] < along { segment += 1 }
            let width = max(lengths[segment + 1] - lengths[segment], 1e-12)
            let t = min(max((along - lengths[segment]) / width, 0), 1)
            let q = path[segment].indices.map { path[segment][$0] + t * (path[segment + 1][$0] - path[segment][$0]) }
            dense.append((span.lowerBound + (span.upperBound - span.lowerBound) * Double(index) / Double(samples), q))
        }
        return dense
    }

    /// The Douglas–Peucker simplification of a curve given as (place, value) points, by the value's error.
    static func simplify(_ points: [(Double, Double)], tolerance: Double) -> [(Double, Double)] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            let (p0, v0) = points[first], (p1, v1) = points[last]
            var worst = first, worstError = 0.0
            for index in (first + 1)..<last {
                let line = v0 + (v1 - v0) * (points[index].0 - p0) / (p1 - p0)
                let error = abs(points[index].1 - line)
                if error > worstError { (worst, worstError) = (index, error) }
            }
            if worstError > tolerance {
                keep[worst] = true
                stack.append((first, worst))
                stack.append((worst, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
