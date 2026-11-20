#if DEBUG
import CloudKit
import Foundation

/// The questions about zones that are deleted, A to G, as `docs/icloud-probe.md` lists them. "N-1" and "N-2" are two
/// zones of different names: N-1 is deleted and never made again, and N-2 is the next. Every engine here fetches all
/// zones of the database, as the app's would, unless a question says otherwise; the report shows the probe's own zones
/// and only counts the others.
nonisolated extension ProbeRun {
    /// A short random id, so that no two zones of a run share a name even when a question is asked twice.
    static func shortID() -> String {
        String(UUID().uuidString.prefix(4))
    }

    // MARK: A and B. N-1 deleted, N-2 made: what an engine that knew N-1 is told, and what a new engine is told

    func qAB() async {
        let tag = Self.shortID()
        let n1 = zone("AB\(tag)_N1")
        let n2 = zone("AB\(tag)_N2")
        let toy1 = toyID(n1)
        let play1 = playID(n1)
        let toy2 = toyID(n2)
        let a = await device("A", scope: .all)
        let b = await device("B", scope: .all)
        let b1 = await device("B1", scope: .zoneIDs([n1.zoneID]))

        await a.queueZoneSave(n1)
        await a.queueSave(toy1, type: "Toy", base: nil, payload: "A: the toy in N-1")
        await a.queueSave(play1, type: "FinishedPlay", base: nil, payload: "A: a play in N-1")
        await a.send("A makes N-1")
        await b.fetch("B learns N-1")
        await b1.fetch("B1 learns N-1")
        await report.result("A", "before: B holds \(await b.known(in: n1.zoneID).map(ProbeText.record)); B1 holds \(await b1.known(in: n1.zoneID).count) records of N-1")

        await a.queueZoneDelete(n1.zoneID)
        await a.send("A deletes N-1")
        await a.queueZoneSave(n2)
        await a.queueSave(toy2, type: "Toy", base: nil, payload: "A: the toy in N-2")
        await a.send("A makes N-2")
        await report.result("A", "on the server now: N-1 \(await zoneExists(n1.zoneID)), N-2 \(await zoneExists(n2.zoneID))")

        // A.1 and A.2: B fetches all zones.
        var mark = await b.mark
        await b.fetch("B, which knew N-1 and has not fetched since")
        var events = await b.events(since: mark)
        await report.result("A.1", "B was told N-1 was deleted: \(deletionText(n1, in: events))")
        await report.result("A.2", "B was told of N-2: \(zoneModifications(events).contains(n2.zoneID)); B received N-2's toy: \(fetchedRecords(events).contains { $0.recordID == toy2 })")
        await report.result("A.2", "B was told, in order: \(told(events))")
        await report.result("A", "B holds afterwards: in N-1 \(await b.known(in: n1.zoneID).map(ProbeText.record)), in N-2 \(await b.known(in: n2.zoneID).map(ProbeText.record))")
        await report.result("A", "B's pending changes afterwards: \(await b.pendingText)")
        mark = await b.mark
        await b.fetch("B once more")
        await report.result("A", "B's next fetch was told: \(told(await b.events(since: mark)))")

        // A.3: B1 fetches N-1 alone, then all zones.
        mark = await b1.mark
        await b1.fetch("B1, which knew N-1, scoped to N-1 alone")
        events = await b1.events(since: mark)
        await report.result("A.3", "B1, scoped to N-1, was told N-1 was deleted: \(deletionText(n1, in: events))")
        await report.result("A.3", "B1, scoped to N-1, was told of N-2: \(zoneModifications(events).contains(n2.zoneID)); received N-2's toy: \(fetchedRecords(events).contains { $0.recordID == toy2 })")
        await report.result("A.3", "B1 was told, in order: \(told(events))")
        mark = await b1.mark
        await b1.fetch("B1 then fetches all zones", scope: .all)
        events = await b1.events(since: mark)
        await report.result("A.3", "B1's next fetch, of all zones: told of N-2 \(zoneModifications(events).contains(n2.zoneID)), received N-2's toy \(fetchedRecords(events).contains { $0.recordID == toy2 }); in order: \(told(events))")

        // B: a new engine, with no state, in the same situation.
        let c = await device("New", scope: .all)
        mark = await c.mark
        await c.fetch("a new engine with no state")
        events = await c.events(since: mark)
        await report.result("B", "the new engine was told N-1 was deleted: \(deletionText(n1, in: events))")
        await report.result("B", "the new engine was told of N-2: \(zoneModifications(events).contains(n2.zoneID)); received N-2's toy: \(fetchedRecords(events).contains { $0.recordID == toy2 }); received N-1's records: \(fetchedRecords(events).contains { $0.recordID.zoneID == n1.zoneID })")
        await report.result("B", "the new engine was told, in order: \(told(events))")
        let deletions = zoneDeletions(events)
        await report.result("B", "it was told of \(deletions.count) zone deletions in all, \(deletions.filter { ProbeText.isProbeZone($0.zoneID) }.count) of them this probe's; of \(zoneModifications(events).count) zones that exist")
        await finish([n2], [a, b, b1, c])
    }

    /// Whether `events` report `zone` as deleted, and with which reason.
    private func deletionText(_ zone: CKRecordZone, in events: [ProbeDevice.Logged]) -> String {
        let reasons = zoneDeletions(events).filter { $0.zoneID == zone.zoneID }.map { ProbeText.reason($0.reason) }
        return reasons.isEmpty ? "no" : "yes, reason \(reasons.joined(separator: ", "))"
    }

    // MARK: C. Saving into N-1 before the deletion has been fetched

    func qC() async {
        let tag = Self.shortID()
        let n1 = zone("C\(tag)_N1")
        let n2 = zone("C\(tag)_N2")
        let toy1 = toyID(n1)
        let a = await device("A", scope: .all)
        let b = await device("B", scope: .all)
        let q = await device("Q", scope: .all)
        let s = await device("S", scope: .all)

        await a.queueZoneSave(n1)
        await a.queueSave(toy1, type: "Toy", base: nil, payload: "A: the toy in N-1")
        await a.queueSave(playID(n1), type: "FinishedPlay", base: nil, payload: "A: a play in N-1")
        await a.send("A makes N-1")
        await b.fetch("B learns N-1")
        await q.fetch("Q learns N-1")
        await s.fetch("S learns N-1")
        let stateBefore = await b.serialization
        await a.queueZoneDelete(n1.zoneID)
        await a.send("A deletes N-1")
        await a.queueZoneSave(n2)
        await a.queueSave(toyID(n2), type: "Toy", base: nil, payload: "A: the toy in N-2")
        await a.send("A makes N-2")

        // C.1: a new record into N-1.
        let newPlay = playID(n1)
        var mark = await b.mark
        await b.queueSave(newPlay, type: "FinishedPlay", base: nil, payload: "B: a new play into N-1, which is gone")
        await b.send("a new record into N-1, before any fetch")
        var events = await b.events(since: mark)
        await report.result("C.1", "B's new record into N-1: \(outcome(of: newPlay, in: events))")
        await report.result("C.1", "B's pending changes afterwards: \(await b.pendingText); the send also told B: \(told(events))")
        await report.result("C.1", "afterwards N-1 \(await zoneExists(n1.zoneID)); the record is \(await onServer(newPlay))")

        // C.2: the toy, on the system fields B holds from N-1.
        let held = await b.known[toy1]
        mark = await b.mark
        await b.queueSave(toy1, type: "Toy", base: held, payload: "B: the toy, on its system fields from N-1")
        await b.send("the toy on its N-1 system fields, before any fetch")
        events = await b.events(since: mark)
        await report.result("C.2", "B's save of the toy with the system fields of tag \(held?.recordChangeTag ?? "none"): \(outcome(of: toy1, in: events))")
        await report.result("C.2", "B's pending changes afterwards: \(await b.pendingText)")
        await report.result("C.2", "afterwards N-1 \(await zoneExists(n1.zoneID)); the toy is \(await onServer(toy1))")

        // C.3: what the engine does with the refused saves.
        mark = await b.mark
        let asked = await b.batchesAsked
        await b.send("once more, with nothing queued again by the probe")
        events = await b.events(since: mark)
        await report.result("C.3", "B's next send asked the delegate for \(await b.batchesAsked - asked) batches; \(savedRecords(events).count) saves accepted, \(failedSaves(events).count) refused; pending \(await b.pendingText)")
        mark = await b.mark
        await b.fetch("B fetches at last")
        await report.result("C.3", "B's fetch afterwards was told: \(told(await b.events(since: mark))); pending \(await b.pendingText)")
        let n = await device("New", scope: .all)
        mark = await n.mark
        await n.fetch("a new engine, to see whether anything made N-1 again")
        events = await n.events(since: mark)
        await report.result("C.3", "a new engine afterwards: told N-1 was deleted \(deletionText(n1, in: events)); told N-1 exists \(zoneModifications(events).contains(n1.zoneID))")

        // C.4: saves pending in N-1 when the deletion arrives by a fetch.
        let pendingPlay = playID(n1)
        await q.queueSave(pendingPlay, type: "FinishedPlay", base: nil, payload: "Q: a play queued into N-1, not sent")
        await q.queueSave(toy1, type: "Toy", base: await q.known[toy1], payload: "Q: the toy queued on its N-1 system fields, not sent")
        await report.result("C.4", "Q's pending changes before its fetch: \(await q.pendingText)")
        mark = await q.mark
        await q.fetch("Q fetches with saves pending in N-1")
        await report.result("C.4", "Q was told: \(told(await q.events(since: mark)))")
        await report.result("C.4", "Q's pending changes after the fetch: \(await q.pendingText)")
        mark = await q.mark
        await q.send("Q sends what is pending")
        events = await q.events(since: mark)
        await report.result("C.4", "Q's send: play \(outcome(of: pendingPlay, in: events)); toy \(outcome(of: toy1, in: events)); pending afterwards \(await q.pendingText)")

        // C.5: the same new record, from an engine with automatic syncing, made from B's state before the deletion.
        var devices = [a, b, q, n]
        if let stateBefore {
            let auto = await device("Auto", scope: .all, state: stateBefore, automatic: true)
            devices.append(auto)
            let autoPlay = playID(n1)
            await auto.queueSave(autoPlay, type: "FinishedPlay", base: nil, payload: "Auto: a new play into N-1, queued at once")
            try? await Task.sleep(for: .seconds(60))
            events = await auto.events(since: 0)
            let firstFetch = events.firstIndex { if case .willFetchChanges = $0.event { true } else { false } }
            let firstSend = events.firstIndex { if case .willSendChanges = $0.event { true } else { false } }
            await report.result("C.5", "in 60 s the automatic engine began \(events.filter { if case .willFetchChanges = $0.event { true } else { false } }.count) fetches and \(events.filter { if case .willSendChanges = $0.event { true } else { false } }.count) sends; the first fetch was event \(firstFetch.map(String.init) ?? "none"), the first send event \(firstSend.map(String.init) ?? "none")")
            await report.result("C.5", "the save: \(outcome(of: autoPlay, in: events)), tried \(failedSaves(events).filter { $0.record.recordID == autoPlay }.count) times; pending at the end \(await auto.pendingText)")
            await report.result("C.5", "it was told: \(told(events))")
            await report.result("C.5", "afterwards N-1 \(await zoneExists(n1.zoneID))")
        }

        // C.6: S, which knew N-1 and has not fetched since, queues N-1's save together with a new play, as a device
        // that sends its zone with its records would. Asked last, because it may make N-1 again.
        let sPlay = playID(n1)
        await s.queueZoneSave(n1)
        await s.queueSave(sPlay, type: "FinishedPlay", base: nil, payload: "S: a new play, sent with N-1's save")
        mark = await s.mark
        await s.send("S sends N-1's save and a play, before any fetch")
        events = await s.events(since: mark)
        await report.result("C.6", "S's save of N-1: \(zoneSaveOutcome(of: n1.zoneID, in: events)); its play: \(outcome(of: sPlay, in: events)); afterwards N-1 \(await zoneExists(n1.zoneID))")
        let m = await device("New2", scope: .all)
        mark = await m.mark
        await m.fetch("a new engine, after S's send")
        events = await m.events(since: mark)
        await report.result("C.6", "a new engine afterwards: told N-1 was deleted \(deletionText(n1, in: events)); told N-1 exists \(zoneModifications(events).contains(n1.zoneID)); received \(fetchedRecords(events).filter { $0.recordID.zoneID == n1.zoneID }.map { ProbeText.record($0) })")
        mark = await a.mark
        await a.fetch("A, which deleted N-1, after S's send")
        await report.result("C.6", "A's fetch afterwards was told: \(told(await a.events(since: mark)))")
        devices += [s, m]
        await finish([n1, n2], devices)
    }

    // MARK: D. Saving a zone that exists; two engines saving the same new zone

    func qD() async {
        let tag = Self.shortID()

        // D.1: a zone that exists, saved again by an engine that knows it, then by one that never fetched.
        let z = zone("D\(tag)_Z")
        let toy = toyID(z)
        let play = playID(z)
        let a = await device("A", scope: .all)
        let b = await device("B", scope: .all)
        await a.queueZoneSave(z)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy in Z")
        await a.queueSave(play, type: "FinishedPlay", base: nil, payload: "A: a play in Z")
        await a.send("A makes Z")
        await a.fetch("A brings its own state up to date")
        await b.fetch("B learns Z")
        await report.result("D.1", "before: the toy is \(await onServer(toy)); the play is \(await onServer(play))")
        let aBase = await a.known[toy]

        var mark = await b.mark
        await b.queueZoneSave(z)
        await b.send("B, which knows Z, saves it again")
        var events = await b.events(since: mark)
        await report.result("D.1", "B's save of Z, which exists: \(zoneSaveOutcome(of: z.zoneID, in: events)); pending afterwards \(await b.pendingText)")
        await report.result("D.1", "after B's save: the toy is \(await onServer(toy)); the play is \(await onServer(play))")
        mark = await a.mark
        await a.fetch("A, after B saved Z again")
        await report.result("D.1", "A's fetch afterwards was told: \(told(await a.events(since: mark)))")

        let c = await device("C", scope: .all)
        let cPlay = playID(z)
        mark = await c.mark
        await c.queueZoneSave(z)
        await c.queueSave(cPlay, type: "FinishedPlay", base: nil, payload: "C: a play, saved with the zone")
        await c.send("C, which never fetched, saves Z and a play in it")
        events = await c.events(since: mark)
        await report.result("D.1", "C's save of Z: \(zoneSaveOutcome(of: z.zoneID, in: events)); its play: \(outcome(of: cPlay, in: events))")
        await report.result("D.1", "after C's save: the toy is \(await onServer(toy)); the play is \(await onServer(play))")
        mark = await a.mark
        await a.fetch("A, after C saved Z")
        await report.result("D.1", "A's fetch afterwards was told: \(told(await a.events(since: mark)))")
        mark = await a.mark
        await a.queueSave(toy, type: "Toy", base: aBase, payload: "A: the toy, on a base taken before Z was saved again")
        await a.send("A saves the toy on its base of before the two saves of Z")
        await report.result("D.1", "A's save of the toy on the system fields of tag \(aBase?.recordChangeTag ?? "none"), taken before B's save of Z: \(outcome(of: toy, in: await a.events(since: mark)))")
        let reader = await device("Reader", z)
        await reader.fetch("a new engine reads the toy")
        await report.result("D.1", "a new engine reads the toy: \(await reader.known[toy].map { "[\(ProbeText.record($0))] \(ProbeText.recordDetails($0))" } ?? "no toy")")

        // D.2: two new engines in this process save the same new zone at once.
        let y = zone("D\(tag)_Y")
        let e1 = await device("E1", scope: .all)
        let e2 = await device("E2", scope: .all)
        let p1 = playID(y)
        let p2 = playID(y)
        await e1.queueZoneSave(y)
        await e1.queueSave(p1, type: "FinishedPlay", base: nil, payload: "E1: a play saved with the new zone")
        await e2.queueZoneSave(y)
        await e2.queueSave(p2, type: "FinishedPlay", base: nil, payload: "E2: a play saved with the new zone")
        let marks = (await e1.mark, await e2.mark)
        async let first: Void = e1.send("at the same moment as E2")
        async let second: Void = e2.send("at the same moment as E1")
        _ = await (first, second)
        let events1 = await e1.events(since: marks.0)
        let events2 = await e2.events(since: marks.1)
        await report.result("D.2", "E1: zone \(zoneSaveOutcome(of: y.zoneID, in: events1)) at \(zoneSaveTime(y, in: events1)); play \(outcome(of: p1, in: events1))")
        await report.result("D.2", "E2: zone \(zoneSaveOutcome(of: y.zoneID, in: events2)) at \(zoneSaveTime(y, in: events2)); play \(outcome(of: p2, in: events2))")
        let n = await device("New", scope: .all)
        mark = await n.mark
        await n.fetch("a new engine")
        events = await n.events(since: mark)
        let names = (try? await database.allRecordZones().map(\.zoneID.zoneName).filter { $0 == y.zoneID.zoneName }) ?? []
        await report.result("D.2", "zones of that name on the server: \(names.count); the new engine received the plays: E1's \(fetchedRecords(events).contains { $0.recordID == p1 }), E2's \(fetchedRecords(events).contains { $0.recordID == p2 })")
        await finish([z, y], [a, b, c, reader, e1, e2, n])
    }

    /// When the engine reported a zone's save, by the clock of the day, to the millisecond.
    func zoneSaveTime(_ zone: CKRecordZone, in events: [ProbeDevice.Logged]) -> String {
        let logged = events.first { logged in
            if case .sentDatabaseChanges(let sent) = logged.event {
                sent.savedZones.contains { $0.zoneID == zone.zoneID } || sent.failedZoneSaves.contains { $0.zone.zoneID == zone.zoneID }
            } else { false }
        }
        return logged.map { ProbeText.clock($0.date) } ?? "no time"
    }

    /// D.3, in two processes: one of the two launches that save the same new zone at an agreed moment. Each saves the
    /// zone and a play named after its role, and says when the engine reported the zone's save.
    func raceSave(zoneName: String, role: String, at moment: Date) async {
        let z = CKRecordZone(zoneName: zoneName)
        guard ProbeText.isProbeZone(z.zoneID) else { return await report.say("--", "STOPPED: \(zoneName) is not a zone name of this probe") }
        let d = await device(role, z)
        let play = CKRecord.ID(recordName: "race-\(role)", zoneID: z.zoneID)
        await d.queueZoneSave(z)
        await d.queueSave(play, type: "FinishedPlay", base: nil, payload: "\(role): saved with the zone at the agreed moment")
        let wait = moment.timeIntervalSinceNow
        await report.say("--", "waits \(ProbeText.decimal(wait, places: 3)) s for the agreed moment \(ProbeText.clock(moment))")
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        let mark = await d.mark
        await report.say("--", "sends at \(ProbeText.clock(.now))")
        await d.send("at the agreed moment")
        let events = await d.events(since: mark)
        await report.result("D.3", "\(role): zone \(zoneSaveOutcome(of: z.zoneID, in: events)), reported at \(zoneSaveTime(z, in: events)); play \(outcome(of: play, in: events))")
        await d.stop()
    }

    /// D.3, the third launch: what a new engine finds after the two saves, and the zone's deletion.
    func raceCheck(zoneName: String) async {
        let z = CKRecordZone(zoneName: zoneName)
        guard ProbeText.isProbeZone(z.zoneID) else { return await report.say("--", "STOPPED: \(zoneName) is not a zone name of this probe") }
        let n = await device("New", z)
        await n.fetch("a new engine, after both launches saved the zone")
        let events = await n.events(since: 0)
        let names = (try? await database.allRecordZones().map(\.zoneID.zoneName).filter { $0 == zoneName }) ?? []
        await report.result("D.3", "zones of that name on the server: \(names.count); the new engine received \(fetchedRecords(events).map { ProbeText.record($0) })")
        await finish([z], [n])
    }

    // MARK: E. A zone made again under its old name, and a token from far ahead

    func qE() async {
        for count in [12, 1] {
            await zoneMadeAgain(withRecords: count)
        }
    }

    private func zoneMadeAgain(withRecords count: Int) async {
        let question = "E(\(count))"
        let z = zone("E\(Self.shortID())_\(count)")
        let a = await device("A", scope: .all)
        let b = await device("B", scope: .all)
        let old = (1...count).map { _ in playID(z) }
        await a.queueZoneSave(z)
        for (index, id) in old.enumerated() {
            await a.queueSave(id, type: "FinishedPlay", base: nil, payload: "A: play \(index + 1) in the first Z")
        }
        await a.send("A makes Z with \(count) records")
        await b.fetch("B fetches them all")
        // B2 fetches the first Z too, then stays away until Z made again has passed every tag B2 saw.
        let b2 = await device("B2", scope: .all)
        await b2.fetch("B2 fetches them all, then stays away")
        let held = await b.known(in: z.zoneID)
        await report.result(question, "B and B2 hold \(held.count) and \(await b2.known(in: z.zoneID).count) records of the first Z, tags \(held.compactMap(\.recordChangeTag).sorted())")

        await a.queueZoneDelete(z.zoneID)
        await a.send("A deletes Z")
        let first = playID(z)
        await a.queueZoneSave(z)
        await a.queueSave(first, type: "FinishedPlay", base: nil, payload: "A: the one record in Z made again")
        await a.send("A makes Z again under its name")
        await report.result(question, "the record in Z made again has tag \(await a.known[first]?.recordChangeTag ?? "none")")

        var mark = await b.mark
        await b.fetch("B, with its token from the first Z")
        var events = await b.events(since: mark)
        await report.result(question, "B's fetch delivered the record of Z made again: \(fetchedRecords(events).contains { $0.recordID == first }); told of Z's deletion: \(zoneDeletions(events).contains { $0.zoneID == z.zoneID }); record deletions: \(fetchedDeletions(events).filter { $0.recordID.zoneID == z.zoneID }.count); zone fetch errors: \(zoneFetchErrors(events))")
        await report.result(question, "B was told, in order: \(told(events))")
        let after = await b.known(in: z.zoneID)
        await report.result(question, "B holds afterwards \(after.count) records of Z: \(after.filter { old.contains($0.recordID) }.count) of the first Z, the record of Z made again \(after.contains { $0.recordID == first })")

        // Further saves in Z made again, one per send, until its tags pass every tag of the first Z. B fetched Z made
        // again before them, so its next fetch starts from a token of the new zone; B2's comes from the first Z.
        var later: [CKRecord.ID] = []
        for index in 1...(count + 3) {
            let id = playID(z)
            await a.queueSave(id, type: "FinishedPlay", base: nil, payload: "A: later record \(index) in Z made again")
            await a.send()
            later.append(id)
        }
        await report.result(question, "A saved \(later.count) more records in Z made again, one per send; tags \(await later.asyncMap { await a.known[$0]?.recordChangeTag ?? "none" })")
        mark = await b.mark
        await b.fetch("B again")
        events = await b.events(since: mark)
        let delivered = fetchedRecords(events).map(\.recordID)
        await report.result(question, "B's next fetch delivered the later records number \(later.enumerated().filter { delivered.contains($0.element) }.map { $0.offset + 1 }); the first record of Z made again: \(delivered.contains(first)); zone fetch errors: \(zoneFetchErrors(events))")
        let final = await b.known(in: z.zoneID)
        await report.result(question, "B holds at the end \(final.count) records of Z: \(final.filter { old.contains($0.recordID) }.count) of the first Z; of Z made again, which has \(later.count + 1): \(final.filter { !old.contains($0.recordID) }.count)")

        mark = await b2.mark
        await b2.fetch("B2, back with its token from the first Z, after Z made again passed its tags")
        events = await b2.events(since: mark)
        let returned = fetchedRecords(events).map(\.recordID)
        await report.result(question, "B2's fetch delivered the first record of Z made again: \(returned.contains(first)); the later records number \(later.enumerated().filter { returned.contains($0.element) }.map { $0.offset + 1 }); told of Z's deletion: \(zoneDeletions(events).contains { $0.zoneID == z.zoneID }); record deletions: \(fetchedDeletions(events).filter { $0.recordID.zoneID == z.zoneID }.count); zone fetch errors: \(zoneFetchErrors(events))")
        let away = await b2.known(in: z.zoneID)
        await report.result(question, "B2 holds afterwards \(away.count) records of Z: \(away.filter { old.contains($0.recordID) }.count) of the first Z; of Z made again, which has \(later.count + 1): \(away.filter { !old.contains($0.recordID) }.count)")

        let n = await device("New", scope: .all)
        mark = await n.mark
        await n.fetch("a new engine")
        events = await n.events(since: mark)
        await report.result(question, "a new engine received \(fetchedRecords(events).filter { $0.recordID.zoneID == z.zoneID }.count) records of Z; told of Z's deletion: \(zoneDeletions(events).contains { $0.zoneID == z.zoneID })")
        await finish([z], [a, b, b2, n])
    }

    // MARK: F. How long deletion reports live

    func qF() async {
        let n = await device("New", scope: .all)
        await n.fetch("a new engine with no state")
        let events = await n.events(since: 0)
        let deletions = zoneDeletions(events)
        let reasons = Dictionary(grouping: deletions) { ProbeText.reason($0.reason) }.mapValues(\.count)
        await report.result("F", "a new engine was told of \(deletions.count) zone deletions, by reason \(reasons.sorted { $0.key < $1.key }), and of \(zoneModifications(events).count) zones that exist")
        await report.result("F", "deleted zones: \(deletions.map { "\($0.zoneID.zoneName) (\(ProbeText.reason($0.reason)))" }.sorted())")
        await report.result("F", "zones that exist: \(zoneModifications(events).map(\.zoneName).sorted())")
        await n.stop()
    }

    // MARK: G. A save on a stale base, accepted in a zone made again: can the other engines read it

    func qG() async {
        await staleBase(equalTags: true)
        await staleBase(equalTags: false)
    }

    private func staleBase(equalTags: Bool) async {
        let question = equalTags ? "G(equal tags)" : "G(different tags)"
        let z = zone("G\(Self.shortID())_\(equalTags ? "eq" : "ne")")
        let toy = toyID(z)
        let a = await device("A", scope: .all)
        let b = await device("B", scope: .all)
        await a.queueZoneSave(z)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy in the first Z")
        await a.send("A makes Z")
        await b.fetch("B learns the first Z")
        guard let held = await b.known[toy] else {
            await report.result(question, "B did not receive the toy")
            return await finish([z], [a, b])
        }
        await a.queueZoneDelete(z.zoneID)
        await a.send("A deletes Z")
        await a.queueZoneSave(z)
        await a.queueSave(toy, type: "Toy", base: nil, payload: "A: the toy in Z made again")
        await a.send("A makes Z again, with a new toy")

        // Bring the tag of the toy in Z made again to B's, or away from it.
        for _ in 0..<10 {
            guard let current = await a.known[toy], let tag = current.recordChangeTag else { break }
            let equal = tag == held.recordChangeTag
            if equalTags {
                guard !equal, let now = Int(tag, radix: 36), let target = held.recordChangeTag.flatMap({ Int($0, radix: 36) }), now < target else { break }
            } else {
                guard equal else { break }
            }
            await a.queueSave(toy, type: "Toy", base: current, payload: "A: the toy in Z made again, saved once more")
            await a.send(equalTags ? "to bring its tag to B's" : "so that its tag differs from B's")
        }
        let current = await a.known[toy]
        await report.result(question, "B holds the first Z's toy with tag \(held.recordChangeTag ?? "none"); Z made again holds a toy with tag \(current?.recordChangeTag ?? "none"); equal: \(held.recordChangeTag == current?.recordChangeTag)")

        var mark = await b.mark
        await b.queueSave(toy, type: "Toy", base: held, payload: "B: on the first Z's toy, never having seen Z made again")
        await b.send("B saves on its base from the first Z")
        var events = await b.events(since: mark)
        await report.result(question, "B's save: \(outcome(of: toy, in: events))")
        guard let written = savedRecords(events).last(where: { $0.recordID == toy }) else {
            return await finish([z], [a, b])
        }
        await report.result(question, "the record B got back: \(ProbeText.recordDetails(written))")

        mark = await a.mark
        await a.fetch("A reads what B wrote")
        events = await a.events(since: mark)
        let readByA = fetchedRecords(events).last { $0.recordID == toy }
        await report.result(question, "A's fetch delivered: \(readByA.map { "[\(ProbeText.record($0))] \(ProbeText.recordDetails($0))" } ?? "no toy"); zone fetch errors \(zoneFetchErrors(events))")
        let n = await device("New", scope: .all)
        mark = await n.mark
        await n.fetch("a new engine reads what B wrote")
        events = await n.events(since: mark)
        let readByNew = fetchedRecords(events).last { $0.recordID == toy }
        await report.result(question, "a new engine's fetch delivered: \(readByNew.map { "[\(ProbeText.record($0))] \(ProbeText.recordDetails($0))" } ?? "no toy"); zone fetch errors \(zoneFetchErrors(events))")
        await report.result(question, "read directly from the database: \(await onServer(toy))")
        await finish([z], [a, b, n])
    }
}

extension Array where Element: Sendable {
    /// The elements mapped one after the other by an asynchronous `transform`.
    nonisolated func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var result: [T] = []
        for element in self { result.append(await transform(element)) }
        return result
    }
}
#endif
