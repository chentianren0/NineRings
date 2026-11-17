import Foundation

/// Renders the voices' tables (see ``Voices``) into samples: mono, at ``Voices/sampleRate``, from −1 to 1.
///
/// Rendering is deterministic: the same voice, pitch and variant give the same samples, bit for bit, on every run,
/// so each is rendered once and kept. Every sound starts at exactly zero, rises over its attack, and fades to exactly
/// zero at its end, so that it can be cut in and out without a click. A strike at full strength peaks well under 1,
/// so that several at once stay clear of clipping.
public enum Synthesis {
    /// A ring struck at full strength, at `pitch` hertz.
    public static func strike(pitch: Double, variant: Int = 0, decayScale: Double = 1, voice: RingVoice = Voices.strike) -> [Float] {
        let fullness = pow(Voices.tuning.pitch(ring: 1) / pitch, voice.fullness)
        let decays = fullness * decayScale * Voices.variation.decayScale[variant]
        var samples = [Double](repeating: 0, count: Int(voice.length * fullness * decayScale * Voices.sampleRate))
        addModes(voice.partials, pitch: detuned(pitch, variant), variant: variant, decayScale: decays, attack: voice.attack, into: &samples)
        addClick(voice.click, attack: voice.attack, seed: UInt64(variant) + 1, into: &samples)
        return finish(samples, level: voice.level, fade: voice.fade)
    }

    /// A knock at full strength: a ring coming to rest at `pitch` hertz, the sword stopping, a ring refused.
    public static func knock(_ voice: KnockVoice, pitch: Double = Voices.tuning.oneNote, variant: Int = 0) -> [Float] {
        let scale = Voices.variation.decayScale[variant]
        var samples = [Double](repeating: 0, count: Int(voice.length * Voices.sampleRate))
        addModes(voice.partials, pitch: detuned(pitch, variant), variant: variant, decayScale: scale, attack: voice.attack, into: &samples)
        let thud = voice.thud
        addTone(
            frequency: detuned(thud.frequency, variant), level: thud.level, decay: thud.decay * scale, attack: voice.attack,
            into: &samples
        )
        addClick(voice.click, attack: voice.attack, seed: UInt64(variant) + 101, into: &samples)
        return finish(samples, level: voice.level, fade: voice.fade)
    }

    /// The phrase when every ring is off, on the rings' own pitches.
    public static func phrase(_ phrase: Phrase = Voices.solved) -> [Float] {
        var samples = [Double](repeating: 0, count: Int(phrase.length * Voices.sampleRate))
        for (index, note) in phrase.notes.enumerated() {
            let variant = index % Voices.variation.count
            let strike = Self.strike(pitch: Voices.tuning.pitch(ring: note.ring), variant: variant, decayScale: note.decayScale)
            let start = Int(note.time * Voices.sampleRate)
            for (offset, sample) in strike.enumerated() where start + offset < samples.count {
                samples[start + offset] += Double(sample) * note.strength
            }
        }
        return finish(samples, level: phrase.level, fade: phrase.fade)
    }

    // MARK: - Parts

    /// A pitch moved by a variant's detune.
    static func detuned(_ pitch: Double, _ variant: Int) -> Double {
        pitch * pow(2, Voices.variation.detuneCents[variant] / 1200)
    }

    /// How a sound rises from silence: zero at the start, one after `attack` seconds.
    static func rise(_ time: Double, attack: Double) -> Double {
        guard time < attack else { return 1 }
        let phase = sin(.pi / 2 * time / attack)
        return phase * phase
    }

    /// The ring's modes, each dying away at its own rate. Modes too high to be rendered are left out.
    static func addModes(
        _ partials: [Partial], pitch: Double, variant: Int, decayScale: Double, attack: Double, into samples: inout [Double]
    ) {
        let tilt = Voices.variation.tilt[variant]
        for partial in partials {
            let level = partial.level * pow(tilt, Double(partial.mode - 2))
            addTone(frequency: pitch * partial.ratio, level: level, decay: partial.decay * decayScale, attack: attack, into: &samples)
        }
    }

    /// A sine at `frequency`, starting at zero phase, rising over `attack` and dying away with time constant `decay`.
    static func addTone(frequency: Double, level: Double, decay: Double, attack: Double, into samples: inout [Double]) {
        guard frequency < 0.45 * Voices.sampleRate else { return }
        let step = 2 * Double.pi * frequency / Voices.sampleRate
        for index in samples.indices {
            let time = Double(index) / Voices.sampleRate
            let envelope = level * exp(-time / decay) * rise(time, attack: attack)
            if envelope < 1e-7 && time > attack { break }
            samples[index] += envelope * sin(step * Double(index))
        }
    }

    /// A burst of noise where the parts touch, softened above the click's cutoff.
    static func addClick(_ click: Click, attack: Double, seed: UInt64, into samples: inout [Double]) {
        var noise = Noise(seed: seed)
        let smoothing = exp(-2 * Double.pi * click.cutoff / Voices.sampleRate)
        var low = 0.0
        for index in samples.indices {
            let time = Double(index) / Voices.sampleRate
            let envelope = click.level * exp(-time / click.decay) * rise(time, attack: attack)
            if envelope < 1e-7 && time > attack { break }
            low = smoothing * low + (1 - smoothing) * noise.next()
            samples[index] += envelope * low
        }
    }

    /// The samples scaled to `level`, faded to zero over the last `fade` seconds, as 32-bit floats.
    static func finish(_ samples: [Double], level: Double, fade: Double) -> [Float] {
        let fadeCount = max(1, min(samples.count - 1, Int(fade * Voices.sampleRate)))
        let last = samples.count - 1
        return samples.indices.map { index in
            var value = samples[index] * level
            let fromEnd = last - index
            if fromEnd < fadeCount {
                let phase = sin(.pi / 2 * Double(fromEnd) / Double(fadeCount))
                value *= phase * phase
            }
            return index == 0 || index == last ? 0 : Float(value)
        }
    }
}

/// White noise from −1 to 1 from a written rule (xorshift), the same on every run for the same seed.
public struct Noise: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    public mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 52) - 1
    }
}

/// The sword's slide as it happens: soft noise, filtered, whose loudness and brightness follow the sword's speed.
///
/// Unlike the other voices it cannot be rendered once, because it follows the sword however the move is played:
/// at any speed, paused, or dragged either way. It is rendered as it plays, a sample at a time, from the speed the
/// player reads off the score (see `Score.swordTravel`); the same speeds give the same samples on every run.
public struct SlideNoise: Sendable {
    public let voice: SlideVoice
    private var noise = Noise(seed: 7)
    private var grit = Noise(seed: 11)
    private var gain = 0.0
    private var gritLevel = 0.0, gritTarget = 0.0, gritCountdown = 0
    private var high = 0.0, lastInput = 0.0, low1 = 0.0, low2 = 0.0
    private var speed = -1.0, lowSmoothing = 0.0
    private let highSmoothing: Double, gainSmoothing: Double, gritPeriod: Int, gritSmoothing: Double

    public init(voice: SlideVoice = Voices.slide) {
        self.voice = voice
        highSmoothing = exp(-2 * Double.pi * voice.lowCut / Voices.sampleRate)
        gainSmoothing = exp(-1 / (voice.smoothing * Voices.sampleRate))
        gritPeriod = max(1, Int(Voices.sampleRate / voice.gritRate))
        gritSmoothing = exp(-voice.gritRate * 4 / Voices.sampleRate)
    }

    /// The next sample, with the sword moving at `speed` millimetres a second.
    public mutating func next(speed newSpeed: Double) -> Float {
        if newSpeed != speed {
            speed = newSpeed
            let cutoff = min(voice.cutoff + voice.cutoffPerSpeed * max(speed, 0), voice.highestCutoff)
            lowSmoothing = exp(-2 * Double.pi * cutoff / Voices.sampleRate)
        }
        let target = voice.level * (1 - exp(-max(speed, 0) / voice.referenceSpeed))
        gain = gainSmoothing * gain + (1 - gainSmoothing) * target
        if gain < 1e-6 && target == 0 {
            gain = 0
            return 0
        }
        if gritCountdown <= 0 {
            gritTarget = abs(grit.next())
            gritCountdown = gritPeriod
        }
        gritCountdown -= 1
        gritLevel = gritSmoothing * gritLevel + (1 - gritSmoothing) * gritTarget
        let input = noise.next()
        // Cut the lows (a one-pole high-pass), then soften the highs twice (two one-pole low-passes).
        high = highSmoothing * (high + input - lastInput)
        lastInput = input
        low1 = lowSmoothing * low1 + (1 - lowSmoothing) * high
        low2 = lowSmoothing * low2 + (1 - lowSmoothing) * low1
        let waver = 1 - voice.gritDepth + voice.gritDepth * 2 * gritLevel
        return Float(low2 * gain * waver * 3)
    }

    /// The slide over a whole stretch, one speed for each sample: what the player would hear.
    public static func render(speeds: [Double], voice: SlideVoice = Voices.slide) -> [Float] {
        var slide = SlideNoise(voice: voice)
        return speeds.map { slide.next(speed: $0) }
    }
}
