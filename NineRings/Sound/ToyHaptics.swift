import Foundation
import Motion
#if os(iOS)
import CoreHaptics
#endif

/// The toy felt, on an iPhone: the same events that are heard, as taps that follow the sound.
///
/// A ring striking the sword is a light, sharp tap; a ring coming to rest a softer one; a ring the rule refuses a
/// short "no" of two dull taps; the puzzle solved a fuller pattern under its phrase. Core Haptics plays them, so that
/// each pattern can follow its sound. Where the device has no haptics (an iPad, a Mac, the simulator) nothing
/// happens and nothing fails.
@MainActor
final class ToyHaptics {
    #if os(iOS)
    /// Whether this device can play haptics.
    static let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    /// Whether the engine has to be started before the next pattern: at first, and after it stopped from outside (the
    /// app suspended, a phone call, a server reset), when Core Haptics asks the app to start it again.
    private var needsStart = true
    private var isStarting = false
    /// The pattern waiting for the engine to start: the latest only, so that a slow start never plays a burst.
    private var waiting: CHHapticPattern?

    /// Makes the engine and starts it, ahead of the first haptic.
    func prepare() {
        guard Self.isSupported, let engine = ready() else { return }
        start(engine)
    }

    /// One event of a move. The sword coming home is not felt.
    func play(_ event: Score.Event) {
        switch event.kind {
        case .strike: play([tap(at: 0, intensity: 0.35 + 0.5 * event.strength, sharpness: 0.75)])
        case .rest: play([tap(at: 0, intensity: 0.25 + 0.4 * event.strength, sharpness: 0.25)])
        case .swordHome: break
        }
    }

    /// A ring the rule will not let move: "no".
    func refused() {
        play([tap(at: 0, intensity: 0.55, sharpness: 0.15), tap(at: 0.1, intensity: 0.4, sharpness: 0.1)])
    }

    /// Every ring off: taps rising under the phrase's run, and a fuller one with a short swell under its chord.
    func solved() {
        var events = (0..<8).map { tap(at: 0.25 + 0.08 * Double($0), intensity: 0.25 + 0.04 * Double($0), sharpness: 0.5) }
        events.append(tap(at: 0.99, intensity: 0.9, sharpness: 0.6))
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ],
            relativeTime: 0.99, duration: 0.45
        ))
        let fade = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: 0.45, value: 0)],
            relativeTime: 0.99
        )
        play(events, curves: [fade])
    }

    private func tap(at time: Double, intensity: Double, sharpness: Double) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(intensity, 1))),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
            ],
            relativeTime: time
        )
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard Self.isSupported, let engine = ready(),
              let pattern = try? CHHapticPattern(events: events, parameterCurves: curves) else { return }
        if needsStart {
            waiting = pattern
            start(engine)
            return
        }
        do {
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // The engine stopped before its stopped handler reached here: start it, and play this once it runs.
            needsStart = true
            waiting = pattern
            start(engine)
        }
    }

    /// Starts the engine, without waiting for it, then plays the pattern waiting, if any.
    private func start(_ engine: CHHapticEngine) {
        guard !isStarting else { return }
        isStarting = true
        engine.start { @Sendable [weak self] error in
            let started = error == nil
            Task { @MainActor in self?.didStart(started) }
        }
    }

    private func didStart(_ started: Bool) {
        isStarting = false
        let pattern = waiting
        waiting = nil
        guard started else { return }
        needsStart = false
        if let pattern { try? engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate) }
    }

    /// The engine, made on first use. Idle, it stops itself; stopped from outside or reset, it is started again on the
    /// next haptic. Its handlers run on Core Haptics' own queue, so they only hop to the main actor.
    private func ready() -> CHHapticEngine? {
        if let engine { return engine }
        guard let engine = try? CHHapticEngine() else { return nil }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { @Sendable [weak self] _ in
            Task { @MainActor in self?.needsStart = true }
        }
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.needsStart = true }
        }
        self.engine = engine
        return engine
    }
    #else
    static let isSupported = false
    func play(_ event: Score.Event) {}
    func refused() {}
    func solved() {}
    func prepare() {}
    #endif
}
