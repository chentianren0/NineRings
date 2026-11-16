import Foundation

/// One number of the motion as a smooth function of the move's progress, written as values at a few progress
/// values ("keys").
///
/// Between keys the curve is a cubic with matching slopes at every key, so the value and its rate of change are
/// continuous. The slopes are chosen so that the curve never overshoots: between two keys it stays between
/// their values, and where the values turn back, or at the first and last key, the slope is zero. Before the
/// first key and after the last the value stays put.
public struct Curve: Sendable {
    public struct Key: Sendable {
        public var progress: Double
        public var value: Double

        public init(_ progress: Double, _ value: Double) {
            self.progress = progress
            self.value = value
        }
    }

    public let keys: [Key]
    private let slopes: [Double]

    public init(_ keys: [Key]) {
        precondition(!keys.isEmpty, "a curve needs at least one key")
        precondition(zip(keys, keys.dropFirst()).allSatisfy { $0.progress < $1.progress }, "keys must be in order")
        self.keys = keys
        slopes = Self.monotoneSlopes(keys)
    }

    /// A curve that holds one value throughout.
    public init(constant value: Double) {
        self.init([Key(0, value)])
    }

    public func value(at progress: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if progress <= first.progress { return first.value }
        if progress >= last.progress { return last.value }
        // Few keys: a straight search is as quick as any.
        var index = 0
        while keys[index + 1].progress < progress { index += 1 }
        let a = keys[index], b = keys[index + 1]
        let width = b.progress - a.progress
        let t = (progress - a.progress) / width
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * a.value
            + (t3 - 2 * t2 + t) * width * slopes[index]
            + (-2 * t3 + 3 * t2) * b.value
            + (t3 - t2) * width * slopes[index + 1]
    }

    /// The Fritsch–Carlson slopes: zero at the ends and where the values turn back, otherwise a blend of the two
    /// neighbouring gradients, limited so that no piece overshoots.
    private static func monotoneSlopes(_ keys: [Key]) -> [Double] {
        let count = keys.count
        guard count > 1 else { return [0] }
        let gradients = (0..<(count - 1)).map { index in
            (keys[index + 1].value - keys[index].value) / (keys[index + 1].progress - keys[index].progress)
        }
        var slopes = [Double](repeating: 0, count: count)
        for index in 1..<(count - 1) {
            let before = gradients[index - 1], after = gradients[index]
            guard before * after > 0 else { continue }
            // The weighted harmonic mean keeps the slope within what both neighbours allow.
            let widthBefore = keys[index].progress - keys[index - 1].progress
            let widthAfter = keys[index + 1].progress - keys[index].progress
            let weightBefore = 2 * widthAfter + widthBefore
            let weightAfter = widthAfter + 2 * widthBefore
            slopes[index] = (weightBefore + weightAfter) / (weightBefore / before + weightAfter / after)
        }
        return slopes
    }
}
