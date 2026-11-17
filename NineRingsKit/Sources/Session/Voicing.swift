import Motion
import Toy

/// Which sound an event is heard with: the voice, the pitch and the variant (see ``Voices``).
///
/// Every sound is rendered once and kept, so a voicing is also the key it is kept under. With one note, every ring
/// sounds alike, so the ring is left out of the key; with a note per ring, each ring has its own pitch.
public struct Voicing: Hashable, Sendable {
    public enum Voice: String, Hashable, Sendable, CaseIterable {
        case strike, rest, swordHome, refusal, solved
    }

    public let voice: Voice
    /// The ring whose pitch it has, or 0 when it has the one note or no pitch.
    public let ring: Int
    public let variant: Int

    public init(voice: Voice, ring: Int = 0, variant: Int = 0) {
        self.voice = voice
        self.ring = ring
        self.variant = variant
    }

    /// The voicing of an event heard, with one note for every ring or a note per ring.
    public init(_ heard: Hearing.Heard, notePerRing: Bool) {
        let variant = Voices.variation.variant(moveNumber: heard.moveNumber, eventIndex: heard.index)
        switch heard.event.kind {
        case .strike: self.init(voice: .strike, ring: notePerRing ? heard.event.ring : 0, variant: variant)
        case .rest: self.init(voice: .rest, ring: notePerRing ? heard.event.ring : 0, variant: variant)
        case .swordHome: self.init(voice: .swordHome, variant: variant)
        }
    }

    public static let refusal = Voicing(voice: .refusal)
    public static let solved = Voicing(voice: .solved)

    /// Its pitch, in hertz.
    public var pitch: Double {
        ring == 0 ? Voices.tuning.oneNote : Voices.tuning.pitch(ring: ring)
    }

    /// Its samples at full strength (see ``Synthesis``): the same on every run.
    public func render() -> [Float] {
        switch voice {
        case .strike: Synthesis.strike(pitch: pitch, variant: variant)
        case .rest: Synthesis.knock(Voices.rest, pitch: pitch, variant: variant)
        case .swordHome: Synthesis.knock(Voices.swordHome, variant: variant)
        case .refusal: Synthesis.knock(Voices.refusal)
        case .solved: Synthesis.phrase()
        }
    }

    /// Every voicing a session can sound, with one note or a note per ring.
    public static func all(notePerRing: Bool) -> [Voicing] {
        let rings = notePerRing ? Array(1...9) : [0]
        let variants = 0..<Voices.variation.count
        return rings.flatMap { ring in variants.flatMap { variant in
            [Voicing(voice: .strike, ring: ring, variant: variant), Voicing(voice: .rest, ring: ring, variant: variant)]
        } } + variants.map { Voicing(voice: .swordHome, variant: $0) } + [.refusal, .solved]
    }
}
