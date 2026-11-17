/// Which events sound when they come close together: at a fast speed, or under a quick drag of the slider.
///
/// A move played at four times its speed passes its events four times as close, and a drag can pass them closer
/// still. Played as they come they would rattle. The rule is one spacing in real time, measured from the last event
/// that sounded: an event sounds only if at least ``spacing`` has passed since then, and a detail (a light touch
/// beside a main strike) only if at least ``detailSpacing`` has. So at full speed every event of every move sounds,
/// and as the speed rises the details drop out first, then events that would come within ``spacing`` of another;
/// whatever the speed, two sounds are never closer than ``spacing``. It goes by real time, so a drag thins out
/// exactly as playing at that speed does.
public struct Thinning: Sendable, Equatable {
    /// The least time, in seconds, between two events that sound.
    public static let spacing = 0.05
    /// The least time, in seconds, between the last event that sounded and a detail.
    public static let detailSpacing = 0.085

    /// When the last event that sounded did, in seconds on whatever clock the caller uses.
    public private(set) var lastSounded: Double?

    public init() {}

    /// Whether `event`, coming at `time`, sounds; if it does, it is the last that sounded.
    public mutating func admits(_ event: Score.Event, at time: Double) -> Bool {
        if let lastSounded, time - lastSounded < (event.isDetail ? Self.detailSpacing : Self.spacing) {
            return false
        }
        lastSounded = time
        return true
    }
}
