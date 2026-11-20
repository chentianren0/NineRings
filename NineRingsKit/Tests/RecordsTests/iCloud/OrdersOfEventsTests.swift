import Foundation
@testable import Records
import Session
import SwiftData
import Testing

/// The checks of docs/icloud.md section 14, over many orders of events that a seeded generator chooses:
/// - no toy is replaced except by taking up or by the person's choice;
/// - all devices end with the same history and the same toy, in one zone;
/// - no finished play is lost, unless a clearing, a purge or the loss of a device's data the design lets go took it;
/// - no shown play leaves a device without a cause the design names: a clearing there, a purge it was told of, a
///   deletion that arrived, a save refused as unknown, another account's data, or a backup brought back;
/// - nothing that a purge removed is sent again;
/// - nothing of one account reaches another account's iCloud;
/// - nothing stays stuck: once every device has synced and had its sending moments, nothing is left marked, and a
///   round of settling sends nothing.
///
/// Calm orders, without lost answers, crashes in a send, zone events, changes of account or restores, where no case the
/// design accepts can bring a cleared play back, also check that none comes back.
///
/// The orders include purges, resets of encrypted data, zones found missing, expired reports of deletions, two
/// creations of a zone at the same time, starts from nothing, relaunches and crashes in the middle of a send, changes
/// of account while the app runs and while it does not, a full storage, lost and late answers, saves refused as
/// unknown after a clearing elsewhere, failed writes of fetched changes, backups brought back, and apps deleted and
/// installed fresh, from nothing or from another device's backup. A failure names its
/// seed, which replays the same order. The ways where Apple documents nothing come from the seed: the three that matter
/// most from its lowest bits, so that the seeds go through every combination (old deletions from nothing, a device's own
/// save fetched before its answer, a lost answer whose save landed), and the rest drawn from it.
@MainActor
@Suite struct OrdersOfEventsTests {
    @Test(arguments: (0..<128).map { UInt64($0) })
    func theChecksHold(seed: UInt64) throws {
        try check(RandomOrder(seed: seed))
    }

    @Test(arguments: (0..<32).map { UInt64($0) })
    func noClearedPlayComesBackInCalmOrders(seed: UInt64) throws {
        try check(RandomOrder(seed: seed, calm: true))
    }

    private func check(_ order: RandomOrder) {
        order.run(steps: 160)
        let settled = order.finish()
        let problems = order.world.watcher.problems + order.world.playsLostOrBack(clearingsHold: order.calm)
        let disagreements = order.world.disagreements()
        #expect(settled, "seed \(order.seed) did not settle: \(order.choices)")
        #expect(problems.isEmpty, "seed \(order.seed): \(problems) \(order.choices)")
        #expect(disagreements.isEmpty, "seed \(order.seed): \(disagreements) \(order.choices) \(order.world.watcher.tally.counts)")
    }
}

/// More orders than continuous integration runs, on request: `ORDERS_SWEEP=128-2128` runs those seeds and prints the
/// ones whose checks fail; `ORDERS_TRACE=86` replays one seed and writes every step, call and change in iCloud to a file
/// in the temporary folder, with what the orders reach. Neither runs unless asked for.
@MainActor
@Suite struct OrdersOfEventsTools {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORDERS_SWEEP"] != nil))
    func sweep() throws {
        let bounds = (ProcessInfo.processInfo.environment["ORDERS_SWEEP"] ?? "").split(separator: "-").compactMap { UInt64($0) }
        guard bounds.count == 2 else { return }
        let calm = ProcessInfo.processInfo.environment["ORDERS_CALM"] != nil
        var failing = 0
        var reached: [String: Int] = [:]
        for seed in bounds[0]..<bounds[1] {
            let order = try RandomOrder(seed: seed, calm: calm)
            order.run(steps: 160)
            let settled = order.finish()
            let problems = order.world.watcher.problems + order.world.playsLostOrBack(clearingsHold: calm)
                + order.world.disagreements()
            for (what, count) in order.world.watcher.tally.counts { reached[what, default: 0] += count }
            guard !settled || !problems.isEmpty else { continue }
            failing += 1
            print("seed \(seed): settled \(settled), \(problems)")
        }
        for (what, count) in reached.sorted(by: { $0.key < $1.key }) { print("reached \(what): \(count)") }
        print("\(failing) of \(bounds[1] - bounds[0]) seeds failed")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORDERS_TRACE"] != nil))
    func trace() throws {
        guard let seed = ProcessInfo.processInfo.environment["ORDERS_TRACE"].flatMap({ UInt64($0) }) else { return }
        var lines: [String] = []
        let order = try RandomOrder(seed: seed, calm: ProcessInfo.processInfo.environment["ORDERS_CALM"] != nil)
        order.trace = { lines.append($0) }
        for device in order.world.devices { device.trace = { lines.append($0) } }
        order.world.cloud.trace = { lines.append($0) }
        order.run(steps: 160)
        let settled = order.finish()
        lines.append("settled \(settled); \(order.choices)")
        lines.append("problems \(order.world.watcher.problems + order.world.playsLostOrBack(clearingsHold: order.calm) + order.world.disagreements())")
        for device in order.world.devices {
            lines.append("\(device.name) shows \(device.history.plays.map { $0.playID.uuidString.prefix(8) }.sorted())")
        }
        if let zone = order.world.personsZone {
            lines.append("iCloud holds \(order.world.cloud.records(zone: zone, account: World.person).compactMap { $0.playID?.uuidString.prefix(8) }.sorted())")
        }
        for (what, count) in order.world.watcher.tally.counts.sorted(by: { $0.key < $1.key }) { lines.append("\(what): \(count)") }
        let file = URL.temporaryDirectory.appending(path: "orders-\(seed).txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        print("written to \(file.path)")
    }
}

/// One order of events, chosen by a seed.
@MainActor
final class RandomOrder {
    let seed: UInt64
    let world: World
    let random: SharedRandom
    /// Whether the order is calm: no lost answers, crashes in a send, zone events, changes of account, restores or apps
    /// deleted.
    let calm: Bool
    /// Copies of devices' stores, as device backups keep them, with the device each was taken of.
    private var backups: [(device: String, store: ModelContainer)] = []
    /// How many devices were installed.
    private var installs = 0
    /// Whether accounts sign out, in again, and change, and whether the storage fills.
    let accountsChange: Bool
    let storageFills: Bool
    /// Whether zones go: purges, resets, zones found missing, expired reports.
    let zonesGo: Bool
    let choices: String

    init(seed: UInt64, calm: Bool = false) throws {
        self.seed = seed
        self.calm = calm
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
        engine.reportsChangeWhileNotRunning = draw.chance(0.7)
        engine.requestFindsFetchUnderWay = draw.chance(0.3) ? 0.3 : 0
        engine.zoneFetchFails = draw.chance(0.2) ? 0.1 : 0
        engine.stateUpdateAfterChange = [0.0, 0.5, 1.0][Int.random(in: 0..<3, using: &draw)]
        engine.batchSize = [1, 3, 8][Int.random(in: 0..<3, using: &draw)]
        accountsChange = draw.chance(0.4) && !calm
        storageFills = draw.chance(0.3)
        zonesGo = draw.chance(0.6) && !calm
        if calm {
            engine.answerLost = 0
            engine.landsWhenAnswerLost = 0
            engine.zoneAnswerLost = 0
        }
        world = World(seed: seed, cloud: cloud, engine: engine)
        random = world.random
        choices = "\(calm ? "calm; " : "")\(cloud); \(engine); accounts change: \(accountsChange), storage fills: \(storageFills), zones go: \(zonesGo)"
        for _ in 0..<(draw.chance(0.5) ? 3 : 2) {
            let device = try install()
            device.accountQuestionFails = draw.chance(0.2) ? 0.3 : 0
        }
    }

    /// A new device, signed in to the person's account, from nothing or from `backup`.
    @discardableResult
    private func install(from backup: ModelContainer? = nil) throws -> SimulatedDevice {
        installs += 1
        let kinds: [MadeOn] = [.iPhone, .iPad, .Mac]
        let device = try world.device("device \(installs)", kind: kinds[(installs - 1) % 3], from: backup)
        device.trace = trace
        return device
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
        trace?("step: \(device.name), \(what)")
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
        case 93: if calm { device.relaunch() } else { device.crashDuringSend() }
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
        case 101, 106:
            // Another device clears, and this one starts from nothing: it sends the plays it held in iCloud again, on
            // their system fields, and those whose records went are refused as unknown (section 7).
            let others = world.devices.filter { $0 !== device }
            if !others.isEmpty {
                let other = random.pick(others)
                other.clearHistory()
                other.syncFully()
            }
            device.discardEngineState()
            device.syncFully()
        case 102:
            device.failsNextWriteOfFetchedChanges = true
        case 103:
            if let backup = try? device.backUp() {
                backups.append((device.name, backup))
                if backups.count > 4 { backups.removeFirst() }
            }
        case 104:
            guard !calm, let backup = backups.last(where: { $0.device == device.name }) else { break }
            world.watcher.tally.count("a device restored from its backup")
            try? device.restore(from: backup.store)
        case 105:
            // An app is deleted from a device, and installed on another: from nothing, or from a backup of another device.
            if !calm, world.devices.count == 3 || (world.devices.count == 2 && random.chance(0.3)) {
                world.watcher.tally.count("an app deleted")
                world.remove(device)
            }
            guard world.devices.count < 3 else { break }
            let backup = calm || backups.isEmpty || random.chance(0.6) ? nil : random.pick(backups).store
            world.watcher.tally.count(backup == nil ? "a device installed fresh" : "a device installed from another's backup")
            _ = try? install(from: backup)
        default:
            // The rules asked for something, which the app does a moment later.
            device.doWhatWasAsked()
        }
    }

    /// Every device online, with a network that loses no answers, signed in to the person's account, with storage to
    /// spare, and synced until nothing changes; every offer is answered with Play That One. Returns whether it settled.
    func finish() -> Bool {
        world.cloud.database(World.person).isFull = false
        for device in world.devices {
            device.failsNextWriteOfFetchedChanges = false
            if device.sync.run.writeFailed {
                // A failed write of fetched changes holds the device back until its next launch (section 10).
                world.watcher.tally.count("relaunched after a failed write of fetched changes")
                device.relaunch()
            }
            var good = device.engineChoices
            good.answerLost = 0
            good.zoneAnswerLost = 0
            good.zoneFetchFails = 0
            good.requestFindsFetchUnderWay = 0
            device.engineChoices = good
            device.engine.choices = good
            device.accountQuestionFails = 0
            device.isOnline = true
            if device.account != World.person { device.signIn(to: World.person) }
        }
        var settled = world.settle(answeringOffers: false)
        // Two cases the design accepts leave a device without records that iCloud holds, until its engine next starts
        // from nothing (section 16): it joined a zone whose records its engine had fetched while it used another, or a
        // play it had cleared came back to it and its deletion was answered only afterwards. It is given that start.
        // Only a device whose every missing play is among the records it did not apply, and that shows no play iCloud
        // lacks, is in one of those cases.
        let lackingRecords = world.devices.filter { device in
            guard let zone = device.zoneNote?.zone.name else { return false }
            let inICloud = Set(world.cloud.records(zone: zone, account: World.person).compactMap(\.playID))
            let shown = Set(((try? device.sync.store.allPlays()) ?? []).filter { $0.sync != .cleared }.map(\.playID))
            let missing = inICloud.subtracting(shown)
            return !missing.isEmpty && shown.isSubset(of: inICloud)
                && missing.allSatisfy { device.recordsNotApplied.contains(RecordID(zone: zone, name: $0.uuidString)) }
        }
        if !lackingRecords.isEmpty {
            world.watcher.tally.count("accepted: records lacking until the next start from nothing")
            for device in lackingRecords { device.discardEngineState() }
            settled = world.settle(answeringOffers: false)
        }
        // A device whose zone went without its being told, by a lost report or a zone found missing, learns of it at its
        // next save (section 9), and brings its data along: the person makes a move on it.
        let unaware = world.devices.filter { device in
            guard let note = device.zoneNote, note.knowledge == .existing else { return false }
            return !world.cloud.hasZone(note.zone.name, account: World.person)
        }
        if !unaware.isEmpty {
            world.watcher.tally.count("accepted: a zone gone without a report, found at the next save")
            for device in unaware {
                device.move()
                device.toyChanged()
            }
            settled = world.settle(answeringOffers: false)
        }
        // A device that applied fetched changes before its account was confirmed, and removed them with another
        // account's data, lacks them until its engine next starts from nothing (section 16): it is given that start.
        let lacking = world.devices.filter(\.lostFetchedChangesWithAnotherAccount)
        if !lacking.isEmpty {
            world.watcher.tally.count("accepted: fetched changes removed with another account's data")
            for device in lacking { device.discardEngineState() }
            settled = world.settle(answeringOffers: false)
        }
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
