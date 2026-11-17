/// The rules the app's playback keeps about time, written here so that they can be tested: when the sword's speed is
/// still to be heard, when to try starting the audio engine again, and when a sound has waited too long to play.
public enum PlaybackRules {
    /// How long, in seconds, a speed set for the slide stays good. Frames set it many times a second; when they stop
    /// (a window closed or minimized while a move plays) the slide falls silent this soon, and the engine can idle.
    public static let speedLife = 0.25

    /// How long, in seconds, a request to play a sound may wait to be played before it is dropped as stale: after
    /// the engine failed to start, or the queue was held up, a sound that comes late is a wrong sound.
    public static let requestLife = 0.1

    /// The speed the slide hears, from a speed set `age` seconds ago: nothing once it is older than ``speedLife``.
    public static func slideSpeed(_ speed: Double, age: Double) -> Double {
        age >= 0 && age < speedLife && speed > 0 ? speed : 0
    }

    /// The speed the slide hears when several toys set one (one per window): the fastest that is still good.
    public static func slideSpeed(_ speeds: [(speed: Double, age: Double)]) -> Double {
        speeds.map { slideSpeed($0.speed, age: $0.age) }.max() ?? 0
    }

    /// Whether a request to play, made at `requested`, is still worth playing at `now` (seconds on one clock).
    public static func isFresh(requested: Double, now: Double) -> Bool {
        now - requested <= requestLife
    }
}

/// When to try starting the audio engine, after it has failed to start.
///
/// A start can fail for a while (a phone call holds the audio, the output device has gone). Trying again on every
/// frame would cost a round trip to the audio server each time and hold up the sounds behind it, so after a failure it
/// waits ``pause`` before trying again; and a second failure in a row asks for the engine to be built afresh, in case
/// what it was built for is gone.
public struct EngineStarts: Sendable, Equatable {
    /// How long, in seconds, to wait after a failed start.
    public static let pause = 1.0
    /// How many failures in a row ask for the engine to be built again.
    public static let failuresBeforeRebuild = 2

    /// The failures since the last start that worked.
    public private(set) var failures = 0
    private var lastFailure: Double?

    public init() {}

    /// Whether to try starting at `time`.
    public func mayTry(at time: Double) -> Bool {
        guard let lastFailure else { return true }
        return time - lastFailure >= Self.pause
    }

    /// A start failed at `time`. Returns whether the engine should be built afresh before the next try.
    public mutating func failed(at time: Double) -> Bool {
        failures += 1
        lastFailure = time
        guard failures >= Self.failuresBeforeRebuild else { return false }
        failures = 0
        return true
    }

    /// A start worked.
    public mutating func started() {
        failures = 0
        lastFailure = nil
    }
}
