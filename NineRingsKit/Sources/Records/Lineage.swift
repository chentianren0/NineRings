import Foundation

/// Which toys of the app's installations a saved toy was made knowing, so that two installations can tell which of
/// their toys is the later without any clock.
///
/// Each installation counts the changes it makes to its toy, 1, 2, 3, and a change is named by the installation and its
/// count. A toy's lineage holds the change that made it as it is, its ``head``, and for each installation the count of
/// its latest change the toy was made knowing, which includes the head. The rules it keeps:
/// - A change the person makes to the toy is a new change of this installation, made knowing all the toy knew. Time
///   spent looking at the toy is not a change.
/// - Taking up another installation's toy makes its head this toy's, and the toy then knows all that either knew. No
///   change is made: the two installations have the same toy.
/// - Keeping this toy over another's, when the play has parted in two, is a change of this installation made knowing
///   all that either knew. So the other installation, seeing it, finds a toy made knowing its own, and follows.
/// - A toy nobody has changed has no head, and every toy was made knowing it.
/// - One toy was made knowing another when it knows the other's head. The later of two toys is the one made knowing
///   the other; when neither was made knowing the other, the play has parted in two (``compare(with:)``).
///
/// Counts only grow: an installation's count in its own toy is never lower than its latest change, since knowing only
/// grows. So a change is never named twice, and once a toy knows a change it knows every earlier change of that
/// installation.
public struct Lineage: Sendable, Hashable, Codable {
    /// One change made to a toy: the installation that made it, and its count of changes then.
    public struct Change: Sendable, Hashable, Codable {
        public var installation: String
        public var count: Int

        public init(installation: String, count: Int) {
            self.installation = installation
            self.count = count
        }
    }

    /// The change that made the toy as it is, or nil when nobody has changed it.
    public private(set) var head: Change?
    /// For each installation, the count of its latest change this toy was made knowing.
    public private(set) var knows: [String: Int]

    /// The lineage of a toy nobody has changed.
    public init() {
        head = nil
        knows = [:]
    }

    init(head: Change?, knows: [String: Int]) {
        self.head = head
        self.knows = knows
    }

    /// Whether this toy was made knowing the toy `other` describes: it knows that toy's head.
    public func knows(_ other: Lineage) -> Bool {
        guard let head = other.head else { return true }
        return knows[head.installation, default: 0] >= head.count
    }

    /// The lineage after `installation` changes the toy.
    public func changed(by installation: String) -> Lineage {
        let count = knows[installation, default: 0] + 1
        var knows = knows
        knows[installation] = count
        return Lineage(head: Change(installation: installation, count: count), knows: knows)
    }

    /// The lineage after taking up the toy `other` describes in place of this one.
    public func takingUp(_ other: Lineage) -> Lineage {
        Lineage(head: other.head, knows: knows.merging(other.knows, uniquingKeysWith: max))
    }

    /// The lineage after `installation` keeps this toy over the one `other` describes.
    public func keeping(over other: Lineage, by installation: String) -> Lineage {
        Lineage(head: head, knows: knows.merging(other.knows, uniquingKeysWith: max)).changed(by: installation)
    }

    /// How two toys stand, seen from this one.
    public enum Order: Sendable, Equatable {
        /// The same toy: made by the same change.
        case same
        /// The other toy was made knowing this one, and this one not knowing it: the other is the later.
        case otherIsLater
        /// This toy was made knowing the other, and the other not knowing it: this one is the later.
        case thisIsLater
        /// Neither was made knowing the other: the play has parted in two.
        case parted
    }

    /// How this toy and the one `other` describes stand. Two different toys that each know the other cannot come about
    /// by the rules above; should they meet, they are told as parted, so that the person decides and nothing is
    /// replaced by itself.
    public func compare(with other: Lineage) -> Order {
        if head == other.head { return .same }
        switch (knows(other), other.knows(self)) {
        case (false, true): return .otherIsLater
        case (true, false): return .thisIsLater
        default: return .parted
        }
    }

    // MARK: Kept as JSON

    /// The lineage as JSON, as a `SavedToy` keeps it.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// The lineage `data` keeps: empty data, as a toy saved before lineages has, is a toy nobody has changed; data that
    /// is not a lineage is nil.
    public init?(data: Data) {
        if data.isEmpty {
            self.init()
            return
        }
        guard let lineage = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = lineage
    }
}
