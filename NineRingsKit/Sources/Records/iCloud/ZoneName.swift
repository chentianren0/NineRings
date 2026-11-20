import Foundation

/// The name of one of the design's zones: `NineRings-`, the zone's number, a hyphen and a random id, for example
/// `NineRings-2-6F9619FF-8B86-4011-B42D-00CF4FC964FF` (docs/icloud.md, section 9).
///
/// The number is written in decimal, from 1, without leading zeros; the random id is a UUID in the upper-case form that
/// Swift's `UUID` gives. Only names of exactly this form are zones of the design; every other zone is ignored. Zones
/// are ordered by their number, compared as numbers, and zones with the same number by their random id, compared as
/// text: *higher* and *highest* mean this order.
struct ZoneName: Hashable, Comparable, Sendable, CustomStringConvertible {
    static let prefix = "NineRings-"

    let number: Int
    let id: String

    /// The name of zone `number` with the random id `id`.
    init(number: Int, id: UUID) {
        precondition(number >= 1, "zone numbers start at 1")
        self.number = number
        self.id = id.uuidString
    }

    /// The zone named `name`, or nil when the name is not of the design's form.
    init?(_ name: String) {
        guard name.hasPrefix(Self.prefix) else { return nil }
        let rest = name.dropFirst(Self.prefix.count)
        guard let hyphen = rest.firstIndex(of: "-") else { return nil }
        let digits = rest[..<hyphen]
        let id = String(rest[rest.index(after: hyphen)...])
        guard let first = digits.first, first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits.count <= 18, let number = Int(digits),
              let uuid = UUID(uuidString: id), uuid.uuidString == id else { return nil }
        self.number = number
        self.id = id
    }

    /// The name as CloudKit holds it.
    var name: String { "\(Self.prefix)\(number)-\(id)" }

    var description: String { name }

    static func < (a: ZoneName, b: ZoneName) -> Bool {
        (a.number, a.id) < (b.number, b.id)
    }
}
