import Puzzle

/// The app's Game Center achievements. Each is earned once, and reported to Game Center when a player is signed in
/// (see ``AchievementLedger``).
///
/// The raw value is the achievement's identifier in Game Center, as written in the project's GameKit configuration and
/// in App Store Connect: it must never change once the achievement is live.
public enum Achievement: String, CaseIterable, Sendable, Codable {
    /// Every ring taken off: the moment the congratulation is due (see ``Congratulation``).
    case allNineOff = "all_nine_off"
    /// From every ring on to every ring off in 341 moves, with no Undo and no move played for the person: the record of
    /// a finished play that went the shortest way (``PlayRecord/isShortestWay``), earned by ``PlayState``.
    case shortestWay = "shortest_way"
    /// From every ring off, every ring put back on.
    case allNineBackOn = "all_nine_back_on"
    /// The arrangement with only ring 9 on: the far end of the puzzle's one path, 511 moves from every ring off.
    case farEnd = "far_end"
}

extension PuzzleState {
    /// Only ring 9 on: the far end of the one path, the arrangement furthest from every ring off.
    public static let farEnd = PuzzleState(rank: count - 1)
}

/// When an achievement is earned, from the person's own toy, change by change, as ``Congratulation`` sees it.
///
/// Whoever drives a ``PuzzleSession`` shows it the person's toy before and after each change, with
/// ``update(from:to:finished:)``, and every arrangement the person sets by hand, with ``set(_:)``. The rules it keeps:
/// - All Nine Off is earned when the congratulation is due: a play from every ring on, ended by the person's own move.
///   It shares the congratulation's rule so that the two never disagree.
/// - The other two are journeys along the one path, made by the person's own moves: from every ring off to every ring
///   on (All Nine Back On), and from every ring on or every ring off to only ring 9 on (The Far End). A journey counts
///   once the toy has been at its start, and it is earned by a move made forward that leaves the toy resting at its
///   end, as the congratulation is. An undo arriving there does not count, and neither does a move that Solve began,
///   however it was carried on.
/// - Resting at a journey's end in any other way, such as by Reset or by an undo, means the journey must start again.
///   The toy passing through it, with another ring waiting, changes nothing.
/// - Rings set by hand start a journey only from its start: setting the rings next to the far end and moving one ring
///   is not the journey there.
/// - A journey under way is kept with the toy between launches (``underWay``), so that it goes on after a relaunch.
/// - The Shortest Way is not earned here: it needs the count of undos and of moves played for the person, which the
///   record of a finished play holds. ``PlayState``, which writes that record at the moment the congratulation is due,
///   adds ``Achievement/shortestWay`` to what that change earns when the play went the shortest way.
public struct AchievementRule: Sendable, Equatable {
    private var backOn = Journey(from: [.allOff], to: .allOn)
    private var farEnd = Journey(from: [.allOn, .allOff], to: .farEnd)

    public init() {}

    /// The rule with the journeys toward `underWay` under way, as a kept toy brings them back. Achievements that are not
    /// journeys are ignored.
    public init(underWay: Set<Achievement>) {
        backOn.isUnderWay = underWay.contains(.allNineBackOn)
        farEnd.isUnderWay = underWay.contains(.farEnd)
    }

    /// The journeys under way, by the achievement each earns: what a kept toy keeps of the rule.
    public var underWay: Set<Achievement> {
        var underWay: Set<Achievement> = []
        if backOn.isUnderWay { underWay.insert(.allNineBackOn) }
        if farEnd.isUnderWay { underWay.insert(.farEnd) }
        return underWay
    }

    /// Takes in one change to the person's toy, `finished` when this change is the moment the congratulation is due.
    /// Returns what this change earns.
    public mutating func update(from before: PuzzleSession, to after: PuzzleSession, finished: Bool) -> Set<Achievement> {
        guard before != after else { return [] }
        var earned: Set<Achievement> = finished ? [.allNineOff] : []
        if backOn.update(from: before, to: after) { earned.insert(.allNineBackOn) }
        if farEnd.update(from: before, to: after) { earned.insert(.farEnd) }
        return earned
    }

    /// Takes in the toy set to an arrangement the person chose: each journey starts there only if it is its start.
    public mutating func set(_ state: PuzzleState) {
        backOn.set(state)
        farEnd.set(state)
    }

    /// One journey along the path, from any of `starts` to `end`.
    private struct Journey: Sendable, Equatable {
        let starts: Set<PuzzleState>
        let end: PuzzleState
        /// Whether the toy has been at a start since it last rested at the end.
        var isUnderWay = false

        init(from starts: Set<PuzzleState>, to end: PuzzleState) {
            self.starts = starts
            self.end = end
        }

        /// Returns true when this change completes the journey.
        mutating func update(from before: PuzzleSession, to after: PuzzleSession) -> Bool {
            // `before` too: the toy as it was first given, at launch or after a change that is not a move (going to the
            // lesson's last step, closing the lesson), is where the person's moves start from.
            if starts.contains(before.state) || starts.contains(after.state) { isUnderWay = true }
            guard after.state == end, !after.isBusy else { return false }
            defer { isUnderWay = false }
            // A move Solve began is Solve's however it is carried on (``PuzzleSession/madeBySolveCount``).
            return isUnderWay && after.moveCount > before.moveCount && !before.isSolving
                && after.madeBySolveCount == before.madeBySolveCount
        }

        mutating func set(_ state: PuzzleState) {
            isUnderWay = starts.contains(state)
        }
    }
}

/// What has been earned on this device, and what of it Game Center has taken: the rest waits for a signed-in player.
///
/// It names no player. Game Center's player identifiers are not read, so an achievement earned with no player signed in
/// goes to the first player who signs in, and one that a player has taken is not reported again on this device.
public struct AchievementLedger: Sendable, Equatable, Codable {
    public private(set) var earned: Set<Achievement> = []
    public private(set) var reported: Set<Achievement> = []

    public init() {}

    /// Earned on this device and not yet taken by Game Center.
    public var pending: Set<Achievement> { earned.subtracting(reported) }

    /// Notes `achievements` as earned. Returns those that are new, so that only they are reported now.
    @discardableResult
    public mutating func earn(_ achievements: Set<Achievement>) -> Set<Achievement> {
        let new = achievements.subtracting(earned)
        earned.formUnion(new)
        return new
    }

    /// Notes that Game Center has taken `achievements`.
    public mutating func markReported(_ achievements: Set<Achievement>) {
        reported.formUnion(achievements.intersection(earned))
    }
}
