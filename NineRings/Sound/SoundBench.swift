#if DEBUG
import Session
import SwiftUI

/// The debug build's sound bench, in the Design menu: each voice on its own, the solved phrase, and the choice
/// between one note and a note per ring. It plays even with the Sounds switch off. Its words are not translated.
struct SoundBenchMenu: View {
    @AppStorage(RingTuningDesign.key) private var tuning = RingTuningDesign.notePerRing

    var body: some View {
        Menu {
            Picker(selection: $tuning) {
                ForEach(RingTuningDesign.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Ring voices")
            }
            .onChange(of: tuning) { _, tuning in
                ToySound.shared?.playback.prepare(notePerRing: tuning == .notePerRing)
            }
            Section {
                bench("Strike, rings 1 to 9") { sequence((1...9).map { Voicing(voice: .strike, ring: notePerRing ? $0 : 0, variant: $0 % 5) }) }
                bench("Strike, one ring, five times") { sequence((0..<5).map { Voicing(voice: .strike, ring: notePerRing ? 1 : 0, variant: $0) }) }
                bench("Coming to rest, rings 1 to 9") { sequence((1...9).map { Voicing(voice: .rest, ring: notePerRing ? $0 : 0, variant: $0 % 5) }) }
                bench("Sword home") { sequence((0..<3).map { Voicing(voice: .swordHome, variant: $0) }) }
                bench("Refused") { sequence([.refusal, .refusal]) }
                bench("Solved") { ToySound.shared?.audition(.solved, gain: 1) }
                bench("Slide, ring 1's move") { ToySound.shared?.auditionSlide(ring: 1) }
                bench("Slide, ring 5's move") { ToySound.shared?.auditionSlide(ring: 5) }
            } header: {
                Text(verbatim: "Listen")
            }
        } label: {
            Text(verbatim: "Sound")
        }
    }

    private var notePerRing: Bool { tuning == .notePerRing }

    private func bench(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(verbatim: title) }
    }

    /// Voicings one after another, 0.6 s apart.
    private func sequence(_ voicings: [Voicing]) {
        for (index, voicing) in voicings.enumerated() {
            ToySound.shared?.audition(voicing, delay: 0.6 * Double(index))
        }
    }
}
#endif
