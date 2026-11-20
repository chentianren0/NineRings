#if DEBUG
import CloudKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The probe's questions, numbered as in `docs/icloud-probe.md`. Each makes its own zone and its own devices, from
/// nothing unless the question is about a saved state, and deletes the zone at its end. A question's `RESULT` lines say
/// what it saw; the timeline above them shows every event.
nonisolated struct ProbeRun: Sendable {
    static let zonePrefix = "NineRingsProbe_"

    let database: CKDatabase
    let report: ProbeReport
    /// A short id of this run, part of every zone's name.
    let run: String

    static let questions: [Int: String] = [
        1: "A first save under a record name that exists, from an engine that never fetched it",
        2: "A save with stale system fields",
        3: "What a saved record carries",
        4: "An engine's own save coming back as a fetched change",
        5: "A record deleted, then saved again under the same name",
        6: "Deleting a record that is already gone",
        7: "Saving into a zone that does not exist",
        8: "A fetch from nothing, in a zone where records were deleted",
        9: "A zone deleted by one engine",
        10: "The account event of a new engine",
        11: "Automatic syncing",
        12: "Two engines from copies of one saved state",
        13: "The field types CloudKit gives encrypted values",
        14: "A fetch when the app comes to the front",
        15: "A zone deleted and made again under the same name",
    ]

    func ask(_ question: Int) async {
        guard let title = Self.questions[question] else {
            return await report.say("--", "no question \(question)")
        }
        await report.heading("\(question). \(title)")
        switch question {
        case 1: await q1()
        case 2: await q2()
        case 3: await q3()
        case 4: await q4()
        case 5: await q5()
        case 6: await q6()
        case 7: await q7()
        case 8: await q8()
        case 9: await q9()
        case 10: await q10()
        case 11: await q11()
        case 12: await q12()
        case 13: await q13()
        case 14: await q14()
        case 15: await q15()
        default: break
        }
    }

    // MARK: 1. A first save under a name that exists

    private func q1() async {
        let zone = zone(1)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        let play = playID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the first toy")
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play")
        await a.send()

        // B never fetched: it knows nothing of the zone or the records.
        let mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: nil, payload: "B: a toy, never having fetched")
        await b.queueSave(play, type: "FinishedPlay", base: nil, payload: "B: the same play")
        await b.send()
        let events = await b.events(since: mark)
        for failure in failedSaves(events) {
            await report.result(1, "B's first save of \(failure.record.recordType) was refused: \(ProbeText.error(failure.error))")
        }
        for saved in savedRecords(events) {
            await report.result(1, "B's first save of \(saved.recordType) was accepted: \(ProbeText.record(saved))")
        }
        await report.result(1, "B's pending changes after the refusal: \(await b.pendingText)")

        // The design's answer to a refused toy: save again on the system fields of the record that came back.
        if let server = failedSaves(events).first(where: { $0.record.recordID == toy })?.error.serverRecord {
            let again = await b.mark
            await b.queueSave(toy, type: "Toy", base: server, payload: "B: kept, on the record that came back")
            await b.send()
            await report.result(1, "B's save on the returned record's system fields: \(outcome(of: toy, in: await b.events(since: again)))")
        }
        await finish(zone, [a, b])
    }

    // MARK: 2. Stale system fields

    private func q2() async {
        let zone = zone(2)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: first")
        await a.send()
        await b.fetch()
        let first = await b.known[toy]
        await report.result(2, "B fetched the toy: \(ProbeText.record(first))")
        await a.queueSave(toy, type: "Toy", base: await a.known[toy], payload: "A: second")
        await a.send()
        let second = await a.known[toy]
        await report.result(2, "A changed the toy: \(ProbeText.record(second))")

        let mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: first, payload: "B: on the first toy's system fields")
        await b.send()
        let events = await b.events(since: mark)
        if let failure = failedSaves(events).first {
            await report.result(2, "B's stale save was refused: \(ProbeText.error(failure.error))")
            let ck = failure.error
            await report.result(2, "serverRecord is A's second toy: \(ck.serverRecord?.recordChangeTag == second?.recordChangeTag); ancestorRecord is B's base: \(ck.ancestorRecord?.recordChangeTag == first?.recordChangeTag)")
        } else {
            await report.result(2, "B's stale save was not refused: \(outcome(of: toy, in: events))")
        }
        await finish(zone, [a, b])
    }

    // MARK: 3. What a saved record carries

    private func q3() async {
        let zone = zone(3)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave()
        let mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: a toy to look at")
        await a.send()
        let saved = savedRecords(await a.events(since: mark)).first { $0.recordID == toy }
        let handed = await a.handed[toy]
        if let saved {
            await report.result(3, "the saved record: \(ProbeText.record(saved))")
            await report.result(3, "its details: \(ProbeText.recordDetails(saved))")
            await report.result(3, "it is the very object handed to the engine: \(saved === handed)")
            let format: Int? = saved.encryptedValues["format"]
            let payload: Data? = saved.encryptedValues["payload"]
            await report.result(3, "its encrypted values read back: format \(format.map(String.init) ?? "none"), payload \(payload.map { "\($0.count) bytes" } ?? "none")")
            let plain = saved["payload"] as? Data
            await report.result(3, "payload read as a plain field: \(plain.map { "\($0.count) bytes" } ?? "none")")
            let fields = ProbeText.systemFields(of: saved)
            let rebuilt = ProbeText.record(systemFields: fields)
            await report.result(3, "its system fields archive in \(fields.count) bytes; rebuilt from them: \(ProbeText.record(rebuilt))")
        } else {
            await report.result(3, "no saved record came back")
        }
        await b.fetch()
        if let fetched = await b.known[toy] {
            await report.result(3, "the same record fetched by B: \(ProbeText.record(fetched))")
            await report.result(3, "its details: \(ProbeText.recordDetails(fetched))")
        }
        await finish(zone, [a, b])
    }

    // MARK: 4. An engine's own save coming back

    private func q4() async {
        let zone = zone(4)
        let a = await device("A", zone)
        let toy = toyID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: saved, then fetched")
        await a.send()
        let tag = await a.known[toy]?.recordChangeTag
        let mark = await a.mark
        await a.fetch("after its own save")
        let back = fetchedRecords(await a.events(since: mark)).filter { $0.recordID == toy }
        await report.result(4, "A's fetch after its own save delivered its own record \(back.count) times\(back.isEmpty ? "" : ", with the saved tag: \(back.allSatisfy { $0.recordChangeTag == tag })")")

        // A send and a fetch asked for together, the fetch a little later each round, so that some fetch reads the
        // server while the save has landed but its answer is still on its way: which comes first?
        for round in 1...8 {
            let start = await a.mark
            let delay = Duration.milliseconds(100 * (round - 1))
            await a.queueSave(toy, type: "Toy", base: await a.known[toy], payload: "A: round \(round)")
            async let sending: Void = a.send("round \(round)")
            async let fetching: Void = {
                try? await Task.sleep(for: delay)
                await a.fetch("round \(round), \(delay) after the send")
            }()
            _ = await (sending, fetching)
            let events = await a.events(since: start)
            let savedAt = events.firstIndex { logged in
                if case .sentRecordZoneChanges(let sent) = logged.event { sent.savedRecords.contains { $0.recordID == toy } } else { false }
            }
            let savedTag = savedRecords(events).first { $0.recordID == toy }?.recordChangeTag
            let fetchedAt = events.firstIndex { logged in
                if case .fetchedRecordZoneChanges(let changes) = logged.event {
                    changes.modifications.contains { $0.record.recordID == toy && $0.record.recordChangeTag == savedTag }
                } else { false }
            }
            let order = switch (savedAt, fetchedAt) {
            case (let saved?, let fetched?): fetched < saved ? "the fetched change came BEFORE the confirmation" : "the confirmation came first, then the fetched change"
            case (.some, nil): "the save was confirmed and not fetched back"
            case (nil, .some): "the change was fetched and never confirmed"
            case (nil, nil): "neither a confirmation nor a fetched change"
            }
            await report.result(4, "round \(round): \(order)")
        }
        await finish(zone, [a])
    }

    // MARK: 5. Deleted, then saved again under the same name

    private func q5() async {
        let zone = zone(5)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy before its deletion")
        await a.send()
        guard let original = await a.known[toy] else { return await finish(zone, [a, b]) }
        await b.fetch()
        await a.queueDelete(toy)
        await a.send()

        var mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: original, payload: "A: again, on the deleted record's system fields")
        await a.send()
        await report.result(5, "saved again WITH the deleted record's system fields: \(outcome(of: toy, in: await a.events(since: mark)))")
        await report.result(5, "A's pending changes after it: \(await a.pendingText)")

        mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: again, without system fields")
        await a.send()
        let renewed = savedRecords(await a.events(since: mark)).first { $0.recordID == toy }
        await report.result(5, "saved again WITHOUT system fields: \(outcome(of: toy, in: await a.events(since: mark)))")
        if let renewed {
            await report.result(5, "a new record: creation date differs from the first: \(renewed.creationDate != original.creationDate)")
        }

        mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: await b.known[toy], payload: "B: on the system fields of the record that was deleted")
        await b.send()
        await report.result(5, "B, holding the deleted record's system fields, saves after the record was made again: \(outcome(of: toy, in: await b.events(since: mark)))")

        mark = await b.mark
        await b.fetch("after the deletion and the new record")
        let events = await b.events(since: mark)
        await report.result(5, "B's fetch then delivered: modifications \(fetchedRecords(events).map { ProbeText.record($0) }), deletions \(fetchedDeletions(events).map { ProbeText.short($0.recordID) })")

        // The engine's own list: a deletion queued, then a save of the same record.
        await a.queueDelete(toy)
        await a.queueSave(toy, type: "Toy", base: await a.known[toy], payload: "A: a save queued after a deletion")
        await report.result(5, "a deletion then a save queued for one record leave pending: \(await a.pendingText)")
        await a.send()
        await finish(zone, [a, b])
    }

    // MARK: 6. Deleting what is already gone

    private func q6() async {
        let zone = zone(6)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let play = playID(zone)
        await a.queueZoneSave()
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play to delete twice")
        await a.send()
        await b.fetch()
        await a.queueDelete(play)
        await a.send()

        var mark = await b.mark
        await b.queueDelete(play)
        await b.send()
        await report.result(6, "B deletes the play A has deleted: \(deleteOutcome(of: play, in: await b.events(since: mark)))")
        await report.result(6, "B's pending changes after it: \(await b.pendingText)")

        let never = playID(zone)
        mark = await b.mark
        await b.queueDelete(never)
        await b.send()
        await report.result(6, "B deletes a record that never existed: \(deleteOutcome(of: never, in: await b.events(since: mark)))")
        await finish(zone, [a, b])
    }

    // MARK: 7. A zone that does not exist

    private func q7() async {
        let zone = zone(7)
        let a = await device("A", zone)
        let play = playID(zone)
        var mark = await a.mark
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play in a zone never made")
        await a.send("no zone queued")
        await report.result(7, "a save into a zone that does not exist: \(outcome(of: play, in: await a.events(since: mark)))")
        await report.result(7, "A's pending changes after it: \(await a.pendingText)")

        mark = await a.mark
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: the play again, the zone queued after it")
        await a.queueZoneSave()
        await a.send("the record queued first, then the zone")
        await report.result(7, "the order of what was sent: \(order(await a.events(since: mark)))")
        await report.result(7, "the save: \(outcome(of: play, in: await a.events(since: mark)))")
        await finish(zone, [a])

        // The other order, in a zone of its own.
        let other = CKRecordZone(zoneName: zone.zoneID.zoneName + "b")
        let c = ProbeDevice(name: "C", database: database, zone: other, report: report)
        await c.start(state: nil, automaticallySync: false)
        let otherPlay = playID(other)
        mark = await c.mark
        await c.queueZoneSave()
        await c.queueSave(otherPlay, type: "FinishedPlay", base: nil, payload: "C: the zone queued first, then the play")
        await c.send("the zone queued first, then the record")
        await report.result(7, "the other order: \(order(await c.events(since: mark)))")
        await finish(other, [c])
    }

    // MARK: 8. A fetch from nothing where records were deleted

    private func q8() async {
        let zone = zone(8)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let aPlays = [playID(zone), playID(zone), playID(zone)]
        let bPlays = [playID(zone), playID(zone)]
        await a.queueZoneSave()
        for (index, id) in aPlays.enumerated() {
            await a.queueSave(id, type: "FinishedPlay", base: nil, payload: "A: play \(index + 1)")
        }
        await a.send()
        for (index, id) in bPlays.enumerated() {
            await b.queueSave(id, type: "FinishedPlay", base: nil, payload: "B: play \(index + 1)")
        }
        await b.send()
        await a.fetch()
        // A deletes one of its own plays and one of B's.
        await a.queueDelete(aPlays[0])
        await a.queueDelete(bPlays[0])
        await a.send()

        let c = await device("C", zone)
        let mark = await c.mark
        await c.fetch("a new engine with no state")
        let events = await c.events(since: mark)
        let deleted = Set(fetchedDeletions(events).map(\.recordID))
        let fetched = Set(fetchedRecords(events).map(\.recordID))
        await report.result(8, "C fetched \(fetched.count) records (expected the 3 still there: \(fetched == Set([aPlays[1], aPlays[2], bPlays[1]])))")
        await report.result(8, "C was told of the deletion of A's own play (created and deleted by A): \(deleted.contains(aPlays[0]))")
        await report.result(8, "C was told of the deletion of B's play (created by B, deleted by A): \(deleted.contains(bPlays[0]))")
        await report.result(8, "deletions delivered to C in all: \(deleted.count)")
        await finish(zone, [a, b, c])
    }

    // MARK: 9. A zone deleted by one engine

    private func q9() async {
        let zone = zone(9)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: a toy in a zone about to go")
        await a.send()
        await b.fetch()
        await a.queueZoneDelete()
        await a.send()

        var mark = await b.mark
        await b.fetch("after A deleted the zone")
        var events = await b.events(since: mark)
        await report.result(9, "B, which knew the zone, was told: zone deletions \(zoneDeletions(events).map { "\(ProbeText.zone($0.zoneID)) reason=\(ProbeText.reason($0.reason))" }), record deletions \(fetchedDeletions(events).map { ProbeText.short($0.recordID) })")

        mark = await a.mark
        await a.fetch("A itself, after deleting the zone")
        events = await a.events(since: mark)
        await report.result(9, "A, which deleted it, was told: zone deletions \(zoneDeletions(events).map { "\(ProbeText.zone($0.zoneID)) reason=\(ProbeText.reason($0.reason))" })")

        let c = await device("C", zone)
        mark = await c.mark
        await c.fetch("a new engine with no state")
        events = await c.events(since: mark)
        let probeZones = zoneDeletions(events).filter { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }
        await report.result(9, "C, new, was told of this zone's deletion: \(probeZones.contains { $0.zoneID == zone.zoneID }); of the probe's zone deletions in all: \(probeZones.map { "\($0.zoneID.zoneName) reason=\(ProbeText.reason($0.reason))" })")
        await report.result(9, "C was told of zones that exist: \(events.flatMap { logged -> [String] in if case .fetchedDatabaseChanges(let changes) = logged.event { changes.modifications.map { ProbeText.zone($0.zoneID) } } else { [] } })")
        await finish(zone, [a, b, c], deleteZone: false)
    }

    // MARK: 10. The account event of a new engine

    private func q10() async {
        let zone = zone(10)
        let userID = try? await CKContainer(identifier: CloudProbe.container).userRecordID()
        await report.result(10, "CKContainer.userRecordID() is \(userID.map { ProbeText.user($0) } ?? "not known")")
        for automatic in [false, true] {
            let fresh = await device(automatic ? "N2" : "N1", zone, automatic: automatic)
            try? await Task.sleep(for: .seconds(8))
            var changes = accountChanges(await fresh.events(since: 0))
            if changes.isEmpty, !automatic {
                await fresh.fetch("to see whether a first operation brings it")
                changes = accountChanges(await fresh.events(since: 0))
            }
            await report.result(10, "a new engine with automatic syncing \(automatic ? "on" : "off") delivered: \(describe(changes, comparedWith: userID))")
            if !automatic, let state = await fresh.serialization {
                await fresh.stop()
                let again = await device("N3", zone, state: state)
                try? await Task.sleep(for: .seconds(8))
                await report.result(10, "an engine made from N1's saved state delivered: \(describe(accountChanges(await again.events(since: 0)), comparedWith: userID))")
                await again.stop()
            } else {
                await fresh.stop()
            }
        }
        await removeZone(zone)
    }

    // MARK: 11. Automatic syncing

    private func q11() async {
        let zone = zone(11)
        await report.result(11, "before this question's engines: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")
        let manual = await device("M", zone)
        await manual.fetch("an engine with automatic syncing off, once")
        try? await Task.sleep(for: .seconds(5))
        await report.result(11, "after an engine with automatic syncing off fetched once: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")
        await manual.stop()
        let a = await device("A", zone, automatic: true)
        let b = await device("B", zone, automatic: true)
        try? await Task.sleep(for: .seconds(15))
        await report.result(11, "15 s after two engines with automatic syncing were made: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")

        let toy = toyID(zone)
        let aMark = await a.mark
        let bMark = await b.mark
        let queued = ContinuousClock.now
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: sent by the engine's own schedule")
        let sent = await waitFor(a, since: aMark, seconds: 120) { logged in
            if case .sentRecordZoneChanges(let sent) = logged.event { sent.savedRecords.contains { $0.recordID == toy } } else { false }
        }
        if let sent {
            await report.result(11, "A's engine sent the queued toy by itself after \(format(sent.at - queued))")
        } else {
            await report.result(11, "A's engine did not send the queued toy within 120 s")
        }
        let fetched = await waitFor(b, since: bMark, seconds: 240) { logged in
            if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.modifications.contains { $0.record.recordID == toy } } else { false }
        }
        if let fetched, let sent {
            await report.result(11, "B's engine fetched A's toy by itself \(format(fetched.at - sent.at)) after A's save was confirmed")
        } else {
            await report.result(11, "B's engine did not fetch A's toy by itself within 240 s")
            await b.fetch("by hand, to see whether the toy is there")
        }
        let reasons = await b.events(since: bMark).compactMap { logged -> String? in
            if case .willFetchChanges(let will) = logged.event { "\(will.context.reason) at \(ProbeText.decimal(report.seconds(at: logged.at), places: 1)) s" } else { nil }
        }
        await report.result(11, "B's fetches meanwhile: \(reasons)")
        let ownBack = fetchedRecords(await a.events(since: aMark)).filter { $0.recordID == toy }.count
        await report.result(11, "A's own toy came back to A in its own fetches \(ownBack) times")
        await report.result(11, "at the end: registered for remote notifications \(await registeredForPushes())")
        await finish(zone, [a, b])
    }

    // MARK: 12. Two engines from one saved state

    private func q12() async {
        let zone = zone(12)
        let a = await device("A", zone)
        let toy = toyID(zone)
        let play = playID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy before the backup")
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play before the backup")
        await a.send()
        await a.fetch()
        // A play finished but not yet sent when the backup was made.
        let unsent = playID(zone)
        let mark = await a.mark
        await a.queueSave(unsent, type: "FinishedPlay", base: nil, payload: "A: a play not yet sent at the backup")
        _ = await waitFor(a, since: mark, seconds: 10) { logged in
            if case .stateUpdate = logged.event { true } else { false }
        }
        guard let state = await a.serialization, let base = await a.known[toy] else {
            await report.result(12, "A handed over no state")
            return await finish(zone, [a])
        }
        await a.stop()

        let one = await device("A1", zone, state: state)
        let two = await device("A2", zone, state: state)
        await one.copyStore(from: a)
        await two.copyStore(from: a)
        await report.result(12, "both copies start with pending: A1 \(await one.pendingText); A2 \(await two.pendingText)")

        var marks = (await one.mark, await two.mark)
        await one.queueSave(toy, type: "Toy", base: base, payload: "A1: the toy after the backup")
        await one.send()
        await two.queueSave(toy, type: "Toy", base: base, payload: "A2: the toy after the backup")
        await two.send()
        await report.result(12, "A1's sends: toy \(outcome(of: toy, in: await one.events(since: marks.0))); the unsent play \(outcome(of: unsent, in: await one.events(since: marks.0)))")
        await report.result(12, "A2's sends: toy \(outcome(of: toy, in: await two.events(since: marks.1))); the unsent play \(outcome(of: unsent, in: await two.events(since: marks.1)))")

        let onePlay = playID(zone)
        let twoPlay = playID(zone)
        await one.queueSave(onePlay, type: "FinishedPlay", base: nil, payload: "A1: a play after the backup")
        await one.send()
        await two.queueSave(twoPlay, type: "FinishedPlay", base: nil, payload: "A2: a play after the backup")
        await two.send()

        marks = (await one.mark, await two.mark)
        await one.fetch()
        await two.fetch()
        for (copy, mark) in [(one, marks.0), (two, marks.1)] {
            let events = await copy.events(since: mark)
            let errors = events.compactMap { logged -> String? in
                if case .didFetchRecordZoneChanges(let did) = logged.event, let error = did.error { ProbeText.error(error) } else { nil }
            }
            await report.result(12, "\(copy.name)'s fetch delivered \(fetchedRecords(events).map { ProbeText.record($0) }), deletions \(fetchedDeletions(events).count), errors \(errors)")
        }
        await finish(zone, [one, two])
    }

    // MARK: 13. Field types

    private func q13() async {
        await report.result(13, "the app cannot read the schema. Every question above saved Toy and FinishedPlay records with format (an Int through encryptedValues) and payload (Data through encryptedValues); `xcrun cktool export-schema` for the development environment shows the types CloudKit gave them.")
        // Saving one record of each type here as well, so that this question alone leaves them in the schema.
        let zone = zone(13)
        let a = await device("A", zone)
        await a.queueZoneSave()
        await a.queueSave(toyID(zone), type: "Toy", base: nil, payload: "A: a toy for the schema")
        await a.queueSave(playID(zone), type: "FinishedPlay", base: nil, payload: "A: a play for the schema")
        await a.send()
        await finish(zone, [a])
    }

    // MARK: 14. Coming to the front

    private func q14() async {
        #if os(macOS)
        let zone = zone(14)
        let a = await device("A", zone, automatic: true)
        try? await Task.sleep(for: .seconds(15))
        let mark = await a.mark
        let active = await MainActor.run { NSApplication.shared.isActive }
        await report.say("--", "the app is \(active ? "active" : "not active"); hiding it")
        await MainActor.run { NSApplication.shared.hide(nil) }
        try? await Task.sleep(for: .seconds(5))
        let hiddenFetches = await a.events(since: mark).filter { if case .willFetchChanges = $0.event { true } else { false } }.count
        let shownMark = await a.mark
        let shown = ContinuousClock.now
        await MainActor.run {
            NSApplication.shared.unhide(nil)
            NSApplication.shared.activate()
        }
        try? await Task.sleep(for: .seconds(2))
        let nowActive = await MainActor.run { NSApplication.shared.isActive }
        await report.say("--", "unhidden and asked to activate: the app is \(nowActive ? "active" : "not active")")
        let fetch = await waitFor(a, since: shownMark, seconds: 30) { logged in
            if case .willFetchChanges = logged.event { true } else { false }
        }
        await report.result(14, "fetches while hidden: \(hiddenFetches); the app became active again: \(nowActive)")
        if let fetch, case .willFetchChanges(let will) = fetch.event {
            await report.result(14, "the engine began a fetch \(format(fetch.at - shown)) after the app was brought back, reason \(will.context.reason)")
        } else {
            await report.result(14, "the engine began no fetch within 30 s of the app being brought back")
        }

        // macOS lets an app become active only when the active app yields, so a probe whose app is behind another
        // cannot bring itself to the front. The system's notifications of becoming active, posted by the probe itself,
        // show at least whether the engine fetches when it hears them.
        let postedMark = await a.mark
        let posted = ContinuousClock.now
        await report.say("--", "posting NSApplication.willBecomeActiveNotification and didBecomeActiveNotification, as the system does when the app comes to the front")
        await MainActor.run {
            NotificationCenter.default.post(name: NSApplication.willBecomeActiveNotification, object: NSApplication.shared)
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        }
        let heard = await waitFor(a, since: postedMark, seconds: 30) { logged in
            if case .willFetchChanges = logged.event { true } else { false }
        }
        if let heard, case .willFetchChanges(let will) = heard.event {
            await report.result(14, "after the posted notifications (not a real return to the front), the engine began a fetch \(format(heard.at - posted)) later, reason \(will.context.reason)")
        } else {
            await report.result(14, "after the posted notifications (not a real return to the front), the engine began no fetch within 30 s")
        }
        await finish(zone, [a])
        #else
        await report.result(14, "asked on the Mac only")
        #endif
    }

    // MARK: 15. A zone deleted and made again

    private func q15() async {
        let zone = zone(15)
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy in the first zone")
        await a.send()
        await b.fetch("B learns the zone before it goes")
        await a.queueZoneDelete()
        await a.send()
        await a.queueZoneSave()
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy in the zone made again")
        await a.send("the zone made again")
        let first = await b.known[toy]
        let again = await a.known[toy]
        await report.result(15, "the toy B holds, from the first zone: tag \(first?.recordChangeTag ?? "none"); the toy in the zone made again: tag \(again?.recordChangeTag ?? "none"); the same tag: \(first?.recordChangeTag == again?.recordChangeTag)")

        // B, which never saw the new toy, saves on the system fields of the toy from the first zone.
        let mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: first, payload: "B: on the first zone's toy, never having seen the new one")
        await b.send("on the first zone's toy")
        await report.result(15, "B's save on the first zone's toy, after the zone was made again: \(outcome(of: toy, in: await b.events(since: mark)))")

        let c = await device("C", zone)
        for (peer, note) in [(b, "B, which knew the first zone and missed its deletion"), (c, "C, a new engine with no state")] {
            let mark = await peer.mark
            await peer.fetch(note)
            let events = await peer.events(since: mark)
            let changes = events.compactMap { logged -> String? in
                switch logged.event {
                case .fetchedDatabaseChanges(let changes):
                    let modified = changes.modifications.filter { $0.zoneID == zone.zoneID }.count
                    let deleted = changes.deletions.filter { $0.zoneID == zone.zoneID }.map { ProbeText.reason($0.reason) }
                    return "database changes: this zone modified \(modified) times, deleted \(deleted)"
                case .fetchedRecordZoneChanges(let changes):
                    return "record changes: \(changes.modifications.map { ProbeText.record($0.record) }), deletions \(changes.deletions.map { ProbeText.short($0.recordID) })"
                case .didFetchRecordZoneChanges(let did) where did.error != nil:
                    return "zone fetch error: \(ProbeText.error(did.error))"
                default:
                    return nil
                }
            }
            await report.result(15, "\(peer.name) was told, in order: \(changes.joined(separator: " | "))")
        }
        await finish(zone, [a, b, c])

        // The same, but the toy in the zone made again is saved twice, so that its tag differs from B's.
        let other = CKRecordZone(zoneName: zone.zoneID.zoneName + "b")
        let d = ProbeDevice(name: "D", database: database, zone: other, report: report)
        let e = ProbeDevice(name: "E", database: database, zone: other, report: report)
        await d.start(state: nil, automaticallySync: false)
        await e.start(state: nil, automaticallySync: false)
        let otherToy = toyID(other)
        await d.queueZoneSave()
        await d.queueSave(otherToy, type: "Toy", base: nil, payload: "D: the toy in the first zone")
        await d.send()
        await e.fetch("E learns the zone before it goes")
        await d.queueZoneDelete()
        await d.send()
        await d.queueZoneSave()
        await d.queueSave(otherToy, type: "Toy", base: nil, payload: "D: the toy in the zone made again")
        await d.send("the zone made again")
        await d.queueSave(otherToy, type: "Toy", base: await d.known[otherToy], payload: "D: the toy changed once more")
        await d.send()
        let held = await e.known[otherToy]
        await report.result(15, "with different tags: E holds tag \(held?.recordChangeTag ?? "none"), the zone made again holds tag \(await d.known[otherToy]?.recordChangeTag ?? "none")")
        let otherMark = await e.mark
        await e.queueSave(otherToy, type: "Toy", base: held, payload: "E: on the first zone's toy")
        await e.send("on the first zone's toy")
        await report.result(15, "E's save on the first zone's toy, the tags differing: \(outcome(of: otherToy, in: await e.events(since: otherMark)))")
        await finish(other, [d, e])
    }

    // MARK: Helpers

    private func zone(_ question: Int) -> CKRecordZone {
        CKRecordZone(zoneName: "\(Self.zonePrefix)\(run)_q\(question)")
    }

    private func toyID(_ zone: CKRecordZone) -> CKRecord.ID {
        CKRecord.ID(recordName: "toy", zoneID: zone.zoneID)
    }

    private func playID(_ zone: CKRecordZone) -> CKRecord.ID {
        CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
    }

    private func device(_ name: String, _ zone: CKRecordZone, state: CKSyncEngine.State.Serialization? = nil, automatic: Bool = false) async -> ProbeDevice {
        let device = ProbeDevice(name: name, database: database, zone: zone, report: report)
        await device.start(state: state, automaticallySync: automatic)
        return device
    }

    /// Lets the devices go and deletes the question's zone.
    private func finish(_ zone: CKRecordZone, _ devices: [ProbeDevice], deleteZone: Bool = true) async {
        for device in devices { await device.stop() }
        if deleteZone { await removeZone(zone) }
    }

    /// Deletes `zone` directly, not through an engine, so that no engine of the probe hears of it.
    func removeZone(_ zone: CKRecordZone) async {
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            await report.say("--", "zone \(zone.zoneID.zoneName) deleted")
        } catch {
            await report.say("--", "zone \(zone.zoneID.zoneName) not deleted: \(ProbeText.error(error))")
        }
    }

    /// Deletes every zone of the probe in the database: those of earlier runs that stopped part way, and this run's.
    /// Says, before the probe makes any engine, whether the app is registered for remote notifications and which
    /// subscriptions the database holds.
    func describeStart() async {
        await report.say("--", "before any engine: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")
    }

    func removeProbeZones() async {
        do {
            let zones = try await database.allRecordZones().filter { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }
            guard !zones.isEmpty else { return await report.say("--", "no probe zones in the database") }
            _ = try await database.modifyRecordZones(saving: [], deleting: zones.map(\.zoneID))
            await report.say("--", "probe zones deleted: \(zones.map(\.zoneID.zoneName))")
        } catch {
            await report.say("--", "the probe zones could not be listed or deleted: \(ProbeText.error(error))")
        }
    }

    private func waitFor(
        _ device: ProbeDevice, since mark: Int, seconds: Double, _ predicate: @escaping @Sendable (ProbeDevice.Logged) -> Bool
    ) async -> ProbeDevice.Logged? {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let found = await device.events(since: mark).first(where: predicate) { return found }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private func registeredForPushes() async -> Bool {
        await MainActor.run {
            #if os(macOS)
            NSApplication.shared.isRegisteredForRemoteNotifications
            #else
            UIApplication.shared.isRegisteredForRemoteNotifications
            #endif
        }
    }

    private func subscriptionIDs() async -> String {
        do {
            return "\(try await database.allSubscriptions().map { "\($0.subscriptionID) (\(type(of: $0)))" })"
        } catch {
            return "not readable: \(ProbeText.error(error))"
        }
    }

    private func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return "\(ProbeText.decimal(seconds, places: 1)) s"
    }

    private func describe(_ changes: [CKSyncEngine.Event.AccountChange], comparedWith userID: CKRecord.ID?) -> String {
        guard !changes.isEmpty else { return "no account event" }
        return changes.map { change in
            let users: [CKRecord.ID] = switch change.changeType {
            case .signIn(let current): [current]
            case .signOut(let previous): [previous]
            case .switchAccounts(let previous, let current): [previous, current]
            @unknown default: []
            }
            let same = userID.map { id in users.map { $0 == id ? "the same as userRecordID()" : "not the same as userRecordID()" } } ?? []
            return "\(ProbeText.event(.accountChange(change))) \(same)"
        }.joined(separator: "; ")
    }

    /// What became of a save of `id` in `events`: accepted with the record that came back, or refused with the error.
    private func outcome(of id: CKRecord.ID, in events: [ProbeDevice.Logged]) -> String {
        if let saved = savedRecords(events).last(where: { $0.recordID == id }) {
            return "accepted: [\(ProbeText.record(saved))]"
        }
        if let failure = failedSaves(events).last(where: { $0.record.recordID == id }) {
            return "refused: \(ProbeText.error(failure.error))"
        }
        return "neither accepted nor refused"
    }

    private func deleteOutcome(of id: CKRecord.ID, in events: [ProbeDevice.Logged]) -> String {
        for logged in events.reversed() {
            guard case .sentRecordZoneChanges(let sent) = logged.event else { continue }
            if sent.deletedRecordIDs.contains(id) { return "reported as deleted" }
            if let error = sent.failedRecordDeletes[id] { return "refused: \(ProbeText.error(error))" }
        }
        return "neither reported deleted nor refused"
    }

    /// The order in which zones and records went out, and when the engine asked for the batch.
    private func order(_ events: [ProbeDevice.Logged]) -> String {
        events.compactMap { logged -> String? in
            switch logged.event {
            case .sentDatabaseChanges(let sent): "zones sent (saved \(sent.savedZones.count), failed \(sent.failedZoneSaves.count))"
            case .sentRecordZoneChanges(let sent): "records sent (saved \(sent.savedRecords.count), failed \(sent.failedRecordSaves.count))"
            default: nil
            }
        }.joined(separator: ", then ")
    }

    private func savedRecords(_ events: [ProbeDevice.Logged]) -> [CKRecord] {
        events.flatMap { logged -> [CKRecord] in
            if case .sentRecordZoneChanges(let sent) = logged.event { sent.savedRecords } else { [] }
        }
    }

    private func failedSaves(_ events: [ProbeDevice.Logged]) -> [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave] {
        events.flatMap { logged -> [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave] in
            if case .sentRecordZoneChanges(let sent) = logged.event { sent.failedRecordSaves } else { [] }
        }
    }

    private func fetchedRecords(_ events: [ProbeDevice.Logged]) -> [CKRecord] {
        events.flatMap { logged -> [CKRecord] in
            if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.modifications.map(\.record) } else { [] }
        }
    }

    private func fetchedDeletions(_ events: [ProbeDevice.Logged]) -> [CKDatabase.RecordZoneChange.Deletion] {
        events.flatMap { logged -> [CKDatabase.RecordZoneChange.Deletion] in
            if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.deletions } else { [] }
        }
    }

    private func zoneDeletions(_ events: [ProbeDevice.Logged]) -> [CKDatabase.DatabaseChange.Deletion] {
        events.flatMap { logged -> [CKDatabase.DatabaseChange.Deletion] in
            if case .fetchedDatabaseChanges(let changes) = logged.event { changes.deletions } else { [] }
        }
    }

    private func accountChanges(_ events: [ProbeDevice.Logged]) -> [CKSyncEngine.Event.AccountChange] {
        events.compactMap { logged in
            if case .accountChange(let change) = logged.event { change } else { nil }
        }
    }
}
#endif
