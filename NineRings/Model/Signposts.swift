import os

/// Marks for Instruments: the work of a launch, as intervals in the Points of Interest track, so that the time from
/// launch to the toy's first frame, and where it goes, can be read on any device with the Time Profiler (the launch
/// and idle hand-over tells how). A signpost nobody records costs a check, so they stay in a release build.
nonisolated enum Signposts {
    static let poster = OSSignposter(subsystem: "NineRings", category: .pointsOfInterest)

    /// Runs `body` as an interval named `name`.
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let mark = begin(name)
        defer { end(name, mark) }
        return try body()
    }

    /// Runs `body` as an interval named `name`, across its suspensions.
    static func interval<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let mark = begin(name)
        defer { end(name, mark) }
        return try await body()
    }

    /// A moment, such as the toy's first frame.
    static func event(_ name: StaticString) {
        poster.emitEvent(name)
        #if MEASURE && os(macOS)
        MeasureLog.record(name, from: nil)
        #endif
    }

    private struct Mark {
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
    }

    private static func begin(_ name: StaticString) -> Mark {
        Mark(state: poster.beginInterval(name, id: poster.makeSignpostID()), start: .now)
    }

    private static func end(_ name: StaticString, _ mark: Mark) {
        poster.endInterval(name, mark.state)
        #if MEASURE && os(macOS)
        MeasureLog.record(name, from: mark.start)
        #endif
    }
}
