import Foundation
@testable import Records
import Testing

/// The checks of docs/icloud.md section 14, over many orders of events that a seeded generator chooses: no toy is
/// replaced except by taking up or by the person's choice; all devices end with the same history once they have all
/// synced; and nothing is sent after a purge. Beyond them, the devices end with iCloud's toy once every offer is answered,
/// and with nothing marked as not received.
///
/// A failure names its seed, which replays the same order. The three ways the brief names where Apple documents nothing
/// come from the seed's lowest bits, so that the seeds go through every combination: whether a fetch from nothing brings
/// old deletions, whether a device's own save comes back before its answer, and whether the answer to a save is lost
/// although the save landed. The rest is drawn from the seed.
@MainActor
@Suite struct OrdersOfEventsTests {
    @Test(arguments: (0..<128).map { UInt64($0) })
    func theChecksHold(seed: UInt64) throws {
        let order = try RandomOrder(seed: seed)
        order.run(steps: 160)
        let settled = order.finish()
        #expect(settled, "seed \(seed) did not settle: \(order.choices)")
        #expect(order.world.watcher.problems.isEmpty, "seed \(seed): \(order.world.watcher.problems) \(order.choices)")
        #expect(order.world.disagreements().isEmpty, "seed \(seed): \(order.world.disagreements()) \(order.choices)")
    }
}

/// One order of events, chosen by a seed.
@MainActor
final class RandomOrder {
    let world: World
    let random: SharedRandom
    /// Whether accounts sign out, in again, and change, and whether the storage fills.
    let accountsChange: Bool
    let storageFills: Bool
    let choices: String

    init(seed: UInt64) throws {
        var draw = SeededRandom(seed: seed &* 0x2545_F491_4F6C_DD1D &+ 7)
        var cloud = StandInICloud.Choices()
        cloud.fetchFromNothingBringsOldDeletions = seed & 1 != 0
        cloud.ownChangesComeBack = [1.0, 0.5, 0.0][Int.random(in: 0..<3, using: &draw)]
        cloud.refusalCarriesRecord = draw.chance(0.85)
        cloud.deletingAMissingRecordIsConfirmed = draw.chance(0.5)
        var engine = StandInEngine.Choices()
        engine.answerComesLate = seed & 2 != 0 ? 0.35 : 0
        engine.answerLost = seed & 4 != 0 ? 0.25 : 0
        engine.landsWhenAnswerLost = seed & 4 != 0 ? 0.7 : 0
        engine.resendsLostAnswers = draw.chance(0.5)
        engine.reportsSignInFromNothing = draw.chance(0.6)
        engine.stateUpdateAfterChange = [0.0, 0.5, 1.0][Int.random(in: 0..<3, using: &draw)]
        engine.batchSize = [1, 3, 8][Int.random(in: 0..<3, using: &draw)]
        accountsChange = draw.chance(0.4)
        storageFills = draw.chance(0.3)
        world = World(seed: seed, cloud: cloud, engine: engine)
        random = world.random
        let kinds: [MadeOn] = [.iPhone, .iPad, .Mac]
        for index in 0..<(draw.chance(0.5) ? 3 : 2) {
            try world.device("device \(index + 1)", kind: kinds[index])
        }
        choices = "\(cloud); \(engine); accounts change: \(accountsChange), storage fills: \(storageFills)"
    }

    /// `steps` things that happen, on any device, in an order the seed chooses.
    func run(steps: Int) {
        for _ in 0..<steps { step() }
    }

    private func step() {
        let device = random.pick(world.devices)
        switch random.int(0..<106) {
        case 100..<103: device.pickUp(moves: random.int(0..<4))
        case 103..<106: device.putDown()
        case 0..<24: device.move()
        case 24..<26: device.undo()
        case 26..<29: device.spendTime()
        case 29..<36: device.finishPlay()
        case 36..<38: device.clearHistory()
        case 38..<49: device.calmMoment()
        case 49..<54: device.answerOffer(keepThisOne: random.chance(0.5))
        case 54..<59: device.sendingMoment()
        case 59..<63: device.cameToFront()
        case 63..<67: device.leftFront()
        case 67..<79: device.engineSends()
        case 79..<91: device.engineFetches()
        case 91..<94: device.deliverLateAnswers()
        case 94..<96: device.relaunch()
        case 96..<98: device.isOnline.toggle()
        case 98:
            guard accountsChange else { break }
            switch random.int(0..<3) {
            case 0: device.signIn(to: nil)
            case 1: device.signIn(to: World.person)
            default: device.signIn(to: World.other)
            }
        case 99:
            guard storageFills else { break }
            world.cloud.database(World.person).isFull.toggle()
        default:
            break
        }
        // What the rules asked of the engine, which the app does outside the delegate's callback, a moment later.
        if device.wantsFetch, random.chance(0.6) { device.engineFetches() }
        if device.wantsSend, random.chance(0.6) { device.engineSends() }
    }

    /// Every device online, signed in to the person's account, with storage to spare, and synced until nothing changes;
    /// every offer is answered with Play That One. Returns whether it settled.
    func finish() -> Bool {
        world.cloud.database(World.person).isFull = false
        for device in world.devices {
            device.isOnline = true
            if device.account != World.person { device.signIn(to: World.person) }
            device.cameToFront()
            device.sendingMoment()
        }
        return world.settle(answeringOffers: false)
    }
}
