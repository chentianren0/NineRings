import Foundation

/// A small random number generator with a seed, so that a search can be run again and give the same result
/// (SplitMix64).
struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number between 0 and 1.
    mutating func uniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// A number from the standard normal distribution (Box–Muller).
    mutating func normal() -> Double {
        let u = max(uniform(), 1e-300), v = uniform()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
