import Foundation
@testable import Records
import Testing

@MainActor
@Suite struct DebugTests {
    @Test(arguments: (ProcessInfo.processInfo.environment["SEEDS"] ?? "").split(separator: ",").compactMap { UInt64($0) })
    func dump(seed: UInt64) throws {
        let order = try RandomOrder(seed: seed)
        var lines: [String] = []
        if ProcessInfo.processInfo.environment["TRACE"] != nil {
            order.trace = { lines.append("T \($0)") }
            for device in order.world.devices { device.trace = { lines.append("T \($0)") } }
            order.world.cloud.trace = { lines.append("T \($0)") }
        }
        defer { try? lines.joined(separator: "\n").write(toFile: "/tmp/trace-\(seed).txt", atomically: true, encoding: .utf8) }
        order.run(steps: 160)
        _ = order.finish()
        print("SEED \(seed): \(order.choices)")
        print("ZONES \(order.world.cloud.zoneNames(account: World.person))")
        for device in order.world.devices {
            let run = device.sync.run
            print("DEV \(device.name) note=\(device.zoneNote.map { "\($0.zone.number)-\($0.zone.id.prefix(4)) \($0.knowledge)" } ?? "none") acct=\(device.account ?? "-") noted=\(device.notedAccount ?? "-") confirmed=\(run.accountConfirmed) gaveUp=\(run.gaveUpZone) writeFailed=\(run.writeFailed) counted=\(run.lastCountedFetchBegan.map(String.init) ?? "-") use=\(run.zoneUseBegan) notKnown=\(run.notKnownSince) noZone=\(run.noZoneSince) knowsNo=\(run.knowsNoAccount) pendingZones=\(device.engine.state.pendingZoneSaves.map { $0.prefix(14) }) pending=\(device.engine.state.pending.count) marks=\(device.hasMarks) held=\(String(describing: device.toySide.held?.kind)) plays=\(device.history.plays.count)")
        }
        for device in order.world.devices {
            let entries = (try? device.sync.store.allPlays()) ?? []
            print("PLAYS \(device.name) \(entries.map { "\($0.playID.uuidString.prefix(6)):\($0.sync):\($0.systemFieldsZone.map { String($0.prefix(14)) } ?? "nofields")" }.sorted())")
        }
        if let zone = order.world.personsZone {
            print("ICLOUD \(order.world.cloud.records(zone: zone, account: World.person).map { $0.name.prefix(6) })")
        }
        print("TALLY \(order.world.watcher.tally.counts)")
        print("DIS \(order.world.disagreements()) PROBLEMS \(order.world.watcher.problems)")
    }
}

@MainActor
@Suite struct ReachTests {
    @Test func whatTheOrdersReach() throws {
        guard ProcessInfo.processInfo.environment["REACH"] != nil else { return }
        var total: [String: Int] = [:]
        var zonesWithOneNumber = 0
        var accountSwitches = 0
        for seed in 0..<128 {
            let order = try RandomOrder(seed: UInt64(seed))
            order.run(steps: 160)
            _ = order.finish()
            for (key, value) in order.world.watcher.tally.counts { total[key, default: 0] += value }
            let numbers = order.world.cloud.zoneNames(account: World.person).compactMap { ZoneName($0)?.number }
            if Set(numbers).count < numbers.count { zonesWithOneNumber += 1 }
            if !order.world.cloud.zoneNames(account: World.other).isEmpty { accountSwitches += 1 }
        }
        for (key, value) in total.sorted(by: { $0.key < $1.key }) { print("REACH \(key): \(value)") }
        print("REACH seeds ending with two zones of one number: \(zonesWithOneNumber)")
        print("REACH seeds where the other account got a zone: \(accountSwitches)")
    }
}

@MainActor
@Suite struct SweepTests {
    @Test func sweep() throws {
        guard let range = ProcessInfo.processInfo.environment["SWEEP"]?.split(separator: "-").compactMap({ UInt64($0) }), range.count == 2 else { return }
        var failing: [String] = []
        for seed in range[0]..<range[1] {
            let order = try RandomOrder(seed: seed)
            order.run(steps: 160)
            let settled = order.finish()
            let problems = order.world.watcher.problems + order.world.disagreements()
            if !settled || !problems.isEmpty { failing.append("\(seed) settled=\(settled) \(problems)") }
        }
        for line in failing { print("FAIL \(line)") }
        print("SWEEP done, \(failing.count) failing")
    }
}
