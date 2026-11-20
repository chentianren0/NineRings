import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// Several simulated devices of one person against one stand-in iCloud: what the scenario tests and the orders of events
/// run in.
@MainActor
final class World {
    let cloud: StandInICloud
    let watcher = Watcher()
    let clock = TestClock()
    let random: SharedRandom
    var engineChoices: StandInEngine.Choices
    private(set) var devices: [SimulatedDevice] = []
    /// The person's account.
    static let person = "person"
    /// Another person's account.
    static let other = "other"

    init(seed: UInt64 = 1, cloud choices: StandInICloud.Choices = .init(), engine: StandInEngine.Choices = .init()) {
        cloud = StandInICloud(choices: choices, seed: seed)
        random = SharedRandom(seed: seed)
        engineChoices = engine
        cloud.zoneWent = { [unowned self] reason in
            switch reason {
            case .purged?, .deleted?: watcher.purgedInICloud()
            case .encryptedDataReset?, nil: watcher.lostInICloud(keeping: devices.reduce(into: []) { $0.formUnion($1.playsHeld) })
            }
        }
        watcher.unsentElsewhere = { [unowned self] device in
            devices.filter { $0.name != device }.reduce(into: []) { $0.formUnion($1.playsNeverSent) }
        }
    }

    /// A new device, signed in to `account`, launched for the first time; or set up from `backup`, a copy of another
    /// device's store. With `clock`, the device keeps time by a clock of its own.
    @discardableResult
    func device(
        _ name: String, kind: MadeOn = .iPhone, account: String? = World.person, from backup: ModelContainer? = nil,
        clock: TestClock? = nil
    ) throws -> SimulatedDevice {
        let device = try SimulatedDevice(
            name: name, kind: kind, cloud: cloud, account: account, watcher: watcher, clock: clock ?? self.clock,
            random: random, engineChoices: engineChoices, restoredFrom: backup
        )
        devices.append(device)
        return device
    }

    /// Takes `device` out of the world: it is no longer settled or checked, as an app that was deleted. The plays it held
    /// that had not reached iCloud are lost with it.
    func remove(_ device: SimulatedDevice) {
        watcher.lost(plays: device.playsICloudLacks)
        devices.removeAll { $0 === device }
    }

    /// Lets every device come to the front, sync, hear its late answers, take toys up at calm moments and have its
    /// sending moments, round after round, until a round changes nothing and sends nothing to iCloud. With
    /// `answeringOffers`, every offer is answered that way: Play That One when false.
    @discardableResult
    func settle(answeringOffers keepThisOne: Bool? = nil, rounds: Int = 40) -> Bool {
        for _ in 0..<rounds {
            let before = look()
            let requestsBefore = cloud.requests.count
            for device in devices {
                device.cameToFront()
                device.syncFully()
                device.deliverLateAnswers()
                device.calmMoment()
                if let keepThisOne, device.isOffered { device.answerOffer(keepThisOne: keepThisOne) }
                device.toyChanged()
                device.syncFully()
            }
            let sent = cloud.requests[requestsBefore...].filter { request in
                // Accepted (section 16): a toy refused without its record, which no fetch brings, is sent again.
                !(request.name == CloudRecord.toyName && devices.contains {
                    $0.name == request.device && $0.toyRefusedWithoutRecord && $0.toySide.isChanged
                })
            }
            if look() == before, sent.isEmpty, devices.allSatisfy(\.isSettled) { return true }
        }
        return false
    }

    /// Everything a round of settling can change, to tell when it changes no more.
    private func look() -> [String] {
        var seen: [String] = []
        for account in cloud.accounts {
            for zone in cloud.zoneNames(account: account) {
                seen.append(zone)
                seen += cloud.records(zone: zone, account: account).map { "\($0.name) \($0.changeTag ?? "")" }
            }
        }
        for device in devices {
            let side = device.toySide
            seen.append("\(device.name) \(side.isChanged) \(side.base?.changeTag ?? "-") \(side.held?.record.changeTag ?? "-") \(side.lastSend.map { "\($0)" } ?? "-")")
            seen.append("\(device.name) \(device.history.plays.map(\.playID)) \(device.history.unreadable) \(device.zoneNote.map { "\($0)" } ?? "-")")
            seen.append("\(device.name) \(device.engine.state.pending) \(device.engine.state.pendingZoneSaves) \(device.engine.lateAnswers.count)")
        }
        return seen
    }

    // MARK: What iCloud holds

    /// The zone the person's devices use, when they all agree on one.
    var personsZone: String? {
        let zones = Set(devices.filter { $0.account == World.person }.map { $0.zoneNote?.zone.name })
        guard zones.count == 1, let zone = zones.first else { return nil }
        return zone
    }

    /// The finished plays iCloud holds in `zone`, the person's devices' zone by default, as a history.
    func historyInICloud(account: String = World.person, zone: String? = nil) -> PlayHistory {
        var history = PlayHistory()
        guard let zone = zone ?? personsZone else { return history }
        for record in cloud.records(zone: zone, account: account) where record.type == CloudRecord.finishedPlayType {
            if let format = record.format, let payload = record.payload,
               let read = FinishedPlayPayload(format: format, payload: payload, recordName: record.name) {
                history.plays.append(read.play)
            } else {
                history.unreadable += 1
            }
        }
        history.plays.sort { ($0.finishedAt, $0.playID.uuidString) > ($1.finishedAt, $1.playID.uuidString) }
        return history
    }

    /// The toy iCloud holds in `zone`, the person's devices' zone by default.
    func toyInICloud(account: String = World.person, zone: String? = nil) -> ToyPayload? {
        guard let zone = zone ?? personsZone else { return nil }
        return cloud.record(.toy(in: zone), account: account).flatMap { record in
            if case .readable(let payload) = ToyPayload.reading(format: record.format, payload: record.payload) { payload } else { nil }
        }
    }

    // MARK: The checks

    /// What the ledger of plays finds at the end, once the devices have settled: a play finished under the person's
    /// account that iCloud lacks, though no clearing, purge or loss the design lets go took it since (failure 1); and,
    /// with `clearingsHold`, for an order in which no case the design accepts can bring a cleared play back, a cleared
    /// play that iCloud holds again (failure 3). Only when the person's devices agree on one zone.
    func playsLostOrBack(clearingsHold: Bool) -> [String] {
        guard let zone = personsZone, cloud.hasZone(zone, account: World.person) else { return [] }
        let inICloud = Set(cloud.records(zone: zone, account: World.person).compactMap { $0.playID?.uuidString })
        var problems = watcher.playsLost(account: World.person, inICloud: inICloud).map { "the play \($0.prefix(8)) was lost" }
        if clearingsHold, cloud.zoneNames(account: World.person).count == 1 {
            watcher.tally.count("checked that no cleared play came back")
            problems += watcher.clearedPlaysBack(inICloud: inICloud).map { "the cleared play \($0.prefix(8)) came back" }
        }
        return problems
    }

    /// What breaks the agreement of the person's devices once they have all synced and had their sending moments: every
    /// device signed in to the person's account uses the same zone, which exists, shows the history iCloud holds there,
    /// keeps iCloud's toy, holds no toy, and marks nothing as not yet received.
    func disagreements() -> [String] {
        var problems: [String] = []
        let persons = devices.filter { $0.account == World.person }
        guard !persons.isEmpty else { return [] }
        if persons.allSatisfy({ $0.zoneNote == nil || $0.zoneNote?.knowledge == .deleted }) {
            // No device uses a zone: then none has anything to send, and none shows a play.
            for device in persons where device.hasMarks || !device.history.plays.isEmpty || device.history.unreadable > 0 {
                problems.append("\(device.name) uses no zone and still has plays or marks")
            }
            return problems
        }
        guard let zone = personsZone else {
            return ["the person's devices use different zones: \(persons.map { "\($0.name) \($0.zoneNote.map { "\($0)" } ?? "none")" })"]
        }
        if !cloud.hasZone(zone, account: World.person) { problems.append("the zone the devices use does not exist") }
        let history = historyInICloud(zone: zone)
        let toy = toyInICloud(zone: zone)
        for device in persons {
            if device.zoneNote?.knowledge != .existing { problems.append("\(device.name) does not know its zone to exist") }
            let shown = device.history
            let sortedShown = shown.plays.sorted { ($0.finishedAt, $0.playID.uuidString) > ($1.finishedAt, $1.playID.uuidString) }
            if sortedShown != history.plays || shown.unreadable != history.unreadable {
                problems.append("\(device.name) shows \(shown.plays.count) plays and \(shown.unreadable) unread; iCloud holds \(history.plays.count) and \(history.unreadable)")
            }
            if device.toySide.isChanged, device.toyRefusedWithoutRecord {
                // Accepted (section 16): CloudKit refused the toy's save without its record, and no fetch brings the toy,
                // so the device tries again at most once a minute, and its toy does not reach iCloud.
                watcher.tally.count("accepted: a toy refused without its record that no fetch brings")
            } else {
                if let toy, let kept = device.keptToy, !kept.isSameToy(as: toy.toy) {
                    problems.append("\(device.name) keeps another toy than iCloud's")
                }
                if device.toySide.isChanged { problems.append("\(device.name) still marks the toy as changed") }
            }
            if device.toySide.held != nil { problems.append("\(device.name) still holds a toy") }
            if device.marksPlays { problems.append("\(device.name) still marks plays iCloud has not received") }
        }
        return problems
    }
}
