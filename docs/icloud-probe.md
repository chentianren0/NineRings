# What CloudKit and its sync engine do: the probe's findings

The iCloud design (`docs/icloud.md`) rests on behaviours of CloudKit and of `CKSyncEngine` that Apple does not document. Its section 15 lists them as open points. The probe, [`NineRings/CloudProbe/`](../NineRings/CloudProbe/), is debug-only code in the Mac app that tries them against CloudKit's development environment. This page says, for each question, what was seen, on which system and how often, what follows from it, and what stays unknown.

Three things are kept apart under every question:

- **Seen**: what the probe did and what came back, with how often: "(3 of 3)" means that the result was the same each of the three times the question was asked, in the runs named.
- **Concluded**: what follows from what was seen, and only that.
- **Unknown**: what the probe could not reach.

The probe finds facts. What the design makes of them is the design's.

## Where, when and how often

- **System:** macOS 27.3 (26C5047e), Xcode 27.3 (27C5035i), `cktool` 1.0.23001.
- **Environment:** the development environment of the container `iCloud.com.chentianren.PlayNineRings`, its private database, with the iCloud account this Mac is signed in to. Production was not seen.
- **When:** 20 November 2026, in UTC (runs 1 to 8 on the evening of 19 November in Pacific time). Each question below names its runs:

  | Run | Began | Questions | Code |
  |---|---|---|---|
  | 1 | 02:12:31 | A, C, D, E, F, G | earlier |
  | 2 | 02:15:36 | A, A, C, D, E, G, G | earlier |
  | race 1 | 02:18:41 | D.3, five rounds, two processes each | earlier |
  | 3 | 02:22:03 | 1 to 14 | earlier |
  | 4 | 02:29:30 | 10, 9 | earlier |
  | 5 and 6 | 02:34:24 | 15, then 16 | earlier |
  | 7 | 02:34:58 | 1 to 8, 11 to 14, A, C, D, E, F, G | earlier |
  | 8 | 02:42:56 | F | earlier |
  | 9 | 10:48:28 | D, E | final |
  | 10 | 10:49:45 | D, with cloudd's log streaming | final |
  | 11 | 10:50:48 | all: 1 to 14, A, C, D, E, F, G | final |
  | 12 | 11:00:40 | A, C, D, E, F, G | final |
  | 13 | 11:03:40 | 10, 9 | final |
  | 14 and 15 | 11:08:34 | 15, then 16 | final |
  | race 2 | 11:08:43 | D.3, five rounds, two processes each | final |

  "Final" is the code at commit `0565180`, which this page describes. "Earlier" is the code before it, which asked the same questions in the same way, except: E had no engine B2, C had no part C.6, D.1 had no save on an old base, and question 9 deleted a zone it had never made; question 13 had no engine W before run 7; in run 1, G compared tags as hexadecimal numbers, which changed nothing, since it never had to adjust a tag. Some headings were worded differently.
- **Engines:** every engine of a question ran in one app process on one Mac, except question D.3, which ran in two processes. To CloudKit they were most likely one device. Points that this leaves open say so.
- **The schema** was imported before the probe ran, and the probe did not change it: an export after the last run was the same as one before the first ([icloud-schema.md](icloud-schema.md)).
- **Not reachable here:** a zone's deletion by a purge (the person deletes the app's data in Settings) or by a reset of encrypted data cannot be provoked in the development environment. Only the reason `deleted` was seen. Where this limits an answer, the answer says so.

## How it runs

A signed debug build, with the iCloud entitlement, started through LaunchServices (`open`), behind the app in front, with the launch switch `-cloudkit-probe`:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/probe-build build
```

```bash
open -g -n -W --stdout /tmp/probe.txt /tmp/probe-build/Build/Products/Debug/NineRings.app --args -ApplePersistenceIgnoreState YES -cloudkit-probe zones
```

- `-cloudkit-probe zones` asks questions A to G (A answers B too); `all` asks 1 to 14 and A to G; `-cloudkit-probe 1,2,E` asks those, and a question named twice is asked twice. Questions 15 and 16 take a launch each, in that order. Question D.3 takes three launches, which `scripts/cloudkit-probe-race.sh` runs. Like every launch switch of the app, it takes a value, and only a debug build reads it.
- The report goes to standard output, one line per event, and to the log under the category `CloudProbe`. Lines that start with `RESULT` say what a question found; the lines above them show every event in order. An account's user record name never appears in it. The app quits when the probe is done.
- While the probe runs, the app keeps its own records in memory, so nothing else in it talks to CloudKit.
- The probe runs in the Mac app only. It stops before reaching CloudKit on iPhone and iPad, where it cannot read its own entitlements, if the build lacks the iCloud entitlement, if it would talk to production, or if no account is available.
- Each question makes its own zones, named `NineRingsProbeAgain_<run>_<question>…`, and deletes them at its end. At the start and the end of a run the probe deletes every zone whose name begins with `NineRingsProbeAgain_`, and it refuses to delete any other zone. So one launch runs at a time; only the two launches of D.3, which leave other zones alone, run side by side.
- Each device of the probe is a `CKSyncEngine` with its own state and its own records in memory. Automatic syncing is off, except where a question says so, and the probe sends and fetches by hand. It never calls the engine from inside a callback. Its records are the design's: `Toy`, named `toy`, and `FinishedPlay`, named by a UUID, each with `format` and `payload` written through `encryptedValues`.
- The engines of questions A to G fetch all zones of the database, as the app's would, unless a question says otherwise. The report shows the records of the probe's own zones and only counts the records of other zones. Zone names, which hold no data, are listed in full where a question lists zones: at the start of a run, in B and in F. The engines of questions 1 to 16 fetch their own zone only.

## In brief

The design's open points (section 15) that a question takes up are named in the last column; the others inform the rules of its sections 6 to 10.

| | Question | What was seen | How often | Open point |
|---|---|---|---|---|
| A | N-1 deleted and N-2 made: an engine that knew N-1 | Told of N-1's deletion (`deleted`) and of N-2 in one report, then given N-2's records unasked. A fetch scoped to N-1 still hears of N-2, and fetches it at the next wider fetch | 6 of 6 | |
| B | The same: a new engine | Told of N-1's deletion, of N-2 with its records, and of every other deleted zone of the database | 6 of 6 | |
| C | Saving into N-1 before fetching | A record's save: `zoneNotFound`, no record attached, with or without system fields; nothing is created, and the engine drops the save. Saves already pending stay pending when a fetch reports the deletion. Sent together with N-1's own save, a record makes N-1 again, and the deletion is no longer reported | 5 of 5; C.6 2 of 2 | |
| D | Saving a zone that exists; two engines saving one new zone | No error, nothing changes, other engines hear nothing. Both succeed, with one zone and both records. On one Mac, cloudd lets one save of a zone go to the server at a time, from any process | 7 of 7; 10 of 10 in two processes | 16, in part |
| E | A zone made again under its old name | An old token hides none of the new records, before or after the new zone passes its old tags; no deletion is reported; the old records stay with the engine | 6 of 6 with 12 records, 6 of 6 with 1; the engine that stays away 3 of 3 each | |
| F | How long deletion reports live | Still delivered 8 hours 50 minutes after the deletion (this probe's dating) and at least 10 hours after it (the earlier probe's logs); none had expired | 5 of 5 | 13 |
| G | A save on a stale base in a zone made again | Accepted when the tags are equal, and readable by every engine; refused when they differ | 6 of 6 each | |
| 1 | A first save under a name that exists | `serverRecordChanged`, "record to insert already exists", with the server's record | 3 of 3 | 1 |
| 2 | A save on stale system fields | `serverRecordChanged`, "client oplock error updating record", with all three records | 3 of 3 | 2 |
| 3 | What a saved record carries | Change tags count up in each zone; the first record saved with a zone has tag 3 | 3 of 3 | |
| 4 | An engine's own save coming back | It comes back, after its confirmation in every round | 3 of 3, 24 rounds | |
| 5 | A record deleted, then saved again | On the old system fields: `unknownItem`. Without them: a new record | 3 of 3 | |
| 6 | Deleting a record that is gone | Reported as deleted, no error | 3 of 3 | |
| 7 | Saving into a zone never made | `zoneNotFound`, dropped. Zones are sent before records | 3 of 3 | |
| 8 | A fetch from nothing after deletions | Both deletions delivered, on one Mac | 3 of 3 | 5, in part |
| 9 | The account event of a new engine | `signIn` with the account's id; none from a saved state | 4 of 4 | 14 |
| 10 | Automatic syncing and pushes | The engine registers for pushes by itself and sends within seconds; it did not fetch another engine's change by itself in 240 s | 4 of 4 | 6, in part |
| 11 | Two engines from one saved state | They behave as two devices | 3 of 3 | 4, in part |
| 12 | Records against the schema | Accepted, and read back with the same types | 3 of 3 | |
| 13 | A fetch when the app becomes active | The engine fetches half a second after the notification, and the fetch reaches the server; a real return to the front was not produced | 3 of 3 | 7, in part |
| 14 | A save and a deletion queued for one record | The later replaces the earlier | 3 of 3 | |
| 15, 16 | A save whose answer is never stored | Still pending after a restart; sent again, refused with the landed save attached | 2 of 2 | |

## A deleted zone (questions A to G)

"N-1" and "N-2" are two zones of different names. N-1 is deleted and not made again; N-2 is the next zone. "Z" is a zone that is deleted and made again under the same name. Engine A makes the changes; engine B, and the others named, look.

### A. N-1 deleted and N-2 made: what an engine that knew N-1 is told

A makes N-1 with the toy and a play. B and B1 fetch them. A deletes N-1 through its engine, then makes N-2 with a toy. B fetches all zones; B1 fetches N-1 alone, then all zones.

**Seen** (6 of 6; runs 1, 2, 7, 11 and 12):

- **A.1** B's next fetch reported N-1 as deleted, with the reason `deleted`.
- **A.2** The same fetch reported N-2 as a changed zone and delivered N-2's toy, which B had not asked for by name. The order of events: first one `fetchedDatabaseChanges` event, which held both lists, N-2 among the modifications and N-1 among the deletions; then the fetch of N-2 began, its toy arrived in `fetchedRecordZoneChanges`, and the fetch of N-2 ended. The engine began no fetch of N-1, reported no error, and delivered no deletion of N-1's records. B's two records of N-1 stayed in its store, where the engine leaves them to the app. B's pending changes were empty. A second fetch reported nothing.
- **A.3** B1, whose fetch was scoped to N-1 alone, got the same `fetchedDatabaseChanges` event: N-1 deleted (`deleted`) and N-2 changed. It did not fetch N-2 or receive its toy. B1's next fetch, of all zones, had no database changes, so it did not name N-2 again, and yet the engine fetched N-2 and delivered its toy.

**Concluded:** an engine that knew a zone is told of its deletion and of the new zone in one report, and fetches the new zone's records by itself unless the fetch's scope leaves the zone out. The database report is not limited by the fetch's scope. A zone that a scoped fetch left out is fetched at the next fetch whose scope includes it.

**Unknown:** whether a purge or a reset of encrypted data is reported in the same way.

### B. The same: what a new engine with no state is told

After A's changes, a new engine fetches all zones for the first time.

**Seen** (6 of 6; runs 1, 2, 7, 11 and 12): its first fetch reported N-1 as deleted (`deleted`) and N-2 as a zone, and delivered N-2's toy, nothing of N-1. The same single `fetchedDatabaseChanges` event also listed every other zone of the database that had been deleted: 52, 62, 64, 109, 153 and 163 deletions in the six runs, the probe's own and older ones (see F). It began with an `accountChange` sign-in event (question 9). A zone that had been made again under its name is not reported as deleted to a new engine (questions E and C.6).

**Concluded:** an engine with no state learns of past zone deletions in its first fetch, together with the zones that exist. It is not told which of the deleted zones it ever knew.

**Unknown:** the same as for A.

### C. Saving into N-1 before the deletion has been fetched

As in A, but B, which holds state and records for N-1, does not fetch after the deletion. It saves into N-1: first a new play, then the toy on the system fields it holds.

**Seen** (5 of 5; runs 1, 2, 7, 11 and 12):

- **C.1** The new play was refused with `CKError.zoneNotFound` (26), server message "Zone does not exist", with no server record attached.
- **C.2** The toy on B's system fields was refused in the same way: `zoneNotFound`, no record attached.
- **C.3** After each refusal B's pending changes were empty: the engine had dropped the save. B's next send asked for a batch, had nothing to send, and sent nothing. N-1 did not exist afterwards, neither record could be read (a direct read answered `zoneNotFound`), and a new engine was still told that N-1 had been deleted. When B then fetched, it was told of N-1's deletion and of N-2, as in A.
- **C.4** Engine Q, which also knew N-1, queued a new play and the toy into N-1 and then fetched without sending. The fetch reported N-1's deletion, and both saves were still pending afterwards. Sent, both were refused with `zoneNotFound` and dropped.
- **C.5** An engine with automatic syncing, made from B's state of before the deletion, with a new play queued into N-1 at once: in 60 seconds it began two fetches and two sends by itself. Its fetches began and ended within a millisecond and delivered nothing; its first send carried the play, which was refused with `zoneNotFound` once and dropped. It was never told of N-1's deletion in that minute.

**Seen, C.6** (2 of 2; runs 11 and 12): engine S, which also knew N-1 and had not fetched since the deletion, queued N-1's own save together with a new play and sent them. The zone was saved and the play accepted, and N-1 existed again. A new engine afterwards was no longer told that N-1 had been deleted: it was told of N-1 as a zone and received S's play. A, whose engine had deleted N-1, was told the same in its first fetch.

**Concluded:** a record's save into a zone that no longer exists fails with `zoneNotFound` and no record, with or without system fields, and creates nothing: neither the zone nor the record. The engine does not keep or retry such a save. Learning of the deletion by a fetch does not remove saves already pending for that zone. When the zone's own save goes with the record, though, the device that sends them makes the zone again under its old name, and from then on its deletion is reported to no one, as in E. An engine's scheduled fetches did not, in that minute, reach the server by themselves; that they did not reach it at all is an inference from their timing.

**Unknown:** what a second device would do: every engine of C ran in one process on one Mac, and none was woken by a push.

### D. Saving a zone that exists, and two engines saving the same new zone

**D.1** A makes Z with the toy and a play, and fetches. B fetches. B saves Z again. Then C, a new engine that never fetched, saves Z again together with a new play. Last, A saves the toy on the system fields it held from before the two saves of Z, and a new engine reads it.

**Seen** (7 of 7; runs 1, 2, 7, 9, 10, 11 and 12): both saves of Z were reported as saved, with no error. The toy and the play kept their values, change tags (3 and 4) and dates, read directly from the database before and after; their system fields archived 453 bytes smaller after B's save of Z than before it (2,354 and 2,398 bytes, then 1,901 and 1,945), in every run. A's next fetch after B's save reported nothing at all, not even Z as changed. After C's save it reported Z as changed and delivered only C's new play. A's save on its base from before was accepted, with tag 6, and the new engine read it with its values (4 of 4; runs 9 to 12).

**D.2** Two new engines in one process each queue a save of the same new zone and a play of their own, and send at once.

**Seen** (7 of 7; runs 1, 2, 7, 9, 10, 11 and 12): both zone saves were reported as saved; there was one zone of that name; a new engine received both plays. The two engines began their sends in the same millisecond, and the second zone save was reported 1.1 to 1.4 seconds after the first, after the first engine's play had been saved. In run 10 cloudd's debug log, which `log stream` read, showed why: cloudd, the system's CloudKit daemon, took both zone saves to "Saving Zones" in the same millisecond, then answered the second "Can't immediately grant exclusive gate … because zone … is held". The second went on only after the first had its answer; cloudd then fetched the zone's protection data (PCS) again and saved the zone a second time.

**D.3** Two copies of the app, in two processes, each save the same new zone and a play of their own at one agreed moment; a third launch looks.

**Seen** (10 of 10 rounds; races 1 and 2): both zone saves were reported as saved, one zone of that name existed, and the third launch received both plays. The two processes began their sends within 6 milliseconds of each other in race 1, and within 1 millisecond in race 2. The second zone save was reported 0.6 to 1.6 seconds after the first: in nine rounds after the first process's play had been saved, in one between the first process's zone and its play. In every round the first record in the zone had tag 3 and the second tag 4.

**Concluded:** saving a zone that exists changes nothing that another engine can see, and does not fail. Its records' system fields come back smaller afterwards, but a save on a base taken before is still accepted. Two engines that both save the same new zone both succeed and share one zone with both records. On one Mac, cloudd lets one save of a zone go to the server at a time, whichever process asks, so one Mac can never put two saves of a zone before the server at the same instant.

**Unknown:** what happens when two devices save the same new zone at the same instant (the design's open point 16). That needs two devices.

### E. A zone made again under its old name, with a token from far ahead

A makes Z with twelve plays in one send; B and B2 fetch them all (their tags 3 to e). A deletes Z, makes it again under the same name, and saves one play (its tag 3). B fetches. Then A saves fifteen more plays, one per send (tags 4 to i, past every tag of the first Z), and B fetches again. B2, which stayed away all that time, fetches now. Last, a new engine fetches. The same with one play instead of twelve. B2 was added after the review of this probe; earlier runs had B alone.

**Seen** (6 of 6 with twelve plays, 6 of 6 with one; runs 1, 2, 7, 9, 11 and 12; B2 3 of 3 each, runs 9, 11 and 12):

- B's fetch delivered the one play of Z made again, although its tag, 3, was below the tags B had seen in the first Z. B was told of no zone deletion and no record deletion, and got no error. The database changes named Z as changed. Afterwards B held all twelve plays of the first Z and the new one. The fifteen later plays all reached B in its next fetch.
- B2, back with its token from the first Z after Z made again had passed every tag it had seen, received all sixteen plays of Z made again, was told of no deletion, and got no error. It held its twelve old plays and the sixteen new ones.
- The new engine received only the sixteen plays of Z made again and was told of no deletion of Z.

**Concluded:** when a zone is made again under its old name, an engine that held a token for the old zone receives every record of the new zone, whether it comes back before the new zone reaches the tags it saw (B) or after the new zone has passed them (B2). The old token hides nothing. Nothing tells the engine that the old zone was deleted or that its old records are gone. Change tags count again from the start in the new zone (question 3 says how they count).

**Unknown:** whether the same holds after a purge or a reset made the zone go.

### F. How long deletion reports live

A new engine with no state fetches all zones, and the probe lists every zone deletion it is told of.

**Seen** (5 of 5; runs 1, 7, 8, 11 and 12, at 02:14:46, 02:39:23, 02:42:57, 11:00:21 and 11:03:18 UTC): the new engine was told of 59, 116, 118, 160 and 170 zone deletions, all with the reason `deleted`, and of no zone that existed. Each list held every zone this probe had deleted until then (8, 65, 67, 109 and 119 of them; the oldest, of run 1, deleted from 02:12:38 on) and the same 51 zones of the earlier probe (names beginning `NineRingsProbe_`, from ten of its runs). No deletion that one list held was missing from a later one. CloudKit's report carries no time, so the probe's own report dates only its own zones. The earlier probe's logs, which are not part of this probe, show three of its zones, `NineRingsProbe_D84AF8_q1` to `q3`, as already deleted at 01:02:27 UTC.

**Concluded:** a report of a zone's deletion was still delivered to a new engine 8 hours 50 minutes after the deletion, by this probe's own dating, and at least 10 hours after it, by the earlier probe's logs. No report seen had expired.

**Unknown:** how long reports live beyond that; Apple publishes no time span. `-cloudkit-probe F` asks again at any later time, and these zones are still listed for comparison.

### G. A save on a stale base, accepted in a zone made again: can the other engines read it

A makes Z with the toy (tag 3); B fetches it. A deletes Z, makes it again under the same name, and saves a new toy without system fields (tag 3 again). B, which never saw the new toy, saves on the system fields of the old one. A, a new engine and a direct read then read the toy. The same once more, with the new toy saved twice so that its tag (4) differs from B's.

**Seen, equal tags** (6 of 6; runs 1, 2, 7, 11 and 12): B's save was accepted, and the toy's tag became 4. It replaced the toy of Z made again, which B had never seen; the record kept that toy's creation date. A's fetch, a new engine's fetch and a direct read of the database all delivered it with `format` and `payload` readable through `encryptedValues`, with the values B wrote, and no error.

**Seen, different tags** (6 of 6; runs 1, 2, 7, 11 and 12): B's save was refused with `serverRecordChanged` (14), "client oplock error updating record", with the toy of Z made again attached as the server record.

**Concluded:** across a zone made again, a save on a base from the old zone was accepted when its tag equalled the current record's and refused when it did not; nothing else in the old base kept it out. The record it writes reads normally on every engine: the encrypted fields decrypt.

**Unknown:** nothing further within reach.

## Records, accounts and scheduling (questions 1 to 16)

These questions take up the other open points of the design's section 15 that one Mac can reach, and the behaviours its rules lean on. Each makes its own zone; its engines fetch that zone alone.

### 1. A first save under a record name that exists (open point 1)

A saves the toy and a play. B, which never fetched, saves a toy and the same play without system fields.

**Seen** (3 of 3; runs 3, 7 and 11): both of B's saves were refused with `serverRecordChanged` (14), server message "record to insert already exists". The error carried the server's record (A's) and B's own; the ancestor was a record with no tag and no values. B's pending changes were empty afterwards. B then saved the toy on the system fields of the record that came back, and it was accepted.

**Concluded:** a first save under a name that exists is refused like a save on an old tag, with the server's record attached, and the engine does not keep it.

### 2. A save on stale system fields (open point 2)

B fetches the toy; A changes it; B saves on the system fields it fetched.

**Seen** (3 of 3; runs 3, 7 and 11): refused with `serverRecordChanged` (14), "client oplock error updating record". The server record was A's second toy, and the ancestor record had B's base tag.

**Concluded:** the engine's saves are checked against the change tag: a save on an old tag does not overwrite. Question G shows the one case in which this check passes on a base from another zone.

### 3. What a saved record carries

**Seen** (3 of 3; runs 3, 7 and 11): the record that the engine hands back after a save is the very object the delegate gave it, now with its change tag and dates. Its encrypted values read back; `payload` read as a plain field is empty. Its system fields archive in about 2,350 bytes, and a record rebuilt from them has the tag and dates and no values. The first record saved together with a new zone gets tag 3, and each later save of a record in the zone takes the next value, written with digits and then letters: the twelve plays of question E had tags 3 to e, and fifteen later saves 4 to i, so the count is not hexadecimal.

**Concluded:** change tags are counters for each zone, not unique across zones; this is why the two tags of question G could be equal.

### 4. An engine's own save coming back as a fetched change

A saves the toy and then fetches; then, eight times, sends a change and fetches at once, the fetch a little later each round.

**Seen** (3 of 3; runs 3, 7 and 11): A's fetch after its own save delivered its own record once, with the saved tag. In the eight rounds of each run, a fetch that brought A's change back always came after the save's confirmation; in round 1 of each run the fetch did not bring the change back.

**Concluded:** an engine's own saves come back to it in later fetches. A fetched change was not seen before its own confirmation.

**Unknown:** whether that order holds always; twenty-four rounds do not rule the other order out.

### 5. A record deleted, then saved again under the same name

**Seen** (3 of 3; runs 3, 7 and 11): a save on the deleted record's system fields was refused with `unknownItem` (11), "recordChangeTag specified, but record not found", and dropped from the pending list. A save without system fields was accepted as a new record, with a new creation date. B, which still held the deleted record's system fields, saved after the record had been made again: refused with `serverRecordChanged`, the new record attached. B's fetch then delivered the new record and no deletion.

**Concluded:** a save on the system fields of a record that is gone fails with `unknownItem`; a save without them creates the record anew.

### 6. Deleting a record that is already gone

**Seen** (3 of 3; runs 3, 7 and 11): B's deletion of a play that A had deleted, and of a record that never existed, were both reported as deleted, with no error, and nothing stayed pending.

**Concluded:** a deletion of a record that does not exist succeeds.

### 7. Saving into a zone that was never made

**Seen** (3 of 3; runs 3, 7 and 11): a save into a zone that was never made was refused with `zoneNotFound` (26), "Zone does not exist", no record attached, and dropped from the pending list. With the zone's save queued too, after the record or before it, the engine sent the zone first and then the record, and both were saved.

**Concluded:** as for a deleted zone (question C): `zoneNotFound`, nothing created, nothing kept. The engine sends zone changes before record changes, whatever the order they were queued in.

### 8. A fetch from nothing, in a zone where records were deleted (open point 5, in part)

A and B each save plays; A deletes one of its own and one of B's. Then a new engine fetches.

**Seen** (3 of 3; runs 3, 7 and 11): the new engine received the three plays that remained and was told of both deletions.

**Concluded:** on one Mac, a fetch from nothing delivered deletions of records that were gone before it began.

**Unknown:** every engine here was on one Mac, so CloudKit may count them as the device that made the records; Apple's engineers describe a fetch from nothing that brings only some deletions. What the engine does with an expired change token could not be provoked.

### 9. The account event of a new engine (open point 14)

**Seen** (4 of 4; runs 3, 4, 11 and 13, and in every new engine of questions A to G): a new engine with no state, with automatic syncing off or on, reported `accountChange` with `signIn`, and the user record id it named was the one `CKContainer.userRecordID()` returns. With syncing off it came at the start of the first fetch or send. An engine made from a saved state reported no account event.

**Concluded:** an engine that starts from nothing reports a sign-in, with the account's id; one that starts from a state does not.

**Unknown:** what an engine reports when the app's switch in Settings is turned off or on (open point 3). The probe changes no settings.

### 10. Automatic syncing and pushes (open point 6)

**Seen** (4 of 4; runs 3, 4, 11 and 13): in runs 4 and 13, where it was asked first in a fresh launch, the app was not registered for remote notifications, and was still not after an engine with automatic syncing off had fetched; 15 seconds after two engines with automatic syncing were made, it was registered. In runs 3 and 11 it was registered already, by the engine with automatic syncing of question 9, asked before it; every launch began unregistered. The database already held one subscription, `CKSyncEngineDatabaseSubscription-Private`, before any engine of the run was made. A's engine sent a queued toy by itself 2.9 to 3.2 seconds after it was queued. B's engine, with automatic syncing on, did not fetch A's toy by itself within 240 seconds, and began no fetch at all in that time.

**Concluded:** an engine with automatic syncing registers the app for remote notifications by itself, and sends queued changes by itself within seconds. On one Mac it did not fetch another engine's change by itself within four minutes.

**Unknown:** whether pushes reach another device, wake an iPhone, or arrive on a Mac. On one Mac the engines are most likely one device to CloudKit, which may not push a device's own changes back to it.

### 11. Two engines from copies of one saved state (open point 4)

A saves the toy and a play, fetches, and queues another play without sending. Its state and records are copied into two new engines, A1 and A2, as two devices restored from one backup.

**Seen** (3 of 3; runs 3, 7 and 11): both copies started with the unsent play pending. A1 sent the toy on the copied base and the play: both accepted. A2 sent its toy on the same base: refused with `serverRecordChanged`, A1's toy attached; its copy of the play: refused with "record to insert already exists", A1's save attached. Each then saved a play of its own, and each fetch from the copied tokens delivered every change made since the copy, with no error.

**Concluded:** two engines from one saved state behave as two devices: the copied tokens work, and the change tag settles which toy stands.

**Unknown:** what the engine does with a state restored from a real backup or a device-to-device transfer, and after a long time.

### 12. Records as the app writes them, against the imported schema

**Seen** (3 of 3; runs 3, 7 and 11): a `Toy` and a `FinishedPlay` with `format` written as an `Int` and `payload` as `Data` through `encryptedValues` were accepted. Another engine read `format` back as a number (read as `Int`: the same value) and `payload` as `Data` of the same length, both through `encryptedValues`, and found no plain values.

**Concluded:** what the app writes fits the schema in [`CloudKit/NineRings.ckdb`](../CloudKit/NineRings.ckdb).

### 13. A fetch when the app comes to the front (open point 7)

An engine with automatic syncing runs while the app is hidden and shown again, and then while the probe posts the system's notifications that the app became active. Before the posting, another engine saves a play.

**Seen** (3 of 3; runs 3, 7 and 11, the first launched in front, the others behind the app in front): the probe could not bring its own app to the front: after it hid and showed itself and asked to be activated, the app was not active, and the engine began no fetch within 30 seconds. After the posted notifications the engine began a scheduled fetch about half a second later. In runs 7 and 11, where another engine had saved a play just before, that fetch delivered the play 1.2 and 1.3 seconds after the notifications (2 of 2).

**Concluded:** the engine starts a fetch when it hears that the app became active.

**Unknown:** what happens on a real return to the front, and on iPhone and iPad.

### 14. A save and a deletion queued for one record

**Seen** (3 of 3; runs 3, 7 and 11): a save queued and then a deletion of the same record left only the deletion pending, and only it was sent, for a record that existed and for one never sent; a deletion and then a save left only the save, which was sent and accepted.

**Concluded:** for one record, the engine keeps only the change queued last.

### 15 and 16. A save whose answer the app never stores (section 10 of the design)

Question 15 keeps the engine's state and the device's records at every state update, sends a change of the toy and a new play, and ends the process as soon as the save's confirmation arrives, before storing it. Question 16, the next launch, starts from what was kept.

**Seen** (2 of 2; runs 5 and 6, 14 and 15): the kept state still listed both saves as pending, and the toy's base still had the tag from before. Sent again, the toy was refused with `serverRecordChanged`, its own landed save attached as the server's record, and the play with "record to insert already exists", its own landed save attached. The fetch then delivered both landed records.

**Concluded:** a save whose confirmation the app never stored is still pending after a restart, and sending it again is refused with the save that landed attached.

**Unknown:** whether the engine itself would have sent it again, and what becomes of a send under way when an iPhone suspends the app.

## What the probe could not reach

- **The reasons `purged` and `encryptedDataReset`** (open points 8 and 15). Only `deleted` can be produced in the development environment.
- **Pushes between devices, real devices, and production.** Everything ran on one Mac, in development, with one account.
- **Two devices that save the same new zone at the same instant** (open point 16). On one Mac, cloudd lets one save of a zone go to the server at a time (question D).
- **How long deletion reports live** beyond the ten hours seen (open point 13; question F), and **an expired change token** (open point 5).
- **The app's switch in Settings** (open point 3), **a restored backup** (open point 4, beyond question 11), and **accounts in unusual states** (open point 12). The probe changes no settings and no account.
