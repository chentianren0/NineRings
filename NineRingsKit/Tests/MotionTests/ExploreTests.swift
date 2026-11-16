import Foundation
import Motion
import Puzzle
import Testing
import Toy
import simd

/// Maps where ring 1 can be, with its eye at a given height over its hole and every other ring on, for working
/// out the drop by hand. Run with `NINE_RINGS_EXPLORE=1`.
@Suite struct ExploreTests {
    struct Config: Hashable { var height: Int; var azimuth: Int; var elevation: Int; var roll: Int }

    static let heights: [Double] = [-9.45, -9.0, -8.5, -8.0, -7.0, -6.0, -5.0, -4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.5]
    static let step = Double(ProcessInfo.processInfo.environment["NINE_RINGS_STEP"] ?? "10")!

    static func held(_ config: Config) -> HeldRing {
        let degree = Double.pi / 180
        let azimuth = Double(config.azimuth) * step * degree
        let elevation = Double(config.elevation) * step * degree
        let roll = Double(config.roll) * step * degree
        // Azimuth 0 points toward the tip, 90 toward +z.
        let center = SIMD3(-cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth))
        var reference = simd_cross(center, SIMD3(0, 1, 0))
        if simd_length(reference) < 1e-6 { reference = SIMD3(0, 0, 1) }
        reference = simd_normalize(reference)
        let wire = simd_quatd(angle: roll, axis: center).act(reference)
        return HeldRing(eye: SIMD3(Layout.hole(1).x, heights[config.height], 0), towardCenter: center, alongWire: wire)
    }

    static func margin(_ config: Config) -> Double {
        let held = held(config)
        let down = simd_normalize(Layout.hole(1) - held.eye)
        if asin(min(1, abs(simd_dot(held.alongWire, down)))) > 55 * Double.pi / 180 { return -10 }
        var rings = PuzzleState.rings.map(RestPoses.on)
        rings[0] = held
        let pose = ToyPose(
            rings: rings.map(\.ringPose),
            rods: zip(PuzzleState.rings, rings).map { $1.rodPose(hole: Layout.hole($0)) },
            bar: Layout.bar, swordSlide: 0
        )
        let (near, far) = Relations.swordCrossings(of: 1, in: pose)
        if !near.isEmpty || !far.isEmpty { return -20 }
        if Relations.areLinked(pose.ring(1).circle, pose.ring(2).circle) { return -30 }
        let gap = Gaps.smallest(in: pose.shapes, involving: [.ring(1), .eye(1), .shaft(1), .bead(1)])
        return min((gap?.distance ?? 10) - 0.2, 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_EXPLORE"] != nil))
    func mapAndPlan() {
        let azimuths = Int(360 / Self.step), elevations = Int(90 / Self.step), rolls = Int(180 / Self.step)
        var configs: [Config] = []
        for height in Self.heights.indices {
            for azimuth in 0..<azimuths {
                for elevation in -elevations...elevations {
                    for roll in 0..<rolls {
                        configs.append(Config(height: height, azimuth: azimuth, elevation: elevation, roll: roll))
                    }
                }
            }
        }
        let list = configs
        let margins = Sweep.inParallel(list.count) { Self.margin(list[$0]) }
        var free: [Config: Double] = [:]
        for (config, margin) in zip(list, margins) where margin >= 0 { free[config] = margin }
        for height in Self.heights.indices {
            print("height \(Self.heights[height]): \(free.keys.filter { $0.height == height }.count) free of \(azimuths * (2 * elevations + 1) * rolls)")
        }
        // Start: eye at the top, ring standing on it along the sword. Goal: eye low, ring hanging across, leaning
        // 60 degrees toward the tip.
        let top = Self.heights.count - 1
        let start = Config(height: top, azimuth: 0, elevation: elevations, roll: 0)
        let goals = free.keys.filter { $0.height == 0 && $0.azimuth == 0 && $0.elevation == -3 }
        print("start free: \(free[start] != nil); goal candidates: \(goals.map { "roll \($0.roll) margin \(free[$0]!)" })")
        // The path whose tightest point has the most room (a widest-path search).
        let goal = Config(height: 0, azimuth: 0, elevation: -Int(30 / Self.step), roll: 0)
        print("goal free: \(free[goal] != nil)")
        var best: [Config: Double] = [start: .infinity]
        var previous: [Config: Config] = [:]
        var heap = Heap()
        heap.push(.infinity, start)
        var done: Set<Config> = []
        while let (width, config) = heap.pop() {
            if done.contains(config) { continue }
            done.insert(config)
            if config == goal { break }
            for neighbour in neighbours(config, azimuths: azimuths, elevations: elevations, rolls: rolls) {
                guard let room = free[neighbour], !done.contains(neighbour) else { continue }
                let through = min(width, room)
                if through > best[neighbour] ?? -1 {
                    best[neighbour] = through
                    previous[neighbour] = config
                    heap.push(through, neighbour)
                }
            }
        }
        guard previous[goal] != nil else { print("no path"); return }
        let floor = best[goal]! - 1e-9
        print("widest path: tightest room \(best[goal]!)")
        // The shortest path that keeps that much room everywhere.
        var back: [Config: Config] = [start: start]
        var frontier = [start]
        while !frontier.isEmpty && back[goal] == nil {
            var next: [Config] = []
            for config in frontier {
                for neighbour in neighbours(config, azimuths: azimuths, elevations: elevations, rolls: rolls) where back[neighbour] == nil && (free[neighbour] ?? -1) >= floor {
                    back[neighbour] = config
                    next.append(neighbour)
                }
            }
            frontier = next
        }
        var path = [goal]
        while let last = path.last, last != start, let before = back[last] { path.append(before) }
        print("shortest such path: \(path.count) steps")
        var last = -1.0
        for (index, config) in path.reversed().enumerated() {
            let held = Self.held(config)
            guard index % 3 == 0 || Self.heights[config.height] != last || free[config]! < 0.2 else { continue }
            last = Self.heights[config.height]
            let v = held.towardCenter, t = held.alongWire
            print(String(format: "eye %6.2f  V (%5.2f %5.2f %5.2f)  T (%5.2f %5.2f %5.2f)  room %.3f", Self.heights[config.height], v.x, v.y, v.z, t.x, t.y, t.z, free[config]!))
        }
    }

    struct Heap {
        var items: [(Double, Config)] = []
        mutating func push(_ key: Double, _ value: Config) {
            items.append((key, value))
            var index = items.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard items[parent].0 < items[index].0 else { break }
                items.swapAt(parent, index)
                index = parent
            }
        }
        mutating func pop() -> (Double, Config)? {
            guard !items.isEmpty else { return nil }
            items.swapAt(0, items.count - 1)
            let top = items.removeLast()
            var index = 0
            while true {
                let left = 2 * index + 1, right = left + 1
                var largest = index
                if left < items.count && items[left].0 > items[largest].0 { largest = left }
                if right < items.count && items[right].0 > items[largest].0 { largest = right }
                guard largest != index else { break }
                items.swapAt(largest, index)
                index = largest
            }
            return top
        }
    }

    func describe(_ config: Config, _ margin: Double) {
        print("  eye \(Self.heights[config.height]) azimuth \(Double(config.azimuth) * Self.step) elevation \(Double(config.elevation) * Self.step) roll \(Double(config.roll) * Self.step) margin \(String(format: "%.2f", margin))")
    }

    func neighbours(_ c: Config, azimuths: Int, elevations: Int, rolls: Int) -> [Config] {
        var list: [Config] = []
        for delta in [-1, 1] {
            if Self.heights.indices.contains(c.height + delta) { list.append(Config(height: c.height + delta, azimuth: c.azimuth, elevation: c.elevation, roll: c.roll)) }
            list.append(Config(height: c.height, azimuth: (c.azimuth + delta + azimuths) % azimuths, elevation: c.elevation, roll: c.roll))
            if abs(c.elevation + delta) <= elevations { list.append(Config(height: c.height, azimuth: c.azimuth, elevation: c.elevation + delta, roll: c.roll)) }
            list.append(Config(height: c.height, azimuth: c.azimuth, elevation: c.elevation, roll: (c.roll + delta + rolls) % rolls))
        }
        return list
    }
}
