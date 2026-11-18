#if DEBUG
import Foundation

/// iCloud's launch switches, read in a debug build only. Each takes a value. (`-cloudkit-schema` is `CloudSchema`'s, and
/// the switch itself is a setting: `-syncsWithICloud NO` launches with it off.)
enum ICloudLaunchOptions {
    /// `-icloud-available NO` counts iCloud as not available, whatever CloudKit says: the iCloud store is not opened,
    /// and Settings shows the line under the switch.
    static var countsICloudUnavailable: Bool {
        value(after: "-icloud-available") == "NO"
    }

    /// Another installation's toy, staged in a launch that keeps its records in memory, whose iCloud store is a stand-in
    /// that never syncs.
    enum StagedPlay: String {
        /// A toy that neither this one nor it was made knowing: the line that offers it shows.
        case parted
        /// A toy made knowing this one: it is taken up by itself at the first calm moment.
        case later
    }

    /// `-stage-other-play parted` or `-stage-other-play later`, which also keeps the launch's records in memory.
    static var stagedPlay: StagedPlay? {
        value(after: "-stage-other-play").flatMap(StagedPlay.init(rawValue:))
    }

    private static func value(after option: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
