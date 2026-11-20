import Foundation
@testable import Records
import Testing

/// The checks of docs/icloud.md section 14, over many orders of events that a seeded generator chooses:
/// - no toy is replaced except by taking up or by the person's choice;
/// - all devices end with the same history and the same toy, in one zone;
/// - nothing that a purge removed is sent again;
/// - nothing of one account reaches another account's iCloud;
/// - nothing stays stuck: once every device has synced and had its sending moments, nothing is left marked.
///
/// The orders include purges, resets of encrypted data, zones found missing, expired reports of deletions, two
/// creations of a zone at the same time, starts from nothing, relaunches and crashes in the middle of a send, changes
/// of account while the app runs and while it does not, a full storage, and lost and late answers. A failure names its
/// seed, which replays the same order. The ways where Apple documents nothing come from the seed: the three that matter
/// most from its lowest bits, so that the seeds go through every combination (old deletions from nothing, a device's own
/// save fetched before its answer, a lost answer whose save landed), and the rest drawn from it.
@MainActor
@Suite struct OrdersOfEventsTests {
    @Test(arguments: (0..<128).map { UInt64($0) })
    func theChecksHold(seed: UInt64) throws {
        let order = try RandomOrder(seed: seed)
        order.run(steps: 160)
        let settled = order.finish()
        let problems = order.world.watcher.problems
        let disagreements = order.world.disagreements()
        #expect(settled, "seed \(seed) did not settle: \(order.choices)")
        #expect(problems.isEmpty, "seed \(seed): \(problems) \(order.choices)")
        #expect(disagreements.isEmpty, "seed \(seed): \(disagreements) \(order.choices) \(order.world.watcher.tally.counts)")
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
    /// Whether zones go: purges, resets, zones found missing, expired reports.
    let zonesGo: Bool
    let choices: String

    init(seed: UInt64) throws {
        var draw = SeededRandom(seed: seed &* 0x2545_F491_4F6C_DD1D &+ 7)
        var cloud = StandInICloud.Choices()
        cloud.fetchFromNothingBringsOldDeletions = seed & 1 != 0
        cloud.ownChangesComeBack = [1.0, 0.5, 0.0][Int.random(in: 0..<3, using: &draw)]
        cloud.refusalCarriesRecord = draw.chance(0.85)
        cloud.reportsOwnZoneChanges = draw.chance(0.5)
        cloud.lossesReportedAsDeletions = draw.chance(0.7)
        var engine = StandInEngine.Choices()
        engine.answerComesLate = seed & 2 != 0 ? 0.3 : 0
        engine.answerLost = seed & 4 != 0 ? 0.2 : 0
        engine.landsWhenAnswerLost = seed & 4 != 0 ? 0.7 : 0
        engine.resendsLostAnswers = draw.chance(0.5)
        engine.zoneAnswerLost = draw.chance(0.3) ? 0.3 : 0
        engine.keepsZoneSaveAfterLostAnswer = draw.chance(0.5)
        engine.reportsSignInFromNothing = draw.chance(0.8)
        engine.accountReportComesFirst = draw.chance(0.5)
        engine.requestFindsFetchUnderWay = draw.chance(0.3) ? 0.3 : 0
        engine.zoneFetchFails = draw.chance(0.2) ? 0.1 : 0
        engine.stateUpdateAfterChange = [0.0, 0.5, 1.0][Int.random(in: 0..<3, using: &draw)]
        engine.batchSize = [1, 3, 8][Int.random(in: 0..<3, using: &draw)]
        accountsChange = draw.chance(0.4)
        storageFills = draw.chance(0.3)
        zonesGo = draw.chance(0.6)
        world = World(seed: seed, cloud: cloud, engine: engine)
        random = world.random
        let kinds: [MadeOn] = [.iPhone, .iPad, .Mac]
        for index in 0..<(draw.chance(0.5) ? 3 : 2) {
            let device = try world.device("device \(index + 1)", kind: kinds[index])
            device.accountQuestionFails = draw.chance(0.2) ? 0.3 : 0
        }
        choices = "\(cloud); \(engine); accounts change: \(accountsChange), storage fills: \(storageFills), zones go: \(zonesGo)"
    }

    /// `steps` things that happen, on any device, in an order the seed chooses.
    func run(steps: Int) {
        for _ in 0..<steps { step() }
    }

    /// Where a trace of every step goes, for a test that looks into one order of events.
    var trace: ((String) -> Void)?

    private func step() {
        let device = random.pick(world.devices)
        let what = random.int(0..<120)
        trace?("STEP \(device.name) \(what)")
        switch what {
        case 0..<22: device.move()
        case 22..<24: device.undo()
        case 24..<26: device.spendTime()
        case 26..<32: device.finishPlay()
        case 32..<34: device.clearHistory()
        case 34..<42: device.calmMoment()
        case 42..<46: device.answerOffer(keepThisOne: random.chance(0.5))
        case 46..<52: device.toyChanged()
        case 52..<56: device.cameToFront()
        case 56..<59: device.leftFront()
        case 59..<62: device.pickUp(moves: random.int(0..<4))
        case 62..<65: device.putDown()
        case 65..<78: device.doWhatWasAsked()
        case 78..<86: device.engineSends()
        case 86..<89: device.engineFetchesByItself()
        case 89..<91: device.deliverLateAnswers()
        case 91..<93: device.relaunch()
        case 93: device.crashDuringSend()
        case 94: device.discardEngineState()
        case 95..<97: device.isOnline.toggle()
        case 97:
            guard accountsChange else { break }
            switch random.int(0..<5) {
            case 0: device.signIn(to: nil)
            case 1: device.signIn(to: World.person)
            case 2: device.signIn(to: World.other)
            case 3: device.signInWhileNotRunning(to: World.person)
            default: device.signInWhileNotRunning(to: World.other)
            }
        case 98:
            guard storageFills else { break }
            world.cloud.database(World.person).isFull.toggle()
        case 99, 100:
            guard zonesGo else { break }
            switch random.int(0..<5) {
            case 0: world.cloud.deleteEveryZone(account: World.person, reason: .purged)
            case 1: world.cloud.deleteEveryZone(account: World.person, reason: .encryptedDataReset)
            case 2:
                if let zone = world.cloud.zoneNames(account: World.person).last {
                    world.cloud.loseZoneSilently(zone, account: World.person)
                }
            case 3: world.cloud.expireDeletionReports(account: World.person)
            default: break
            }
        default:
            // The rules asked for something, which the app does a moment later.
            device.doWhatWasAsked()
        }
    }

    /// Every device online, signed in to the person's account, with storage to spare, and synced until nothing changes;
    /// every offer is answered with Play That One. Returns whether it settled.
    func finish() -> Bool {
        world.cloud.database(World.person).isFull = false
        for device in world.devices {
            device.isOnline = true
            if device.account != World.person { device.signIn(to: World.person) }
        }
        var settled = world.settle(answeringOffers: false)
        // A device that would give up a second zone without a report in one run keeps it as not known to exist until
        // its next launch (section 9): it is launched again, and only it.
        for _ in 0..<4 {
            let waiting = world.devices.filter { $0.sync.run.gaveUpZone && $0.zoneNote?.knowledge == .notKnownToExist }
            guard !waiting.isEmpty else { break }
            world.watcher.tally.count("waited for the next launch, after a second zone not known to exist in a run")
            for device in waiting { device.relaunch() }
            settled = world.settle(answeringOffers: false)
        }
        return settled
    }
}
