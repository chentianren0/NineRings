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
final class Haptics {
    #if os(iOS)
    /// Whether this device can play haptics.
    static let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?

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

    func stop() {
        engine?.stop(completionHandler: nil)
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
        guard Self.isSupported, let engine = ready() else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // A haptic that cannot play is simply not felt.
        }
    }

    /// The engine, made on first use. It starts and stops itself: on a player's request, and when idle.
    private func ready() -> CHHapticEngine? {
        if let engine { return engine }
        guard let engine = try? CHHapticEngine() else { return nil }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        engine.start(completionHandler: nil)
        self.engine = engine
        return engine
    }
    #else
    static let isSupported = false
    func play(_ event: Score.Event) {}
    func refused() {}
    func solved() {}
    func stop() {}
    #endif
}
