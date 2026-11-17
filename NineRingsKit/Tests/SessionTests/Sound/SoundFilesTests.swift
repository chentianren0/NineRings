import Foundation
import Motion
import Puzzle
@testable import Session
import Testing
import Toy

/// Writes the voices, and the shortest solution as the app plays it, to WAV files, for listening. Run optimized with
/// `NINE_RINGS_WAV=<folder>`; `NINE_RINGS_WAV_SECONDS` sets how much of the solution (60 by default).
///
/// The solution is rendered as the app plays it: every move of the shortest solution from every ring on, one after
/// another, each event at its moment of the move's timing, thinned as the app thins it, voiced as the app voices it,
/// and the sword's slide following its written speed.
@Suite struct SoundFilesTests {
    static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["NINE_RINGS_WAV"] != nil))
    func writeFiles() throws {
        let folder = URL(fileURLWithPath: Self.environment["NINE_RINGS_WAV"]!)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ name: String, _ samples: [Float]) throws {
            let url = folder.appending(path: name + ".wav")
            try Self.wav(samples).write(to: url)
            print(String(format: "wrote %@: %.1f s, peak %.2f", url.lastPathComponent, Double(samples.count) / Voices.sampleRate, samples.map(abs).max() ?? 0))
        }
        // Each voice alone: a strike of each variant of the one note, then each ring's strike, then the same for the
        // rest, each 0.7 s apart.
        try write("1-strike-one-note-5-variants", Self.sequence((0..<5).map { Voicing(voice: .strike, variant: $0) }))
        try write("2-strike-note-per-ring-1-to-9", Self.sequence((1...9).map { Voicing(voice: .strike, ring: $0) }))
        try write("3-rest-one-note-5-variants", Self.sequence((0..<5).map { Voicing(voice: .rest, variant: $0) }))
        try write("4-rest-note-per-ring-1-to-9", Self.sequence((1...9).map { Voicing(voice: .rest, ring: $0) }))
        try write("5-sword-home", Self.sequence((0..<3).map { Voicing(voice: .swordHome, variant: $0) }))
        try write("6-refusal", Self.sequence([.refusal, .refusal]))
        try write("7-solved", Voicing.solved.render())
        for ring in [1, 2, 9] {
            guard let move = Move(ring: ring, from: ring == 1 ? .allOn : PuzzleState(bits: UInt16(0x1FF) & ~UInt16((1 << max(ring - 2, 0)) - 1))) else { continue }
            try write("8-slide-ring-\(ring)-off", Self.render(moves: [move], seconds: 10, speed: 1, notePerRing: true, eventsToo: false))
        }
        let seconds = Double(Self.environment["NINE_RINGS_WAV_SECONDS"] ?? "60") ?? 60
        let solution = Self.solution
        for notePerRing in [true, false] {
            let name = notePerRing ? "note-per-ring" : "one-note"
            try write("9-solution-1x-\(name)", Self.render(moves: solution, seconds: seconds, speed: 1, notePerRing: notePerRing))
            try write("9-solution-4x-\(name)", Self.render(moves: solution, seconds: 30, speed: 4, notePerRing: notePerRing))
        }
    }

    /// The shortest solution from every ring on.
    static let solution: [Move] = {
        var state = PuzzleState.allOn
        return state.moves(to: .allOff).map { ring in
            let move = Move(ring: ring, from: state)!
            state = move.to
            return move
        }
    }()

    /// Voicings one after another, 0.7 s apart.
    static func sequence(_ voicings: [Voicing]) -> [Float] {
        let gap = Int(0.7 * Voices.sampleRate)
        var out = [Float](repeating: 0, count: gap * voicings.count + Int(Voices.sampleRate))
        for (index, voicing) in voicings.enumerated() {
            for (offset, sample) in voicing.render().enumerated() where index * gap + offset < out.count {
                out[index * gap + offset] += sample
            }
        }
        return out
    }

    /// `moves` played one after another at `speed`, for at most `seconds`, as the app plays them.
    static func render(moves: [Move], seconds: Double, speed: Double, notePerRing: Bool, eventsToo: Bool = true) -> [Float] {
        let rate = Voices.sampleRate
        var out = [Double](repeating: 0, count: Int(seconds * rate))
        var slideSpeed = [Double](repeating: 0, count: out.count)
        var buffers: [Voicing: [Float]] = [:]
        var thinning = Thinning()
        var time = 0.0
        for (number, move) in moves.enumerated() where time < seconds {
            let motion = MoveMotion(move), score = Score(move), timing = motion.timing
            if eventsToo {
                for (index, event) in score.events.enumerated() {
                    let at = time + timing.time(atProgress: event.progress) / speed
                    guard thinning.admits(event, at: at) else { continue }
                    let heard = Hearing.Heard(event: event, move: move, index: index, moveNumber: number)
                    let voicing = Voicing(heard, notePerRing: notePerRing)
                    let samples = buffers[voicing] ?? voicing.render()
                    buffers[voicing] = samples
                    let start = Int(at * rate)
                    for (offset, sample) in samples.enumerated() where start + offset < out.count {
                        out[start + offset] += Double(sample) * event.strength
                    }
                }
            }
            // The sword's speed, worked out every millisecond of the move, as the app does every frame.
            let step = 0.001
            var last = 0.0
            for tick in stride(from: step, through: timing.duration / speed, by: step) {
                let travel = score.swordTravel(at: timing.progress(atTime: tick * speed))
                let speedNow = (travel - last) / step
                last = travel
                let from = Int((time + tick - step) * rate), to = min(Int((time + tick) * rate), out.count)
                if from < to { for index in from..<to { slideSpeed[index] = speedNow } }
            }
            time += timing.duration / speed
            if eventsToo && move.to == .allOff {
                let phrase = Voicing.solved.render()
                let start = Int((time + 0.25) * rate)
                for (offset, sample) in phrase.enumerated() where start + offset < out.count { out[start + offset] += Double(sample) }
            }
        }
        let slide = SlideNoise.render(speeds: slideSpeed)
        return zip(out, slide).map { Float($0) + $1 }
    }

    /// 16-bit mono WAV.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let rate = UInt32(Voices.sampleRate)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples.count * 2))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * 32_767)) }
        return data
    }
}
