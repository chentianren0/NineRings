#if DEBUG
import CloudKit
import Foundation
#if os(macOS)
import AppKit
#endif

/// The probe's numbered questions, as `docs/icloud-probe.md` lists them: records, accounts and scheduling. Each makes
/// its own zone, named after the question, and devices that fetch that zone alone.
nonisolated extension ProbeRun {
    // MARK: 1. A first save under a name that exists

    func q1() async {
        let zone = zone("q1")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        let play = playID(zone)
        await a.queueZoneSave(zone)
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
            await report.result("1", "B's first save of \(failure.record.recordType) was refused: \(ProbeText.error(failure.error))")
        }
        for saved in savedRecords(events) {
            await report.result("1", "B's first save of \(saved.recordType) was accepted: \(ProbeText.record(saved))")
        }
        await report.result("1", "B's pending changes after the refusal: \(await b.pendingText)")

        // The design's answer to a refused toy: save again on the system fields of the record that came back.
        if let server = failedSaves(events).first(where: { $0.record.recordID == toy })?.error.serverRecord {
            let again = await b.mark
            await b.queueSave(toy, type: "Toy", base: server, payload: "B: kept, on the record that came back")
            await b.send()
            await report.result("1", "B's save on the returned record's system fields: \(outcome(of: toy, in: await b.events(since: again)))")
        }
        await finish([zone], [a, b])
    }

    // MARK: 2. Stale system fields

    func q2() async {
        let zone = zone("q2")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave(zone)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: first")
        await a.send()
        await b.fetch()
        let first = await b.known[toy]
        await report.result("2", "B fetched the toy: \(ProbeText.record(first))")
        await a.queueSave(toy, type: "Toy", base: await a.known[toy], payload: "A: second")
        await a.send()
        let second = await a.known[toy]
        await report.result("2", "A changed the toy: \(ProbeText.record(second))")

        let mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: first, payload: "B: on the first toy's system fields")
        await b.send()
        let events = await b.events(since: mark)
        if let failure = failedSaves(events).first {
            await report.result("2", "B's stale save was refused: \(ProbeText.error(failure.error))")
            let ck = failure.error
            await report.result("2", "serverRecord is A's second toy: \(ck.serverRecord?.recordChangeTag == second?.recordChangeTag); ancestorRecord is B's base: \(ck.ancestorRecord?.recordChangeTag == first?.recordChangeTag)")
        } else {
            await report.result("2", "B's stale save was not refused: \(outcome(of: toy, in: events))")
        }
        await finish([zone], [a, b])
    }

    // MARK: 3. What a saved record carries

    func q3() async {
        let zone = zone("q3")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave(zone)
        let mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: a toy to look at")
        await a.send()
        let saved = savedRecords(await a.events(since: mark)).first { $0.recordID == toy }
        let handed = await a.handed[toy]
        if let saved {
            await report.result("3", "the saved record: \(ProbeText.record(saved))")
            await report.result("3", "its details: \(ProbeText.recordDetails(saved))")
            await report.result("3", "it is the very object handed to the engine: \(saved === handed)")
            let format: Int? = saved.encryptedValues["format"]
            let payload: Data? = saved.encryptedValues["payload"]
            await report.result("3", "its encrypted values read back: format \(format.map(String.init) ?? "none"), payload \(payload.map { "\($0.count) bytes" } ?? "none")")
            let plain = saved["payload"] as? Data
            await report.result("3", "payload read as a plain field: \(plain.map { "\($0.count) bytes" } ?? "none")")
            let fields = ProbeText.systemFields(of: saved)
            let rebuilt = ProbeText.record(systemFields: fields)
            await report.result("3", "its system fields archive in \(fields.count) bytes; rebuilt from them: \(ProbeText.record(rebuilt))")
        } else {
            await report.result("3", "no saved record came back")
        }
        await b.fetch()
        if let fetched = await b.known[toy] {
            await report.result("3", "the same record fetched by B: \(ProbeText.record(fetched))")
            await report.result("3", "its details: \(ProbeText.recordDetails(fetched))")
        }
        await finish([zone], [a, b])
    }

    // MARK: 4. An engine's own save coming back

    func q4() async {
        let zone = zone("q4")
        let a = await device("A", zone)
        let toy = toyID(zone)
        await a.queueZoneSave(zone)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: saved, then fetched")
        await a.send()
        let tag = await a.known[toy]?.recordChangeTag
        let mark = await a.mark
        await a.fetch("after its own save")
        let back = fetchedRecords(await a.events(since: mark)).filter { $0.recordID == toy }
        await report.result("4", "A's fetch after its own save delivered its own record \(back.count) times\(back.isEmpty ? "" : ", with the saved tag: \(back.allSatisfy { $0.recordChangeTag == tag })")")

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
            await report.result("4", "round \(round): \(order)")
        }
        await finish([zone], [a])
    }

    // MARK: 5. Deleted, then saved again under the same name

    func q5() async {
        let zone = zone("q5")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        await a.queueZoneSave(zone)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy before its deletion")
        await a.send()
        guard let original = await a.known[toy] else { return await finish([zone], [a, b]) }
        await b.fetch()
        await a.queueDelete(toy)
        await a.send()

        var mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: original, payload: "A: again, on the deleted record's system fields")
        await a.send()
        await report.result("5", "saved again WITH the deleted record's system fields: \(outcome(of: toy, in: await a.events(since: mark)))")
        await report.result("5", "A's pending changes after it: \(await a.pendingText)")

        mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: again, without system fields")
        await a.send()
        let renewed = savedRecords(await a.events(since: mark)).first { $0.recordID == toy }
        await report.result("5", "saved again WITHOUT system fields: \(outcome(of: toy, in: await a.events(since: mark)))")
        if let renewed {
            await report.result("5", "a new record: creation date differs from the first: \(renewed.creationDate != original.creationDate)")
        }

        mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: await b.known[toy], payload: "B: on the system fields of the record that was deleted")
        await b.send()
        await report.result("5", "B, holding the deleted record's system fields, saves after the record was made again: \(outcome(of: toy, in: await b.events(since: mark)))")

        mark = await b.mark
        await b.fetch("after the deletion and the new record")
        let events = await b.events(since: mark)
        await report.result("5", "B's fetch then delivered: modifications \(fetchedRecords(events).map { ProbeText.record($0) }), deletions \(fetchedDeletions(events).map { ProbeText.short($0.recordID) })")

        // The engine's own list: a deletion queued, then a save of the same record.
        await a.queueDelete(toy)
        await a.queueSave(toy, type: "Toy", base: await a.known[toy], payload: "A: a save queued after a deletion")
        await report.result("5", "a deletion then a save queued for one record leave pending: \(await a.pendingText)")
        await a.send()
        await finish([zone], [a, b])
    }

    // MARK: 6. Deleting what is already gone

    func q6() async {
        let zone = zone("q6")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let play = playID(zone)
        await a.queueZoneSave(zone)
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play to delete twice")
        await a.send()
        await b.fetch()
        await a.queueDelete(play)
        await a.send()

        var mark = await b.mark
        await b.queueDelete(play)
        await b.send()
        await report.result("6", "B deletes the play A has deleted: \(deleteOutcome(of: play, in: await b.events(since: mark)))")
        await report.result("6", "B's pending changes after it: \(await b.pendingText)")

        let never = playID(zone)
        mark = await b.mark
        await b.queueDelete(never)
        await b.send()
        await report.result("6", "B deletes a record that never existed: \(deleteOutcome(of: never, in: await b.events(since: mark)))")
        await finish([zone], [a, b])
    }

    // MARK: 7. A zone that does not exist

    func q7() async {
        let zone = zone("q7")
        let a = await device("A", zone)
        let play = playID(zone)
        var mark = await a.mark
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play in a zone never made")
        await a.send("no zone queued")
        await report.result("7", "a save into a zone that does not exist: \(outcome(of: play, in: await a.events(since: mark)))")
        await report.result("7", "A's pending changes after it: \(await a.pendingText)")

        mark = await a.mark
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: the play again, the zone queued after it")
        await a.queueZoneSave(zone)
        await a.send("the record queued first, then the zone")
        await report.result("7", "the order of what was sent: \(order(await a.events(since: mark)))")
        await report.result("7", "the save: \(outcome(of: play, in: await a.events(since: mark)))")
        await finish([zone], [a])

        // The other order, in a zone of its own.
        let other = CKRecordZone(zoneName: zone.zoneID.zoneName + "b")
        let c = await device("C", other)
        let otherPlay = playID(other)
        mark = await c.mark
        await c.queueZoneSave(other)
        await c.queueSave(otherPlay, type: "FinishedPlay", base: nil, payload: "C: the zone queued first, then the play")
        await c.send("the zone queued first, then the record")
        await report.result("7", "the other order: \(order(await c.events(since: mark)))")
        await finish([other], [c])
    }

    // MARK: 8. A fetch from nothing where records were deleted

    func q8() async {
        let zone = zone("q8")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let aPlays = [playID(zone), playID(zone), playID(zone)]
        let bPlays = [playID(zone), playID(zone)]
        await a.queueZoneSave(zone)
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
        await report.result("8", "C fetched \(fetched.count) records (expected the 3 still there: \(fetched == Set([aPlays[1], aPlays[2], bPlays[1]])))")
        await report.result("8", "C was told of the deletion of A's own play (created and deleted by A): \(deleted.contains(aPlays[0]))")
        await report.result("8", "C was told of the deletion of B's play (created by B, deleted by A): \(deleted.contains(bPlays[0]))")
        await report.result("8", "deletions delivered to C in all: \(deleted.count)")
        await finish([zone], [a, b, c])
    }

    // MARK: 9. The account event of a new engine

    func q9() async {
        let zone = zone("q9")
        let userID = try? await CKContainer(identifier: CloudProbe.container).userRecordID()
        await report.result("9", "CKContainer.userRecordID() is \(userID.map { ProbeText.user($0) } ?? "not known")")
        for automatic in [false, true] {
            let fresh = await device(automatic ? "N2" : "N1", zone, automatic: automatic)
            try? await Task.sleep(for: .seconds(8))
            var changes = accountChanges(await fresh.events(since: 0))
            if changes.isEmpty, !automatic {
                await fresh.fetch("to see whether a first operation brings it")
                changes = accountChanges(await fresh.events(since: 0))
            }
            await report.result("9", "a new engine with automatic syncing \(automatic ? "on" : "off") delivered: \(describe(changes, comparedWith: userID))")
            if !automatic, let state = await fresh.serialization {
                await fresh.stop()
                let again = await device("N3", zone, state: state)
                try? await Task.sleep(for: .seconds(8))
                await report.result("9", "an engine made from N1's saved state delivered: \(describe(accountChanges(await again.events(since: 0)), comparedWith: userID))")
                await again.stop()
            } else {
                await fresh.stop()
            }
        }
        // No engine here saves the zone, so there is none to delete.
    }

    // MARK: 10. Automatic syncing

    func q10() async {
        let zone = zone("q10")
        await report.result("10", "before this question's engines: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")
        let manual = await device("M", zone)
        await manual.fetch("an engine with automatic syncing off, once")
        try? await Task.sleep(for: .seconds(5))
        await report.result("10", "after an engine with automatic syncing off fetched once: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")
        await manual.stop()
        let a = await device("A", zone, automatic: true)
        let b = await device("B", zone, automatic: true)
        try? await Task.sleep(for: .seconds(15))
        await report.result("10", "15 s after two engines with automatic syncing were made: registered for remote notifications \(await registeredForPushes()), the database's subscriptions \(await subscriptionIDs())")

        let toy = toyID(zone)
        let aMark = await a.mark
        let bMark = await b.mark
        let queued = ContinuousClock.now
        await a.queueZoneSave(zone)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: sent by the engine's own schedule")
        let sent = await waitFor(a, since: aMark, seconds: 120) { logged in
            if case .sentRecordZoneChanges(let sent) = logged.event { sent.savedRecords.contains { $0.recordID == toy } } else { false }
        }
        if let sent {
            await report.result("10", "A's engine sent the queued toy by itself after \(format(sent.at - queued))")
        } else {
            await report.result("10", "A's engine did not send the queued toy within 120 s")
        }
        let fetched = await waitFor(b, since: bMark, seconds: 240) { logged in
            if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.modifications.contains { $0.record.recordID == toy } } else { false }
        }
        if let fetched, let sent {
            await report.result("10", "B's engine fetched A's toy by itself \(format(fetched.at - sent.at)) after A's save was confirmed")
        } else {
            await report.result("10", "B's engine did not fetch A's toy by itself within 240 s")
            await b.fetch("by hand, to see whether the toy is there")
        }
        let reasons = await b.events(since: bMark).compactMap { logged -> String? in
            if case .willFetchChanges(let will) = logged.event { "\(will.context.reason) at \(ProbeText.decimal(report.seconds(at: logged.at), places: 1)) s" } else { nil }
        }
        await report.result("10", "B's fetches meanwhile: \(reasons)")
        let ownBack = fetchedRecords(await a.events(since: aMark)).filter { $0.recordID == toy }.count
        await report.result("10", "A's own toy came back to A in its own fetches \(ownBack) times")
        await report.result("10", "at the end: registered for remote notifications \(await registeredForPushes())")
        await finish([zone], [a, b])
    }

    // MARK: 11. Two engines from one saved state

    func q11() async {
        let zone = zone("q11")
        let a = await device("A", zone)
        let toy = toyID(zone)
        let play = playID(zone)
        await a.queueZoneSave(zone)
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
            await report.result("11", "A handed over no state")
            return await finish([zone], [a])
        }
        await a.stop()

        let one = await device("A1", zone, state: state)
        let two = await device("A2", zone, state: state)
        await one.copyStore(from: a)
        await two.copyStore(from: a)
        await report.result("11", "both copies start with pending: A1 \(await one.pendingText); A2 \(await two.pendingText)")

        var marks = (await one.mark, await two.mark)
        await one.queueSave(toy, type: "Toy", base: base, payload: "A1: the toy after the backup")
        await one.send()
        await two.queueSave(toy, type: "Toy", base: base, payload: "A2: the toy after the backup")
        await two.send()
        await report.result("11", "A1's sends: toy \(outcome(of: toy, in: await one.events(since: marks.0))); the unsent play \(outcome(of: unsent, in: await one.events(since: marks.0)))")
        await report.result("11", "A2's sends: toy \(outcome(of: toy, in: await two.events(since: marks.1))); the unsent play \(outcome(of: unsent, in: await two.events(since: marks.1)))")

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
            await report.result("11", "\(copy.name)'s fetch delivered \(fetchedRecords(events).map { ProbeText.record($0) }), deletions \(fetchedDeletions(events).count), errors \(errors)")
        }
        await finish([zone], [one, two])
    }

    // MARK: 12. Records as the app writes them, against the schema

    func q12() async {
        // The schema is imported: the probe only writes the two fields it has, so that no save adds a field.
        let zone = zone("q12")
        let a = await device("A", zone)
        let b = await device("B", zone)
        let toy = toyID(zone)
        let play = playID(zone)
        await a.queueZoneSave(zone)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: a toy as the app writes it", format: 1)
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play as the app writes it", format: 2)
        let mark = await a.mark
        await a.send()
        let events = await a.events(since: mark)
        await report.result("12", "the toy: \(outcome(of: toy, in: events)); the play: \(outcome(of: play, in: events))")
        await b.fetch()
        for id in [toy, play] {
            guard let record = await b.known[id] else {
                await report.result("12", "B did not receive \(ProbeText.short(id))")
                continue
            }
            let format = record.encryptedValues["format"]
            let payload = record.encryptedValues["payload"]
            await report.result("12", "B read \(record.recordType): format as \(format.map { "\(type(of: $0)) \($0)" } ?? "nothing"), read as Int \((record.encryptedValues["format"] as Int?).map(String.init) ?? "no"); payload as \(payload.map { "\(type(of: $0))" } ?? "nothing"), read as Data \((record.encryptedValues["payload"] as Data?).map { "\($0.count) bytes" } ?? "no"); plain values \(record.allKeys().filter { record[$0] != nil && record.encryptedValues[$0] == nil })")
        }
        await finish([zone], [a, b])
    }

    // MARK: 13. Coming to the front

    func q13() async {
        #if os(macOS)
        let zone = zone("q13")
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
        await report.result("13", "fetches while hidden: \(hiddenFetches); the app became active again: \(nowActive)")
        if let fetch, case .willFetchChanges(let will) = fetch.event {
            await report.result("13", "the engine began a fetch \(format(fetch.at - shown)) after the app was brought back, reason \(will.context.reason)")
        } else {
            await report.result("13", "the engine began no fetch within 30 s of the app being brought back")
        }

        // macOS lets an app become active only when the active app yields, so a probe whose app is behind another
        // cannot bring itself to the front. The system's notifications of becoming active, posted by the probe itself,
        // show at least whether the engine fetches when it hears them.
        // Another engine saves a play first, so that a fetch which reaches the server shows by delivering it.
        let w = await device("W", zone)
        let play = playID(zone)
        await w.queueZoneSave(zone)
        await w.queueSave(play, type: "FinishedPlay", base: nil, payload: "W: a play for A's next fetch to bring")
        await w.send()
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
            await report.result("13", "after the posted notifications (not a real return to the front), the engine began a fetch \(format(heard.at - posted)) later, reason \(will.context.reason)")
            let brought = await waitFor(a, since: postedMark, seconds: 30) { logged in
                if case .fetchedRecordZoneChanges(let changes) = logged.event { changes.modifications.contains { $0.record.recordID == play } } else { false }
            }
            await report.result("13", brought.map { "that fetch delivered W's play \(format($0.at - posted)) after the notifications" } ?? "no fetch delivered W's play within 30 s")
        } else {
            await report.result("13", "after the posted notifications (not a real return to the front), the engine began no fetch within 30 s")
        }
        await finish([zone], [a, w])
        #else
        await report.result("13", "asked on the Mac only")
        #endif
    }

    // MARK: 14. A save and a deletion queued for one record

    func q14() async {
        let zone = zone("q14")
        let a = await device("A", zone)
        let existing = playID(zone)
        let other = playID(zone)
        await a.queueZoneSave(zone)
        await a.queueSave(existing, type: "FinishedPlay", base: nil, payload: "A: a play that exists")
        await a.queueSave(other, type: "FinishedPlay", base: nil, payload: "A: another play that exists")
        await a.send()

        // A save, then a deletion, of a record that exists.
        var mark = await a.mark
        await a.queueSave(existing, type: "FinishedPlay", base: await a.known[existing], payload: "A: a save queued before a deletion")
        await a.queueDelete(existing)
        await report.result("14", "a save then a deletion of a record that exists leave pending: \(await a.pendingText)")
        await a.send()
        await report.result("14", "sent: \(sentSummary(await a.events(since: mark))); the record is now \(await onServer(existing))")

        // A save, then a deletion, of a record never sent.
        let fresh = playID(zone)
        mark = await a.mark
        await a.queueSave(fresh, type: "FinishedPlay", base: nil, payload: "A: a play never sent")
        await a.queueDelete(fresh)
        await report.result("14", "a save then a deletion of a record never sent leave pending: \(await a.pendingText)")
        await a.send()
        await report.result("14", "sent: \(sentSummary(await a.events(since: mark))); the record is now \(await onServer(fresh))")

        // A deletion, then a save, of a record that exists.
        mark = await a.mark
        await a.queueDelete(other)
        await a.queueSave(other, type: "FinishedPlay", base: await a.known[other], payload: "A: a save queued after a deletion")
        await report.result("14", "a deletion then a save of a record that exists leave pending: \(await a.pendingText)")
        await a.send()
        await report.result("14", "sent: \(sentSummary(await a.events(since: mark))); the record is now \(await onServer(other))")
        await finish([zone], [a])
    }

    /// The saves and deletions the engine reported in `events`.
    private func sentSummary(_ events: [ProbeDevice.Logged]) -> String {
        let parts = events.compactMap { logged -> String? in
            guard case .sentRecordZoneChanges(let sent) = logged.event else { return nil }
            let saved = sent.savedRecords.map { "saved [\(ProbeText.record($0))]" }
            let failed = sent.failedRecordSaves.map { "save refused \(ProbeText.short($0.record.recordID)): \(ProbeText.name($0.error.code))" }
            let deleted = sent.deletedRecordIDs.map { "deleted \(ProbeText.short($0))" }
            let failedDeletes = sent.failedRecordDeletes.map { "deletion refused \(ProbeText.short($0.key)): \(ProbeText.name($0.value.code))" }
            let all = saved + failed + deleted + failedDeletes
            return all.isEmpty ? nil : all.joined(separator: ", ")
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: "; ")
    }

    // MARK: 15 and 16. A save whose answer the app never stores

    /// Where question 15 leaves the device's state and records for question 16, in the app's own temporary folder.
    static let lostAnswerFile = FileManager.default.temporaryDirectory.appending(path: "NineRingsProbeAgain lost answer.json")

    /// The zone question 15 left for question 16, if it left one.
    static var lostAnswerZone: String? {
        guard let data = try? Data(contentsOf: lostAnswerFile) else { return nil }
        return (try? JSONDecoder().decode(ProbeDevice.Kept.self, from: data))?.zoneName
    }

    func q15() async {
        let zone = zone("q15")
        let a = await device("A", zone)
        let toy = toyID(zone)
        await a.keep(in: Self.lostAnswerFile)
        await a.queueZoneSave(zone)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy before the lost answer")
        await a.send()
        guard let base = await a.known[toy] else { return await report.result("15", "the first toy was not saved") }
        let play = playID(zone)
        let mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: base, payload: "A: the save whose answer is lost")
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play whose answer is lost")
        _ = await waitFor(a, since: mark, seconds: 10) { logged in
            if case .stateUpdate = logged.event { true } else { false }
        }
        await report.result("15", "kept before the send, at every state update, in the app's temporary folder; the toy's base has tag \(base.recordChangeTag ?? "none"). The process ends when the save's confirmation arrives: run question 16 next.")
        await a.endOnConfirmation()
        await a.send("the send whose answer is never stored")
        await report.result("15", "the confirmation never came, so the process did not end")
    }

    func q16() async {
        guard let data = try? Data(contentsOf: Self.lostAnswerFile), let kept = try? JSONDecoder().decode(ProbeDevice.Kept.self, from: data) else {
            return await report.result("16", "nothing kept by question 15: run it first")
        }
        let zone = CKRecordZone(zoneName: kept.zoneName)
        let toy = toyID(zone)
        let a = await device("A", zone, state: kept.state)
        await a.restore(kept)
        await report.result("16", "the restored state holds pending: \(await a.pendingText); the toy's base has tag \(await a.known[toy]?.recordChangeTag ?? "none")")
        // The app's launch queues again what its store marks as not yet received (design, section 8).
        let outgoing = await a.outgoingRecords
        for (id, plan) in outgoing.sorted(by: { $0.key.recordName < $1.key.recordName }) {
            await a.queueSave(id, type: plan.recordType, base: plan.systemFields.flatMap(ProbeText.record(systemFields:)), payload: plan.payload, format: plan.format)
        }
        await report.result("16", "after the app's own queueing at launch, pending: \(await a.pendingText)")
        var mark = await a.mark
        await a.send("at the next start")
        for id in outgoing.keys.sorted(by: { $0.recordName < $1.recordName }) {
            await report.result("16", "\(ProbeText.short(id)) sent again: \(outcome(of: id, in: await a.events(since: mark)))")
        }
        mark = await a.mark
        await a.fetch("at the next start")
        await report.result("16", "the fetch delivered: \(fetchedRecords(await a.events(since: mark)).map { ProbeText.record($0) })")
        try? FileManager.default.removeItem(at: Self.lostAnswerFile)
        await finish([zone], [a])
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
}
#endif
