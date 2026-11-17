import SwiftUI

/// The keys the sound settings are kept under.
enum SoundKey {
    static let sounds = "sound.enabled"
    static let haptics = "haptics.enabled"
}

/// The switches for sound and haptics, both on at first. Haptics is offered only where the device has them.
struct SoundSettingsSection: View {
    @AppStorage(SoundKey.sounds) private var sounds = true
    @AppStorage(SoundKey.haptics) private var haptics = true

    var body: some View {
        Section {
            Toggle(isOn: $sounds) {
                Text("Sounds", comment: "Settings switch: whether the toy makes sounds as its rings move.")
            }
            if Haptics.isSupported {
                Toggle(isOn: $haptics) {
                    Text("Haptics", comment: "Settings switch: whether the rings' moves are felt as taps on iPhone.")
                }
            }
        }
    }
}

/// Whether the rings sound alike, as rings of one size do, or each has its own note. The owner chooses by listening,
/// in the debug build's sound bench; a release build has a note per ring.
enum RingTuningDesign: String, CaseIterable, Identifiable {
    /// The same voice at nine pitches on a five-note scale: ring 1 the highest, ring 9 the lowest.
    case notePerRing
    /// One note for every ring.
    case oneNote

    static let key = "design.ringTuning"

    var id: Self { self }

    var title: String {
        switch self {
        case .notePerRing: "A note per ring"
        case .oneNote: "One note"
        }
    }
}
