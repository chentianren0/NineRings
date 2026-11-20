import Foundation
@testable import Records
import Testing

@MainActor
@Suite struct SmokeTests {
    @Test func twoDevicesShare() throws {
        let world = World()
        let iPhone = try world.device("iPhone")
        iPhone.move()
        iPhone.finishPlay()
        iPhone.move()
        iPhone.putDown()
        world.settle()
        let iPad = try world.device("iPad", kind: .iPad)
        world.settle()
        print(world.watcher.tally.counts)
        print(iPhone.zoneNote as Any, iPad.zoneNote as Any)
        #expect(world.disagreements().isEmpty, "\(world.disagreements())")
        #expect(iPad.history.plays.count == 1)
        #expect(iPad.keptToy?.isSameToy(as: iPhone.keptToy!) == true)
    }
}
