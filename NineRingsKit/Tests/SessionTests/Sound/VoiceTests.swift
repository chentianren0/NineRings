import Foundation
import Motion
import Puzzle
@testable import Session
import Testing
import Toy

/// The voices, by numbers: what can be checked without hearing them.
@Suite struct VoiceTests {
    static let every = Voicing.all(notePerRing: true) + Voicing.all(notePerRing: false)

    @Test func theSameOnEveryRun() {
        for voicing in Self.every {
            #expect(voicing.render() == voicing.render(), "\(voicing)")
        }
        let speeds = (0..<48_000).map { Double($0 % 9_000) / 30 }
        #expect(SlideNoise.render(speeds: speeds) == SlideNoise.render(speeds: speeds))
    }

    /// Each starts and ends at exactly zero, holds nothing but numbers, and peaks well under full scale.
    @Test func cleanAndQuiet() {
        for voicing in Self.every {
            let samples = voicing.render()
            #expect(samples.count > 1000)
            #expect(samples.first == 0 && samples.last == 0, "\(voicing)")
            let finite = samples.allSatisfy { $0.isFinite }
            #expect(finite)
            let peak = samples.map(abs).max() ?? 0
            #expect(peak > 0.01 && peak < (voicing.voice == .solved ? 0.8 : 0.6), "\(voicing): peak \(peak)")
        }
    }

    /// The ring's lowest mode, from its sizes, is a few kilohertz, and its modes go as n(n²−1)/√(n²+1).
    @Test func pitchesFromTheRing() {
        #expect(Tuning.lowestMode > 7_000 && Tuning.lowestMode < 8_200, "\(Tuning.lowestMode) Hz")
        let ratios = (2...5).map { Tuning.modeRatio($0) }
        for (ratio, expected) in zip(ratios, [1, 2.83, 5.42, 8.77]) {
            #expect(abs(ratio - expected) < 0.01)
        }
        let tuning = Voices.tuning
        #expect(abs(tuning.oneNote - Tuning.lowestMode / 4) < 1e-9)
        #expect(tuning.pitch(ring: 1) == tuning.oneNote)
        let pitches = PuzzleState.rings.map { tuning.pitch(ring: $0) }
        #expect(zip(pitches, pitches.dropFirst()).allSatisfy { $0 > $1 }, "ring 1 highest, ring 9 lowest")
        print("pitches: lowest mode \(Int(Tuning.lowestMode)) Hz; one note \(Int(tuning.oneNote)) Hz; rings " + pitches.map { "\(Int($0))" }.joined(separator: ", "))
    }

    /// A strike has its partials where its table says: each is louder than the spectrum a little either side of it.
    @Test func partialsWhereTheTableSays() {
        for ring in [0, 1, 5, 9] {
            let voicing = Voicing(voice: .strike, ring: ring)
            let samples = voicing.render()
            for partial in Voices.strike.partials {
                let frequency = voicing.pitch * partial.ratio
                guard frequency < 0.45 * Voices.sampleRate else { continue }
                let at = Self.magnitude(samples, frequency)
                for off in [0.96, 1.04] {
                    #expect(at > 4 * Self.magnitude(samples, frequency * off), "ring \(ring) mode \(partial.mode) at \(Int(frequency)) Hz")
                }
            }
        }
        // A knock's body is its thud.
        let rest = Voicing(voice: .rest).render()
        let thud = Voices.rest.thud.frequency
        #expect(Self.magnitude(rest, thud) > 2 * Self.magnitude(rest, thud * 2))
    }

    /// The level of a frequency in the samples (the Goertzel filter, over the whole sound).
    static func magnitude(_ samples: [Float], _ frequency: Double) -> Double {
        let coefficient = 2 * cos(2 * Double.pi * frequency / Voices.sampleRate)
        var previous = 0.0, beforePrevious = 0.0
        for sample in samples {
            let next = Double(sample) + coefficient * previous - beforePrevious
            beforePrevious = previous
            previous = next
        }
        return sqrt(previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
    }

    /// A ring's repeats in the shortest solution go through every variant in turn: its first five all differ (or all
    /// it has, for rings 7 to 9, which move fewer times), and no two in a row are the same.
    @Test func repeatsVary() {
        var state = PuzzleState.allOn
        var variantsByRing: [Int: [Int]] = [:]
        for (number, ring) in state.moves(to: .allOff).enumerated() {
            variantsByRing[ring, default: []].append(Voices.variation.variant(moveNumber: number, eventIndex: 0))
            state = state.moving(ring)
        }
        for ring in 1...9 {
            let variants = variantsByRing[ring]!
            let first = variants.prefix(Voices.variation.count)
            #expect(Set(first).count == first.count, "ring \(ring): \(variants.prefix(8))")
            #expect(zip(variants, variants.dropFirst()).allSatisfy { $0 != $1 })
        }
    }

    /// The slide is silent while the sword is still, and louder and brighter as it goes faster, never clipping.
    @Test func slideFollowsTheSword() {
        func level(_ speed: Double) -> Double {
            let samples = SlideNoise.render(speeds: Array(repeating: speed, count: 24_000)).suffix(12_000)
            return sqrt(samples.map { Double($0 * $0) }.reduce(0, +) / Double(samples.count))
        }
        #expect(level(0) == 0)
        let slow = level(30), normal = level(100), fast = level(400)
        #expect(slow > 0 && slow < normal && normal < fast)
        let loudest = SlideNoise.render(speeds: Array(repeating: 2_000, count: 48_000)).map(abs).max()!
        #expect(loudest < 0.3)
        // Stopping fades it out, to exactly nothing.
        let stopping = SlideNoise.render(speeds: Array(repeating: 100, count: 4_800) + Array(repeating: 0, count: 48_000))
        #expect(stopping.suffix(1_000).allSatisfy { $0 == 0 })
    }
}
