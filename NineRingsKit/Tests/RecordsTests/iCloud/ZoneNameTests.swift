import Foundation
@testable import Records
import Testing

/// The zone's name, docs/icloud.md section 9: its form, and the order of zones.
@Suite struct ZoneNameTests {
    private let id = "6F9619FF-8B86-4011-B42D-00CF4FC964FF"

    @Test func aNameOfTheDesignsForm() throws {
        let zone = try #require(ZoneName("NineRings-2-\(id)"))
        #expect(zone.number == 2 && zone.id == id)
        #expect(zone.name == "NineRings-2-\(id)")
        #expect(ZoneName(number: 12, id: UUID(uuidString: id)!).name == "NineRings-12-\(id)")
    }

    /// Only names of exactly this form count: the number in decimal from 1 without leading zeros, and the random id in the
    /// upper-case form Swift's `UUID` gives.
    @Test(arguments: [
        "Plays", "NineRings-0-6F9619FF-8B86-4011-B42D-00CF4FC964FF", "NineRings-02-6F9619FF-8B86-4011-B42D-00CF4FC964FF",
        "NineRings--6F9619FF-8B86-4011-B42D-00CF4FC964FF", "NineRings-2-6f9619ff-8b86-4011-b42d-00cf4fc964ff",
        "NineRings-2-6F9619FF8B864011B42D00CF4FC964FF", "NineRings-2", "NineRings-+2-6F9619FF-8B86-4011-B42D-00CF4FC964FF",
        "ninerings-2-6F9619FF-8B86-4011-B42D-00CF4FC964FF", "NineRings-2-6F9619FF-8B86-4011-B42D-00CF4FC964FF-",
        "NineRingsProbeAgain_3_A",
    ])
    func otherNamesAreNotZonesOfTheDesign(name: String) {
        #expect(ZoneName(name) == nil)
    }

    /// Zones are ordered by their number, compared as numbers, and zones with the same number by their random id,
    /// compared as text.
    @Test func theOrder() throws {
        let two = try #require(ZoneName("NineRings-2-FFFFFFFF-8B86-4011-B42D-00CF4FC964FF"))
        let ten = try #require(ZoneName("NineRings-10-00000000-8B86-4011-B42D-00CF4FC964FF"))
        let twoLater = try #require(ZoneName("NineRings-2-FFFFFFFF-8B86-4011-B42D-00CF4FC96500"))
        #expect(two < ten, "as numbers, not as text")
        #expect(two < twoLater)
        #expect([ten, twoLater, two].max() == ten)
    }
}
