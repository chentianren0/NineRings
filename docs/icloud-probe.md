# What CloudKit and its sync engine do: the probe's findings

The iCloud design (`docs/icloud.md`) rests on behaviours of CloudKit and of `CKSyncEngine` that Apple does not document. Its section 15 lists them as open points. The probe, [`NineRings/CloudProbe/`](../NineRings/CloudProbe/), is debug-only code in the Mac app that tries them against CloudKit's development environment. This page says, for each question, what was seen, on which system and how often, what follows from it, and what stays unknown.

Three things are kept apart under every question:

- **Seen**: what the probe did and what came back, with how often: "(3 of 3)" means that the result was the same in each of the three runs that asked.
- **Concluded**: what follows from what was seen, and only that.
- **Unknown**: what the probe could not reach.

The probe finds facts. What the design makes of them is the design's.

## Where, when and how often

- **System:** macOS 27.3 (26C5047e), Xcode 27.3 (27C5035i), `cktool` 1.0.23001.
- **Environment:** the development environment of the container `iCloud.com.chentianren.PlayNineRings`, its private database, with the iCloud account this Mac is signed in to. Production was not seen.
- **When:** 20 November 2026, in UTC (the evening of 19 November in Pacific time). Each question below names its runs:

  | Run | Began | Questions |
  |---|---|---|
  | 1 | 02:12:31 | A, C, D, E, F, G |
  | 2 | 02:15:36 | A, A, C, D, E, G, G |
  | race 1 | 02:18:41 | D.3, five rounds, two processes each |
  | 3 | 02:22:03 | 1 to 14 |
  | 4 | 02:29:30 | 10, 9 |
  | 5 and 6 | 02:34:24 | 15, then 16 |
  | 7 | 02:34:58 | 1 to 8, 11 to 14, A, C, D, E, F, G |
  | 8 | 02:42:56 | F |
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
- The probe stops before reaching CloudKit if the build lacks the iCloud entitlement, if it would talk to production, or if no account is available.
- Each question makes its own zones, named `NineRingsProbeAgain_<run>_<question>…`, and deletes them at its end. At the start and the end of a run the probe deletes every zone whose name begins with `NineRingsProbeAgain_`, and it refuses to delete any other zone.
- Each device of the probe is a `CKSyncEngine` with its own state and its own records in memory. Automatic syncing is off, except where a question says so, and the probe sends and fetches by hand. It never calls the engine from inside a callback. Its records are the design's: `Toy`, named `toy`, and `FinishedPlay`, named by a UUID, each with `format` and `payload` written through `encryptedValues`.
- The engines of questions A to G fetch all zones of the database, as the app's would, unless a question says otherwise. The report shows the probe's own zones and only counts the others. The engines of questions 1 to 16 fetch their own zone only.

## In brief

The design's open points (section 15) that a question takes up are named in the last column; the others inform the rules of its sections 6 to 10.

| | Question | What was seen | How often | Open point |
|---|---|---|---|---|
| A | N-1 deleted and N-2 made: an engine that knew N-1 | Told of N-1's deletion (`deleted`) and of N-2 in one report, then given N-2's records unasked. A fetch scoped to N-1 still hears of N-2, and fetches it at the next wider fetch | 4 of 4 | |
| B | The same: a new engine | Told of N-1's deletion, of N-2 with its records, and of every other deleted zone whose name is not in use | 4 of 4 | |
| C | Saving into N-1 before fetching | `zoneNotFound`, no record attached, with or without system fields. Nothing is created; the engine drops the save. Saves already pending stay pending when a fetch reports the deletion | 3 of 3 | |
| D | Saving a zone that exists; two engines saving one new zone | No error, nothing changes, other engines hear nothing. Both succeed, with one zone and both records; on one Mac the two saves ran one after the other, also from two processes | 3 of 3; 5 of 5 in two processes | 16, in part |
| E | A zone made again under its old name | An old token hides none of the new records; no deletion is reported; the old records stay with the engine | 3 of 3 with 12 records, 3 of 3 with 1 | |
| F | How long deletion reports live | Still delivered 30 minutes after the deletion (this probe's dating) and at least 100 minutes after it (the earlier probe's logs); none had expired | 3 of 3 | 13 |
| G | A save on a stale base in a zone made again | Accepted when the tags are equal, and readable by every engine; refused when they differ | 4 of 4 each | |
| 1 | A first save under a name that exists | `serverRecordChanged`, "record to insert already exists", with the server's record | 2 of 2 | 1 |
| 2 | A save on stale system fields | `serverRecordChanged`, "client oplock error updating record", with all three records | 2 of 2 | 2 |
| 3 | What a saved record carries | Change tags count up in each zone; the first record saved with a zone has tag 3 | 2 of 2 | |
| 4 | An engine's own save coming back | It comes back, after its confirmation in every round | 2 of 2, 16 rounds | |
| 5 | A record deleted, then saved again | On the old system fields: `unknownItem`. Without them: a new record | 2 of 2 | |
| 6 | Deleting a record that is gone | Reported as deleted, no error | 2 of 2 | |
| 7 | Saving into a zone never made | `zoneNotFound`, dropped. Zones are sent before records | 2 of 2 | |
| 8 | A fetch from nothing after deletions | Both deletions delivered, on one Mac | 2 of 2 | 5, in part |
| 9 | The account event of a new engine | `signIn` with the account's id; none from a saved state | 2 of 2 | 14 |
| 10 | Automatic syncing and pushes | The engine registers for pushes by itself and sends within seconds; it did not fetch another engine's change by itself in 240 s | 2 of 2 | 6, in part |
| 11 | Two engines from one saved state | They behave as two devices | 2 of 2 | 4, in part |
| 12 | Records against the schema | Accepted, and read back with the same types | 2 of 2 | |
| 13 | A fetch when the app becomes active | The engine fetches half a second after the notification; a real return to the front was not produced | 2 of 2 | 7, in part |
| 14 | A save and a deletion queued for one record | The later replaces the earlier | 2 of 2 | |
| 15, 16 | A save whose answer is never stored | Still pending after a restart; sent again, refused with the landed save attached | 1 of 1 | |

## A deleted zone (questions A to G)

"N-1" and "N-2" are two zones of different names. N-1 is deleted and not made again; N-2 is the next zone. "Z" is a zone that is deleted and made again under the same name. Engine A makes the changes; engine B, and the others named, look.

### A. N-1 deleted and N-2 made: what an engine that knew N-1 is told

A makes N-1 with the toy and a play. B and B1 fetch them. A deletes N-1 through its engine, then makes N-2 with a toy. B fetches all zones; B1 fetches N-1 alone, then all zones.

**Seen** (4 of 4; runs 1, 2 and 7):

- **A.1** B's next fetch reported N-1 as deleted, with the reason `deleted`.
- **A.2** The same fetch reported N-2 as a changed zone and delivered N-2's toy, which B had not asked for by name. The order of events: first one `fetchedDatabaseChanges` event, which held both lists, N-2 among the modifications and N-1 among the deletions; then the fetch of N-2 began, its toy arrived in `fetchedRecordZoneChanges`, and the fetch of N-2 ended. The engine began no fetch of N-1, reported no error, and delivered no deletion of N-1's records. B's two records of N-1 stayed in its store, where the engine leaves them to the app. B's pending changes were empty. A second fetch reported nothing.
- **A.3** B1, whose fetch was scoped to N-1 alone, got the same `fetchedDatabaseChanges` event: N-1 deleted (`deleted`) and N-2 changed. It did not fetch N-2 or receive its toy. B1's next fetch, of all zones, had no database changes, so it did not name N-2 again, and yet the engine fetched N-2 and delivered its toy.

**Concluded:** an engine that knew a zone is told of its deletion and of the new zone in one report, and fetches the new zone's records by itself unless the fetch's scope leaves the zone out. The database report is not limited by the fetch's scope. A zone that a scoped fetch left out is fetched at the next fetch whose scope includes it.

**Unknown:** whether a purge or a reset of encrypted data is reported in the same way.

### B. The same: what a new engine with no state is told

After A's changes, a new engine fetches all zones for the first time.

**Seen** (4 of 4; runs 1, 2 and 7): its first fetch reported N-1 as deleted (`deleted`) and N-2 as a zone, and delivered N-2's toy, nothing of N-1. The same single `fetchedDatabaseChanges` event also listed every other zone of the database that had been deleted and whose name was not in use: 52, 62, 64 and 109 deletions in the four runs, the probe's own and older ones (see F). It began with an `accountChange` sign-in event (question 9).

**Concluded:** an engine with no state learns of past zone deletions in its first fetch, together with the zones that exist. It is not told which of the deleted zones it ever knew.

**Unknown:** the same as for A.

### C. Saving into N-1 before the deletion has been fetched

As in A, but B, which holds state and records for N-1, does not fetch after the deletion. It saves into N-1: first a new play, then the toy on the system fields it holds.

**Seen** (3 of 3; runs 1, 2 and 7):

- **C.1** The new play was refused with `CKError.zoneNotFound` (26), server message "Zone does not exist", with no server record attached.
- **C.2** The toy on B's system fields was refused in the same way: `zoneNotFound`, no record attached.
- **C.3** After each refusal B's pending changes were empty: the engine had dropped the save. B's next send asked for a batch, had nothing to send, and sent nothing. N-1 did not exist afterwards, neither record could be read (a direct read answered `zoneNotFound`), and a new engine was still told that N-1 had been deleted. When B then fetched, it was told of N-1's deletion and of N-2, as in A.
- **C.4** Engine Q, which also knew N-1, queued a new play and the toy into N-1 and then fetched without sending. The fetch reported N-1's deletion, and both saves were still pending afterwards. Sent, both were refused with `zoneNotFound` and dropped.
- **C.5** An engine with automatic syncing, made from B's state of before the deletion, with a new play queued into N-1 at once: in 60 seconds it began two fetches and two sends by itself. Its fetches began and ended within a millisecond and delivered nothing; its first send carried the play, which was refused with `zoneNotFound` once and dropped. It was never told of N-1's deletion in that minute.

**Concluded:** a save into a zone that no longer exists fails with `zoneNotFound` and no record, with or without system fields, and creates nothing: neither the zone nor the record. The engine does not keep or retry such a save. Learning of the deletion by a fetch does not remove saves already pending for that zone. An engine's scheduled fetches did not, in that minute, reach the server by themselves; that they did not reach it at all is an inference from their timing.

**Unknown:** whether a scheduled fetch on a real device, woken by a push, would have learned of the deletion first.

### D. Saving a zone that exists, and two engines saving the same new zone

**D.1** A makes Z with the toy and a play, and fetches. B fetches. B saves Z again. Then C, a new engine that never fetched, saves Z again together with a new play.

**Seen** (3 of 3; runs 1, 2 and 7): both saves of Z were reported as saved, with no error. The toy and the play kept their values and change tags (3 and 4) and their dates, read directly from the database before and after. A's next fetch after B's save reported nothing at all, not even Z as changed. After C's save it reported Z as changed and delivered only C's new play.

**D.2** Two new engines in one process each queue a save of the same new zone and a play of their own, and send at once.

**Seen** (3 of 3; runs 1, 2 and 7): both zone saves were reported as saved; there was one zone of that name; a new engine received both plays. The saves did not overlap: the second engine's zone save was reported 1.2, 1.3 and 1.4 seconds after the first's, after the first engine's play had been saved.

**D.3** Two copies of the app, in two processes, each save the same new zone and a play of their own at one agreed moment; a third launch looks.

**Seen** (5 of 5 rounds; race 1): both zone saves were reported as saved, one zone of that name existed, and the third launch received both plays. The two processes began their sends within 6 milliseconds of each other in every round, and yet the second zone save was reported 1.3 to 1.6 seconds after the first, each time after the first process's play had been saved: the first record in the zone had tag 3 and the second tag 4.

**Concluded:** saving a zone that exists changes nothing that another engine can see, and does not fail. Two engines on one Mac that both save the same new zone both succeed and share one zone with both records. On one Mac the two saves were carried out one after the other, also from two processes, so a save at the same instant was not produced.

**Unknown:** where the saves were put one after the other (on the Mac or on the server), and what happens when two devices save the same new zone at the same instant (the design's open point 16).

### E. A zone made again under its old name, with a token from far ahead

A makes Z with twelve plays in one send; B fetches them all (their tags 3 to e). A deletes Z, makes it again under the same name, and saves one play (its tag 3). B fetches. Then A saves fifteen more plays, one per send, and B fetches again. Last, a new engine fetches. The same with one play instead of twelve.

**Seen** (3 of 3 with twelve plays, 3 of 3 with one; runs 1, 2 and 7):

- B's fetch delivered the one play of Z made again, although its tag, 3, was below the tags B had seen in the first Z.
- B was told of no zone deletion and no record deletion, and got no error. The database changes named Z as changed.
- Afterwards B held all twelve plays of the first Z and the new one.
- The fifteen later plays (tags 4 to i) all reached B in its next fetch.
- The new engine received only the sixteen plays of Z made again and was told of no deletion of Z.

**Concluded:** when a zone is made again under its old name, an engine that held a token for the old zone receives every record of the new zone, so the old token hides nothing, even from twelve changes ahead. Nothing tells it that the old zone was deleted or that its old records are gone. Change tags count again from the start in the new zone (question 3 says how they count).

**Unknown:** whether the same holds after a purge or a reset made the zone go.

### F. How long deletion reports live

A new engine with no state fetches all zones, and the probe lists every zone deletion it is told of.

**Seen** (runs 1, 7 and 8, at 02:14:46, 02:39:23 and 02:42:57 UTC): the new engine was told of 59, 116 and 118 zone deletions, all with the reason `deleted`, and of no zone that existed. Each list held every zone this probe had deleted until then (8, 65 and 67 of them; the oldest, of run 1, deleted from 02:12:38 on) and the same 51 zones of the earlier probe (names beginning `NineRingsProbe_`, from ten of its runs). No deletion that one list held was missing from a later one. CloudKit's report carries no time, so the probe's own report dates only its own zones. The earlier probe's logs, which are not part of this probe, show three of its zones, `NineRingsProbe_D84AF8_q1` to `q3`, as already deleted at 01:02:27 UTC.

**Concluded:** a report of a zone's deletion was still delivered to a new engine 30 minutes after the deletion, by this probe's own dating, and at least 100 minutes after it, by the earlier probe's logs. No report seen had expired.

**Unknown:** how long reports live beyond that: this probe's runs spanned half an hour, and Apple publishes no time span. `-cloudkit-probe F` asks again at any later time; the earlier probe's zones and these are still listed for comparison.

### G. A save on a stale base, accepted in a zone made again: can the other engines read it

A makes Z with the toy (tag 3); B fetches it. A deletes Z, makes it again under the same name, and saves a new toy without system fields (tag 3 again). B, which never saw the new toy, saves on the system fields of the old one. A, a new engine and a direct read then read the toy. The same once more, with the new toy saved twice so that its tag (4) differs from B's.

**Seen, equal tags** (4 of 4; runs 1, 2 and 7): B's save was accepted, and the toy's tag became 4. It replaced the toy of Z made again, which B had never seen; the record kept that toy's creation date. A's fetch, a new engine's fetch and a direct read of the database all delivered it with `format` and `payload` readable through `encryptedValues`, with the values B wrote, and no error.

**Seen, different tags** (4 of 4; runs 1, 2 and 7): B's save was refused with `serverRecordChanged` (14), "client oplock error updating record", with the toy of Z made again attached as the server record.

**Concluded:** across a zone made again, CloudKit compares only the change tags. A save on a base from the old zone is accepted when the tags happen to be equal, and the record it writes reads normally on every engine: the encrypted fields decrypt.

**Unknown:** nothing further within reach.

## Records, accounts and scheduling (questions 1 to 16)

These questions take up the other open points of the design's section 15 that one Mac can reach, and the behaviours its rules lean on. Each makes its own zone; its engines fetch that zone alone.

### 1. A first save under a record name that exists (open point 1)

A saves the toy and a play. B, which never fetched, saves a toy and the same play without system fields.

**Seen** (2 of 2; runs 3 and 7): both of B's saves were refused with `serverRecordChanged` (14), server message "record to insert already exists". The error carried the server's record (A's) and B's own; the ancestor was a record with no tag and no values. B's pending changes were empty afterwards. B then saved the toy on the system fields of the record that came back, and it was accepted.

**Concluded:** a first save under a name that exists is refused like a save on an old tag, with the server's record attached, and the engine does not keep it.

### 2. A save on stale system fields (open point 2)

B fetches the toy; A changes it; B saves on the system fields it fetched.

**Seen** (2 of 2; runs 3 and 7): refused with `serverRecordChanged` (14), "client oplock error updating record". The server record was A's second toy, and the ancestor record had B's base tag.

**Concluded:** the engine's saves are checked against the change tag: a save on an old tag does not overwrite. Question G shows the one case in which this check passes on a base from another zone.

### 3. What a saved record carries

**Seen** (2 of 2; runs 3 and 7): the record that the engine hands back after a save is the very object the delegate gave it, now with its change tag and dates. Its encrypted values read back; `payload` read as a plain field is empty. Its system fields archive in about 2,350 bytes, and a record rebuilt from them has the tag and dates and no values. The first record saved together with a new zone gets tag 3, and each later save of a record in the zone takes the next value, written with digits and then letters: the twelve plays of question E had tags 3 to e, and fifteen later saves 4 to i, so the count is not hexadecimal.

**Concluded:** change tags are counters for each zone, not unique across zones; this is why the two tags of question G could be equal.

### 4. An engine's own save coming back as a fetched change

A saves the toy and then fetches; then, eight times, sends a change and fetches at once, the fetch a little later each round.

**Seen** (2 of 2; runs 3 and 7): A's fetch after its own save delivered its own record once, with the saved tag. In the eight rounds of each run, a fetch that brought A's change back always came after the save's confirmation; in round 1 of each run the fetch did not bring the change back.

**Concluded:** an engine's own saves come back to it in later fetches. A fetched change was not seen before its own confirmation.

**Unknown:** whether that order holds always; sixteen rounds do not rule the other order out.

### 5. A record deleted, then saved again under the same name

**Seen** (2 of 2; runs 3 and 7): a save on the deleted record's system fields was refused with `unknownItem` (11), "recordChangeTag specified, but record not found", and dropped from the pending list. A save without system fields was accepted as a new record, with a new creation date. B, which still held the deleted record's system fields, saved after the record had been made again: refused with `serverRecordChanged`, the new record attached. B's fetch then delivered the new record and no deletion.

**Concluded:** a save on the system fields of a record that is gone fails with `unknownItem`; a save without them creates the record anew.

### 6. Deleting a record that is already gone

**Seen** (2 of 2; runs 3 and 7): B's deletion of a play that A had deleted, and of a record that never existed, were both reported as deleted, with no error, and nothing stayed pending.

**Concluded:** a deletion of a record that does not exist succeeds.

### 7. Saving into a zone that was never made

**Seen** (2 of 2; runs 3 and 7): a save into a zone that was never made was refused with `zoneNotFound` (26), "Zone does not exist", no record attached, and dropped from the pending list. With the zone's save queued too, after the record or before it, the engine sent the zone first and then the record, and both were saved.

**Concluded:** as for a deleted zone (question C): `zoneNotFound`, nothing created, nothing kept. The engine sends zone changes before record changes, whatever the order they were queued in.

### 8. A fetch from nothing, in a zone where records were deleted (open point 5, in part)

A and B each save plays; A deletes one of its own and one of B's. Then a new engine fetches.

**Seen** (2 of 2; runs 3 and 7): the new engine received the three plays that remained and was told of both deletions.

**Concluded:** on one Mac, a fetch from nothing delivered deletions of records that were gone before it began.

**Unknown:** every engine here was on one Mac, so CloudKit may count them as the device that made the records; Apple's engineers describe a fetch from nothing that brings only some deletions. What the engine does with an expired change token could not be provoked.

### 9. The account event of a new engine (open point 14)

**Seen** (2 of 2; runs 3 and 4, and in every new engine of questions A to G): a new engine with no state, with automatic syncing off or on, reported `accountChange` with `signIn`, and the user record id it named was the one `CKContainer.userRecordID()` returns. With syncing off it came at the start of the first fetch or send. An engine made from a saved state reported no account event.

**Concluded:** an engine that starts from nothing reports a sign-in, with the account's id; one that starts from a state does not.

**Unknown:** what an engine reports when the app's switch in Settings is turned off or on (open point 3). The probe changes no settings.

### 10. Automatic syncing and pushes (open point 6)

**Seen** (runs 3 and 4): in run 4, asked first in a fresh launch, the app was not registered for remote notifications, and was still not after an engine with automatic syncing off had fetched; 15 seconds after two engines with automatic syncing were made, it was registered. In run 3 it was registered already, by the engine with automatic syncing of question 9, asked before it; every launch began unregistered. The database already held one subscription, `CKSyncEngineDatabaseSubscription-Private`, before any engine of the run was made. A's engine sent a queued toy by itself 3.2 seconds after it was queued. B's engine, with automatic syncing on, did not fetch A's toy by itself within 240 seconds, and began no fetch at all in that time.

**Concluded:** an engine with automatic syncing registers the app for remote notifications by itself, and sends queued changes by itself within seconds. On one Mac it did not fetch another engine's change by itself within four minutes.

**Unknown:** whether pushes reach another device, wake an iPhone, or arrive on a Mac. On one Mac the engines are most likely one device to CloudKit, which may not push a device's own changes back to it.

### 11. Two engines from copies of one saved state (open point 4)

A saves the toy and a play, fetches, and queues another play without sending. Its state and records are copied into two new engines, A1 and A2, as two devices restored from one backup.

**Seen** (2 of 2; runs 3 and 7): both copies started with the unsent play pending. A1 sent the toy on the copied base and the play: both accepted. A2 sent its toy on the same base: refused with `serverRecordChanged`, A1's toy attached; its copy of the play: refused with "record to insert already exists", A1's save attached. Each then saved a play of its own, and each fetch from the copied tokens delivered every change made since the copy, with no error.

**Concluded:** two engines from one saved state behave as two devices: the copied tokens work, and the change tag settles which toy stands.

**Unknown:** what the engine does with a state restored from a real backup or a device-to-device transfer, and after a long time.

### 12. Records as the app writes them, against the imported schema

**Seen** (2 of 2; runs 3 and 7): a `Toy` and a `FinishedPlay` with `format` written as an `Int` and `payload` as `Data` through `encryptedValues` were accepted. Another engine read `format` back as a number (read as `Int`: the same value) and `payload` as `Data` of the same length, both through `encryptedValues`, and found no plain values.

**Concluded:** what the app writes fits the schema in [`CloudKit/NineRings.ckdb`](../CloudKit/NineRings.ckdb).

### 13. A fetch when the app comes to the front (open point 7)

An engine with automatic syncing runs while the app is hidden and shown again, and then while the probe posts the system's notifications that the app became active. Before the posting, another engine saves a play.

**Seen** (2 of 2; runs 3 and 7, the first launched in front, the second behind the app in front): the probe could not bring its own app to the front: after it hid and showed itself and asked to be activated, the app was not active, and the engine began no fetch within 30 seconds. After the posted notifications the engine began a scheduled fetch about half a second later. In run 7, where another engine had saved a play just before, that fetch delivered the play 1.2 seconds after the notifications (1 of 1).

**Concluded:** the engine starts a fetch when it hears that the app became active.

**Unknown:** what happens on a real return to the front, and on iPhone and iPad.

### 14. A save and a deletion queued for one record

**Seen** (2 of 2; runs 3 and 7): a save queued and then a deletion of the same record left only the deletion pending, and only it was sent, for a record that existed and for one never sent; a deletion and then a save left only the save, which was sent and accepted.

**Concluded:** for one record, the engine keeps only the change queued last.

### 15 and 16. A save whose answer the app never stores (section 10 of the design)

Question 15 keeps the engine's state and the device's records at every state update, sends a change of the toy and a new play, and ends the process as soon as the save's confirmation arrives, before storing it. Question 16, the next launch, starts from what was kept.

**Seen** (1 of 1; runs 5 and 6): the kept state still listed both saves as pending, and the toy's base still had the tag from before. Sent again, the toy was refused with `serverRecordChanged`, its own landed save attached as the server's record, and the play with "record to insert already exists", its own landed save attached. The fetch then delivered both landed records.

**Concluded:** a save whose confirmation the app never stored is still pending after a restart, and sending it again is refused with the save that landed attached.

**Unknown:** whether the engine itself would have sent it again, and what becomes of a send under way when an iPhone suspends the app.

## What the probe could not reach

- **The reasons `purged` and `encryptedDataReset`** (open points 8 and 15). Only `deleted` can be produced in the development environment.
- **Pushes between devices, real devices, and production.** Everything ran on one Mac, in development, with one account.
- **Two devices that save the same new zone at the same instant** (open point 16). On one Mac the saves ran one after the other (question D).
- **How long deletion reports live** beyond the 100 minutes seen (open point 13; question F), and **an expired change token** (open point 5).
- **The app's switch in Settings** (open point 3), **a restored backup** (open point 4, beyond question 11), and **accounts in unusual states** (open point 12). The probe changes no settings and no account.
