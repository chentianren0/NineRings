import Foundation

// The voices of the toy: every number of every sound, one small table per voice, so that they can be tuned by ear.
// Nothing here makes sound; `Synthesis` renders these tables into samples, the same on every run.

/// How the toy sounds: the voices' tables.
public enum Voices {
    /// The rate every voice is rendered at, in samples a second.
    public static let sampleRate = 48_000.0

    /// A ring struck: against the sword, or another ring. A small steel ring rings in its bending modes, which are
    /// not harmonic (see ``Tuning``); held on its rod and touching the sword, it is damped and short.
    public static let strike = RingVoice(
        partials: [
            Partial(mode: 2, level: 1.0, decay: 0.20),
            Partial(mode: 3, level: 0.45, decay: 0.10),
            Partial(mode: 4, level: 0.22, decay: 0.055),
            Partial(mode: 5, level: 0.10, decay: 0.032),
        ],
        attack: 0.0012,
        click: Click(level: 0.12, decay: 0.0015, cutoff: 7_000),
        fullness: 0.5,
        level: 0.32,
        length: 0.9,
        fade: 0.06
    )

    /// A ring coming to rest: on the sword, or hanging against the ring behind. Softer and lower than a strike: the
    /// ring's own modes, damped hard by what it settles on, over a dull thud.
    public static let rest = KnockVoice(
        partials: [
            Partial(mode: 2, level: 0.35, decay: 0.06),
            Partial(mode: 3, level: 0.12, decay: 0.03),
        ],
        thud: Thud(frequency: 260, level: 0.7, decay: 0.028),
        attack: 0.002,
        click: Click(level: 0.10, decay: 0.004, cutoff: 1_800),
        level: 0.22,
        length: 0.35,
        fade: 0.04
    )

    /// The sword coming home and stopping: a faint, low click.
    public static let swordHome = KnockVoice(
        partials: [],
        thud: Thud(frequency: 190, level: 0.6, decay: 0.035),
        attack: 0.002,
        click: Click(level: 0.25, decay: 0.003, cutoff: 1_200),
        level: 0.12,
        length: 0.25,
        fade: 0.04
    )

    /// A ring the rule will not let move, nudged against its rod: a dull, soft knock with no ring in it.
    public static let refusal = KnockVoice(
        partials: [],
        thud: Thud(frequency: 210, level: 0.8, decay: 0.022),
        attack: 0.003,
        click: Click(level: 0.08, decay: 0.003, cutoff: 900),
        level: 0.13,
        length: 0.2,
        fade: 0.04
    )

    /// The sword sliding: soft noise, filtered, as loud and as bright as the sword is fast.
    public static let slide = SlideVoice(
        level: 0.06,
        referenceSpeed: 150,
        lowCut: 500,
        cutoff: 1_400,
        cutoffPerSpeed: 9,
        highestCutoff: 6_000,
        smoothing: 0.03,
        gritRate: 70,
        gritDepth: 0.5
    )

    /// The pitches of the rings.
    public static let tuning = Tuning(
        transposition: 0.25,
        scale: [0, -2, -5, -7, -9, -12, -14, -17, -19]
    )

    /// The short phrase when every ring is off: the rings from 9 up to 2, one after another, and a chord of rings 5,
    /// 3 and 2, ringing longer.
    public static let solved = Phrase(
        notes: [
            Phrase.Note(time: 0.00, ring: 9, strength: 0.40),
            Phrase.Note(time: 0.08, ring: 8, strength: 0.42),
            Phrase.Note(time: 0.16, ring: 7, strength: 0.44),
            Phrase.Note(time: 0.24, ring: 6, strength: 0.46),
            Phrase.Note(time: 0.32, ring: 5, strength: 0.48),
            Phrase.Note(time: 0.40, ring: 4, strength: 0.50),
            Phrase.Note(time: 0.48, ring: 3, strength: 0.52),
            Phrase.Note(time: 0.56, ring: 2, strength: 0.55),
            Phrase.Note(time: 0.74, ring: 5, strength: 0.45, decayScale: 2.5),
            Phrase.Note(time: 0.74, ring: 3, strength: 0.45, decayScale: 2.5),
            Phrase.Note(time: 0.74, ring: 2, strength: 0.50, decayScale: 2.5),
        ],
        level: 0.8,
        length: 1.9,
        fade: 0.35
    )

    /// How repeats differ, so that 341 moves do not sound like one sample played 341 times.
    public static let variation = Variation(
        detuneCents: [0, 6, -4, 3, -7],
        decayScale: [1, 0.93, 1.07, 0.97, 1.04],
        tilt: [1, 1.12, 0.9, 1.05, 0.95]
    )
}

/// One bending mode of a ring.
public struct Partial: Sendable, Equatable {
    /// The in-plane bending mode, n = 2 for the lowest.
    public var mode: Int
    /// How loud, at the start.
    public var level: Double
    /// How fast it dies away: the time, in seconds, for it to fall to 1/e.
    public var decay: Double

    public init(mode: Int, level: Double, decay: Double) {
        self.mode = mode
        self.level = level
        self.decay = decay
    }

    /// Its frequency over the lowest mode's (see ``Tuning/modeRatio(_:)``).
    public var ratio: Double { Tuning.modeRatio(mode) }
}

/// A short burst of noise where two parts touch.
public struct Click: Sendable, Equatable {
    public var level: Double
    /// The time, in seconds, for it to fall to 1/e.
    public var decay: Double
    /// The frequency, in hertz, above which it is softened.
    public var cutoff: Double

    public init(level: Double, decay: Double, cutoff: Double) {
        self.level = level
        self.decay = decay
        self.cutoff = cutoff
    }
}

/// A low, dying tone: the body of a knock.
public struct Thud: Sendable, Equatable {
    public var frequency: Double
    public var level: Double
    public var decay: Double

    public init(frequency: Double, level: Double, decay: Double) {
        self.frequency = frequency
        self.level = level
        self.decay = decay
    }
}

/// A ring struck.
public struct RingVoice: Sendable, Equatable {
    public var partials: [Partial]
    /// How long, in seconds, the sound takes to rise from silence.
    public var attack: Double
    public var click: Click
    /// How much longer a lower ring rings: every decay is scaled by (highest pitch / pitch) to this power, so that
    /// ring 9, the lowest, is also the fullest.
    public var fullness: Double
    /// The loudness of the whole voice at full strength.
    public var level: Double
    /// The most it lasts, in seconds, for the highest ring; lower rings last longer by their fullness.
    public var length: Double
    /// How long, in seconds, it fades to silence at its end.
    public var fade: Double
}

/// A knock: a ring coming to rest, the sword stopping, a ring refused.
public struct KnockVoice: Sendable, Equatable {
    /// The ring's modes, at the ring's pitch, if any.
    public var partials: [Partial]
    public var thud: Thud
    public var attack: Double
    public var click: Click
    public var level: Double
    public var length: Double
    public var fade: Double
}

/// The sword sliding.
public struct SlideVoice: Sendable, Equatable {
    /// The loudness the noise approaches as the sword goes fast.
    public var level: Double
    /// The sword's speed, in millimetres a second, at which the noise is at 63 % of `level`.
    public var referenceSpeed: Double
    /// The frequency, in hertz, below which the noise is cut.
    public var lowCut: Double
    /// The frequency, in hertz, above which the noise is softened, when the sword barely moves, and how much it
    /// rises for each millimetre a second, up to `highestCutoff`: a faster slide is brighter.
    public var cutoff: Double
    public var cutoffPerSpeed: Double
    public var highestCutoff: Double
    /// How long, in seconds, the loudness takes to follow a change of speed, so that it never clicks.
    public var smoothing: Double
    /// The slide is uneven, as wire over wire is: its loudness wavers this many times a second, by this much.
    public var gritRate: Double
    public var gritDepth: Double
}

/// The pitches of the rings.
///
/// The ring's lowest in-plane bending mode, for wire thickness d and radius R to the wire's centre line, is
/// f = (1/2π) · k₂ · (d / 4R²) · √(E/ρ), where kₙ = n(n²−1)/√(n²+1). For the toy's steel rings that is about
/// 7.6 kHz, which puts the upper partials past hearing and sounds thin; every pitch is brought down by
/// `transposition`, which keeps the ratios of the modes, the ring's character.
public struct Tuning: Sendable, Equatable {
    /// The speed of sound in steel, √(E/ρ), in metres a second.
    public static let steelWaveSpeed = 5_100.0

    /// What every pitch is multiplied by: 1/4 is two octaves down.
    public var transposition: Double
    /// With a note per ring, each ring's pitch in semitones from ring 1's, which is the one note: a five-note scale
    /// going down, ring 1 the highest and lightest, ring 9 the lowest and fullest.
    public var scale: [Double]

    /// The factor kₙ = n(n²−1)/√(n²+1) of the in-plane bending mode n.
    public static func modeFactor(_ mode: Int) -> Double {
        let n = Double(mode)
        return n * (n * n - 1) / (n * n + 1).squareRoot()
    }

    /// Mode n's frequency over the lowest mode's: about 1, 2.83, 5.42 and 8.77 for n = 2 to 5.
    public static func modeRatio(_ mode: Int) -> Double {
        modeFactor(mode) / modeFactor(2)
    }

    /// The lowest bending mode of the toy's ring, in hertz, from its sizes.
    public static var lowestMode: Double {
        let thickness = 2 * Dimensions.Ring.wireRadius / 1000, radius = Dimensions.Ring.radius / 1000
        return modeFactor(2) / (2 * .pi) * thickness / (4 * radius * radius) * steelWaveSpeed
    }

    /// The one note: every ring alike, as rings of one size are.
    public var oneNote: Double { Self.lowestMode * transposition }

    /// Ring `ring`'s pitch with a note per ring.
    public func pitch(ring: Int) -> Double {
        oneNote * pow(2, scale[ring - 1] / 12)
    }

    /// Ring `ring`'s pitch, with one note for every ring or a note per ring.
    public func pitch(ring: Int, notePerRing: Bool) -> Double {
        notePerRing ? pitch(ring: ring) : oneNote
    }
}

/// A short phrase played on the rings.
public struct Phrase: Sendable, Equatable {
    public struct Note: Sendable, Equatable {
        /// When it starts, in seconds from the phrase's start.
        public var time: Double
        public var ring: Int
        public var strength: Double
        /// How much longer than a strike it rings.
        public var decayScale: Double

        public init(time: Double, ring: Int, strength: Double, decayScale: Double = 1) {
            self.time = time
            self.ring = ring
            self.strength = strength
            self.decayScale = decayScale
        }
    }

    public var notes: [Note]
    public var level: Double
    public var length: Double
    public var fade: Double
}

/// The small differences between one sounding of a voice and the next, chosen by a written rule (see
/// ``variant(moveNumber:eventIndex:)``), never at random.
public struct Variation: Sendable, Equatable {
    /// Each variant's pitch, in cents from the voice's.
    public var detuneCents: [Double]
    /// Each variant's decays, as a factor.
    public var decayScale: [Double]
    /// Each variant's balance of upper modes to the lowest: mode n's level is multiplied by this to the power n − 2.
    public var tilt: [Double]

    /// How many variants there are.
    public var count: Int { detuneCents.count }

    /// The variant for the event at `eventIndex` of a move's score, in the move numbered `moveNumber` in the session.
    ///
    /// Ring k moves every 2^k moves of the shortest solution. The count of variants is odd (five), so stepping by any
    /// power of two goes through every variant before repeating, and each ring's repeats all differ in turn.
    public func variant(moveNumber: Int, eventIndex: Int) -> Int {
        ((moveNumber + 3 * eventIndex) % count + count) % count
    }
}
