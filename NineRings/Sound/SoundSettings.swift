import Foundation

/// The keys the settings screen keeps the sound switches under: both on when nothing is stored. The switches
/// themselves belong to the settings screen.
enum SoundKey {
    static let sounds = "settings.sounds"
    static let haptics = "settings.haptics"
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
