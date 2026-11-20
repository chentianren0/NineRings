# What CloudKit's sync engine does: the probe's findings

The iCloud design rests on a few behaviours of `CKSyncEngine` that Apple does not document (section 15 of the design, and its sources 9, 10, 17, 18 and 49 to 53). The probe, [`NineRings/CloudProbe/`](../NineRings/CloudProbe/), is debug-only code in the app that tries each of them against CloudKit's development environment. This page says what it did, what came back, and where that differs from what the design expects.

Each point keeps three things apart: what the probe **did**, what **came back**, and how that stands **against the design**. What is only inferred says so.

## Where and when

- macOS 27.3 (26C5047e), Xcode 27.3 (27C5035i), `cktool` 1.0.23001.
- 19 November 2026, between 17:00 and 17:45 Pacific time.
- The development environment of the app's container, its private database, and the iCloud account this Mac is signed in to.
- Every engine ran in one app process, on one Mac. To CloudKit they are most likely one device. Several points below say what that leaves open.
- Ten runs: questions 1 to 3 as a first try, and questions 1 to 14 with the app started by running its executable; then, through LaunchServices, questions 15, 4, 11 and 14, question 15 again with two saves added, a run of questions 1 to 15, a run of questions 15 and 16 after question 15 had grown, questions 17 and 18, one launch each, a run of questions 19, 20, 21 and 15, and question 20 once more after a fix. The results below are the latest run's for each question, and every earlier run that asked the same question gave the same result, except where a point says otherwise.

## How it runs

A signed debug build, with the iCloud entitlement, started through LaunchServices with the launch switch `-cloudkit-probe`:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/probe-build -allowProvisioningUpdates build
```

```bash
open -n --stdout /tmp/probe.txt --stderr /tmp/probe.err /tmp/probe-build/Build/Products/Debug/NineRings.app --args -ApplePersistenceIgnoreState YES -cloudkit-probe all
```

- `-cloudkit-probe all` asks every question but 17 and 18; `-cloudkit-probe 1,2,15` asks those. Questions 17 and 18 take a launch each, in that order: `-cloudkit-probe 17`, then `-cloudkit-probe 18`. Like every launch switch of the app, it takes a value, and only a debug build reads it.
- The report goes to standard output, one line per event, and to the log under the category `CloudProbe`. The app writes no file of its own, and it quits when the probe is done. To stop it earlier, quit it by its process id: other copies of the app may be running.
- While the probe runs, the app keeps its records in memory, so nothing else in it talks to CloudKit.
- The probe stops before reaching CloudKit if the build lacks the iCloud entitlement, if it would talk to production, or if no account is available.
- Each question makes its own zone, named `NineRingsProbe_<run>_q<n>`, and its own engines, and deletes the zone at its end. At the start and the end of a run the probe deletes every zone whose name begins with `NineRingsProbe_`, and nothing else.
- Each device of the probe is a `CKSyncEngine` with its own state and its own records in memory. Automatic syncing is off, except in questions 10, 11 and 14, so the probe sends and fetches by hand. It never calls the engine from inside a callback. Its records are the design's: `Toy`, named `toy`, and `FinishedPlay`, named by a UUID, with `format` and `payload` written through `encryptedValues`.
- **Start it through LaunchServices** (`open`), not by running the executable. Started directly, the engine's background scheduling failed every time ("BUG IN CLOUDKIT: Error submitting background task request: Error Domain=BGSystemTaskSchedulerErrorDomain Code=3", after "Could not find specified service"), and an engine with automatic syncing never ran its first sync. Through LaunchServices it did.

## In brief

| | Question | What came back | Against the design |
|---|---|---|---|
| 1 | First save under a name that exists | `serverRecordChanged`, "record to insert already exists", with the server's and the client's record; the ancestor is empty | Agrees (open point 1) |
| 2 | Save on stale system fields | `serverRecordChanged`, "client oplock error updating record", with all three records | Agrees (open point 2), but see 15 |
| 3 | A saved record | The object handed in, with tag and dates; its encrypted values read back; tags are hexadecimal counters per zone | Agrees |
| 4 | Own save fetched back | Yes. Never before its confirmation in 19 tries | Agrees; the early case is not ruled out |
| 5 | Deleted, then saved again | Old system fields: `unknownItem`. None: a new record | Agrees |
| 6 | Deleting what is gone | Reported as deleted, no error | Agrees, and simpler |
| 7 | Saving into a missing zone | `zoneNotFound`; the engine drops the save. With the zone queued, zones go first | Agrees |
| 8 | Fetch from nothing after deletions | Both deletions delivered | Cannot separate devices on one Mac |
| 9 | A zone deleted | `deleted` to every engine. **A new engine is told of earlier zone deletions too** | **Differs** |
| 10 | Account event of a new engine | `signIn` with the account's own user record id; none from a saved state | Agrees; answers open point 14 |
| 11 | Automatic syncing | The engine registers for pushes by itself; it sent by itself within 3 s; the other engine never fetched | Push delivery not testable on one Mac |
| 12 | Two engines from one saved state | Behave as two devices; the copied tokens work | Agrees |
| 13 | Field types | `ENCRYPTED INT64` and `ENCRYPTED BYTES` | Agrees |
| 14 | Fetch on coming to the front | The engine fetches when it hears the app become active; a real return to the front was not produced | Answers open point 7 in part |
| 15 | A zone deleted and made again | **Nothing of the deletion reaches an engine that knew the old zone: it keeps the old zone's records. Tags start again, and a save on a base from the old zone is accepted when the tags coincide** | **Differs**; answers open point 13 |
| 16 | A save and a deletion queued for one record | The later replaces the earlier; only it is sent | Agrees |
| 17, 18 | A save whose answer is never stored | The saved state still lists the save; sent again, it is refused with the device's own save attached | Agrees |
| 19 | A zone given up for another name | Every engine that knew the old zone, and every new one, is told of its deletion with the reason; saves into it fail with `zoneNotFound` and create nothing | Facts for the correction being weighed |
| 20 | Saving a zone that exists; one new zone saved by two engines | Nothing changes, and nobody is told; both saves succeed, with one zone | Agrees |
| 21 | A zone made again, through a token far ahead of its counter | Every new record arrives; the old records are never reported deleted | Part of 15 |

## Point by point

### 1. A first save under a record name that exists

**Did.** Engine A made the zone and saved a `Toy` named `toy` and a `FinishedPlay`. Engine B, with no state, having fetched nothing, then saved records under the same two names without system fields.

**Came back.** Both saves were refused, in `sentRecordZoneChanges.failedRecordSaves`, with `CKError.serverRecordChanged` (14). The server's message was "record to insert already exists", under the internal code `CKInternalErrorDomain` 2004. On each error:

- `serverRecord` was A's record, with its change tag, its dates and its encrypted values readable.
- `clientRecord` was B's record as sent.
- `ancestorRecord` was there, but empty: no change tag, no dates, no values.
- The `userInfo` keys were `AncestorRecord`, `CKErrorDescription`, `ClientRecord`, `ContainerID`, `NSDebugDescription`, `NSLocalizedDescription`, `NSUnderlyingError`, `OperationID`, `RequestUUID`, `ServerErrorDescription`, `ServerEtag`, `ServerRecord`, `errorKey`.

`sendChanges()` threw `partialFailure`. Afterwards B's list of pending changes was empty: **the engine does not keep a refused save.** B then saved the toy again on the system fields of the returned `serverRecord`, and that save was accepted.

**Against the design.** This is what section 6 expects ("refused in the same way, with iCloud's record attached") and what rule 4 of section 7 expects for a finished play, so open point 1 is answered. The refusal without a record that a 2019 report describes, for a record that other records point to, did not occur; the app's records point to nothing. Two details for the delegate: the ancestor of such a refusal carries nothing, and a refused save leaves the engine's list, so the app queues again whatever it still wants sent. Section 6 already says so for Keep This One.

### 2. A save with stale system fields

**Did.** A saved the toy; B fetched it; A saved it again on the system fields it got back; B then saved on the system fields of the first version.

**Came back.** Refused with `CKError.serverRecordChanged` (14), "client oplock error updating record", internal code 2004. `serverRecord` was A's second version. `clientRecord` was B's. `ancestorRecord` held the system fields of B's base (its tag and dates) without values.

**Against the design.** As expected: the engine saves so that a stale tag is refused, and so is a save without a tag under a name that exists (point 1). This answers open point 2 by behaviour; the policy's name is still only an Apple engineer's word. Point 15 shows a case where the tag check does not protect the toy.

### 3. What a saved record carries

**Did.** A saved the toy, and the probe looked at the record in `savedRecords`, then at the same record fetched by B.

**Came back.**

- The saved record is **the very `CKRecord` object** that the delegate handed to the engine, now carrying its change tag and its creation and modification dates. Its creator and last modifier are `__defaultOwner__`, and it has no changed keys.
- Its encrypted values read back through `encryptedValues`: `format` 1, and the payload's bytes. `allKeys()` lists `format` and `payload` as well. Reading `payload` as a plain field gives nothing.
- Its system fields archive in about 2.3 KB (2,358 bytes here). A record rebuilt from them has the tag and the dates and no values.
- The record fetched by B has the same tag, and its values read back the same way.
- **Change tags are short hexadecimal counters for the whole zone**: `3`, `4` … `9`, `a`, `b`. The first record saved in a new zone got `3`; two records saved together got `3` and `4`; every later save in the zone, of any record, takes the next number.

**Against the design.** As section 6, step 3 expects: the returned record becomes the base. Two sizes to know: each base is about 2.3 KB, which is more than an untouched toy (264 bytes). The tags are counters per zone in the development environment; whether production's are too is not known. Point 15 shows why it matters.

### 4. An engine's own save coming back as a fetched change

**Did.** A saved the toy, then fetched. Then, eight times, A queued a change to the toy and asked for a send and a fetch together, each round starting the fetch 0.1 s later than the round before (0 to 0.7 s after the send).

**Came back.** A's fetch after its own save delivered its own record, with the tag it had just been given. In the eight rounds the engine ran the send and the fetch side by side: in some rounds the zone's fetch began before the save was confirmed. But **the fetched change never arrived before the confirmation**. In seven rounds the confirmation came first and the change was fetched after it; in one, the fetch was over before the save landed. Two earlier runs, of three and eight rounds, gave the same.

**Against the design.** A device's own save does come back to it, as the design expects (source 17). Section 6 handles that with its first case: the record arriving is the base, with the same tag. That the change can come back *before* its confirmation was not seen in nineteen rounds, and it is not ruled out either. The stamps of choice 12 are there also for an answer that never arrives, which points 17 and 18 show.

### 5. A record deleted, then saved again under the same name

**Did.** A saved the toy, B fetched it, A deleted it, and A saved it again: once on the deleted record's system fields, once without system fields. Then B, still holding the deleted record's system fields, saved too.

**Came back.**

- On the deleted record's system fields: refused with `CKError.unknownItem` (11), "recordChangeTag specified, but record not found" (internal code 2003), with no record attached. The engine dropped the save.
- Without system fields: accepted, as a new record, with a new creation date.
- B's save on the old system fields after the record was made again: `serverRecordChanged`, "client oplock error updating record", with the new record as `serverRecord`.
- B's fetch afterwards delivered the new record and no deletion.
- A deletion queued and then a save queued for the same record left only the save pending, as Apple's documentation says.

**Against the design.** As section 10 expects ("the base is emptied and the toy is sent as a new record"), and as Apple's sample shows (source 52).

### 6. Deleting a record that is already gone

**Did.** A saved a play, B fetched it, A deleted it, and B deleted it as well. B also deleted a record that never existed.

**Came back.** Both deletions were reported in `deletedRecordIDs`, as successful, with no error.

**Against the design.** Section 7, rule 7 removes an entry when iCloud confirms its deletion "or reports that the record is already gone". The engine does not tell the two apart: both are a confirmed deletion. That agrees with the rule, and it needs no error case.

### 7. Saving into a zone that does not exist

**Did.** A, with no state, saved a play into a zone never made. Then it queued the play again with the zone's save queued after it, and in another zone the other way round.

**Came back.** The first save was refused with `CKError.zoneNotFound` (26), "Zone does not exist" (internal code 2036), and the engine dropped it from its list. With the zone queued, in either order, the zone was sent first (`sentDatabaseChanges`), then the engine asked for the batch of records, then the records were sent.

**Against the design.** As sections 9 and 10 expect (source 10). The app queues the save again together with the zone, because the engine does not keep it.

### 8. A fetch from nothing, in a zone where records were deleted

**Did.** A saved three plays and B two. A deleted one of its own plays and one of B's. Then C, a new engine with no state, fetched.

**Came back.** C received the three plays still there, and **both deletions**: the play A had made and deleted, and the play B had made and A had deleted.

**Against the design.** Apple's engineer says a fetch from nothing delivers a deletion when the record was created by the fetching *device* (source 50). Here every engine ran on one Mac, so to CloudKit every record was most likely created by the fetching device, and this agrees with that rule as well as with the developer who saw many deletions. **What a second device would receive is not known from this.** Since its revision, the design removes the entries whose deletions arrive when a device joins (section 8), and accepts that some may not arrive (section 16).

### 9. A zone that one engine deletes

**Did.** A made a zone with a toy, B fetched, and A deleted the zone through its engine. Then B fetched, A fetched, and C, a new engine with no state, fetched.

**Came back.**

- B was told of the zone's deletion with the reason `deleted`, and of no record deletions.
- A, which had deleted it, was told the same on its next fetch.
- **C, new, was told of this zone's deletion, and of every other probe zone deleted earlier, each with the reason `deleted`.** That includes the zones of an earlier run, deleted directly through `CKDatabase` and not through an engine. C's fetch was limited to one zone, but database changes are not limited by zone.
- This held in every run. In point 15, a zone that had been made again was not reported as deleted.
- **How long the reports live.** At 17:41:59 Pacific time a new engine, fetching every zone, was told of 43 deleted probe zones: every probe zone that had existed and been deleted before that fetch. The oldest had been deleted at 17:01:58, 40 minutes earlier. None had expired. This is a lower bound only; how long CloudKit keeps such reports is not known. No zone from before the development environment was emptied that day was reported.

**Against the design. This differs.** Section 9 acts on a zone's deletion as on news. But an engine that starts from nothing is also told of zones deleted at any earlier time, as long as the zone does not exist when it fetches. The probe cannot make a purge, which only the person can do in Settings, nor an encryption reset. *Inferred, not seen:* if a purge is reported the same way, a device that joins after a purge, before any device has saved the zone again, would be told `purged`, and under section 9 it would remove its history and its toy and send nothing again, even if its plays were made after the purge. Whether this can happen depends on order: joining queues the zone's save (section 8), and once the zone exists, no deletion is reported (point 15). In point 11 the engine's own schedule fetched before it sent.

### 10. The account event of a new engine

**Did.** Made engines with no state, with automatic syncing off and on, waited, and looked at their events; then made one from a saved state.

**Came back.**

- A new engine with automatic syncing off delivered `signIn` at its first operation. With it on, it delivered `signIn` as soon as it was made.
- The user record id in it was **the account's own** (33 characters, beginning with an underscore), the same as `CKContainer.userRecordID()`. It was not `__defaultOwner__`.
- An engine made from a saved state delivered no account event.

**Against the design.** As section 8 expects: an engine that starts from nothing reports a sign-in, and the store notes the account from it. Comparing that id with the stored one works, because it is the account's real id. Over all the runs, each of the 89 engines that started from nothing reported the sign-in, and none of the 7 made from a saved state did. That answers open point 14 on this Mac.

### 11. Automatic syncing

**Did.** Looked at the app's push registration and the database's subscriptions at the start, after an engine with automatic syncing off had fetched, and after two engines with it on (A and B) were made. Then A queued the zone and a toy without asking for a send, and the probe waited up to 240 s for B to fetch the toy by itself.

**Came back.**

- **Pushes.** In the run that asked this question before any engine with automatic syncing had been made, the app was not registered for remote notifications at the start, nor after the engine with automatic syncing off had fetched. It was registered 15 s after the engines with automatic syncing were made. (In the final run, question 10 had already made such an engine, and the app was registered from then on.) At that moment CloudKit's log shows `client/notification-listener-register` and `client/push-environment`, with a connection to the system's remote notification service, and the push daemon's log shows a token issued for the app's topic in the development push environment. **The engine registers for pushes by itself when automatic syncing is on.** The app has no code that does, and needs none.
- **Subscription.** Every engine, with automatic syncing on or off, saved and then fetched the database subscription `CKSyncEngineDatabaseSubscription-Private` at its first operation.
- **Sending.** About 0.5 s after A's changes were queued, A's engine fetched, then sent, by itself (reason `scheduled`). The toy was saved 2.6 s after it was queued (2.8 s and 3.4 s in earlier runs).
- **The other engine.** B never fetched A's toy by itself within 240 s and began no fetch of its own in that time. The push daemon received nothing for the app's topic. Fetched by hand afterwards, the toy was there. A's own toy did not come back to A either, because A did not fetch again.

**Against the design.** *Inferred:* CloudKit does not push a change to the device that made it, so a probe on one Mac cannot show a push arriving or the fetch that follows it (section 11, "a push arrives"; open point 6). What it does show: the engine registers for pushes by itself (source 18 listed this as not documented), and it sends queued changes by itself within seconds. The app needs the push entitlement, which it has, and no code of its own.

### 12. Two engines from copies of one saved state

**Did.** A saved a toy and a play, fetched, and queued a third play without sending it, as a device backed up at that moment. A1 and A2 were made from copies of A's saved state, each with a copy of A's records. Both changed the toy on the same base and sent; then each saved a new play, and both fetched.

**Came back.**

- Both copies began with the same pending change: the unsent play.
- A1's toy and the unsent play were accepted.
- A2's toy was refused with `serverRecordChanged` (stale tag) and A1's toy attached; A2's copy of the unsent play was refused with "record to insert already exists" and A1's copy attached.
- Both fetches, from the copied change tokens, ran without error and delivered every record, each engine's own included, and no deletions.

**Against the design.** As section 17 and principle 7 expect: two devices set up from one backup behave like any two devices. For open point 4, the engine went on from a copied state without complaint, minutes after it was saved. A state restored on a real device after a longer time was not tried.

### 13. The field types CloudKit gives encrypted values

**Did.** Every question saved `Toy` and `FinishedPlay` records, with `format` written as an `Int` and `payload` as `Data` through `encryptedValues`, in a development environment that held no such types before. Then `xcrun cktool export-schema` read the development schema.

**Came back.** Both record types, with `format ENCRYPTED INT64` and `payload ENCRYPTED BYTES`, CloudKit's six system fields without indexes, and the permissions `WRITE` to `_creator`, `CREATE` to `_icloud` and `READ` to `_world`. Besides them, only `Users`.

**Against the design.** As sections 5 and 12 expect, and the same as [the schema file](icloud-schema.md), except for the permissions, which the file leaves out by choice.

### 14. A fetch when the app comes to the front

**Did.** With an engine whose automatic syncing was on, the probe hid the app and showed it again, asking it to become active. Then it posted the system's notifications of becoming active (`NSApplication.willBecomeActiveNotification` and `didBecomeActiveNotification`) itself.

**Came back.** The app was behind another app when the question began, and showing it again did not make it active: macOS lets an app become active only when the active app yields. So no real return to the front happened, and no fetch began. **After the posted notifications, the engine began a fetch 0.5 s later**, with the reason `scheduled`. CloudKit's log at that moment reads "received appForegroundNotificationName notification", followed by the activity `engine/fetch-on-foreground`. A newly made engine with automatic syncing also ran a sync of its own at once: a fetch, then a send.

**Against the design.** Open point 7 expected, from names in the CloudKit binary (source 53), that the engine fetches when the app becomes active. The engine does fetch when it hears the system's notification that the app is becoming active. That it hears it on a real return to the front, as it should, was not seen; a person bringing the app forward, with the log open, would close the point. If it holds, the app's own request for a fetch on coming to the front can go, as section 11 and open point 7 foresee.

### 15. A zone deleted and made again under the same name

**Did.** A made a zone with the toy, then a play in it. B and B2 fetched both. A deleted the zone, made it again under the same name, and saved a new toy and another play in it. The play of the first zone was not saved again. Then:

- B, which still held state for the first zone, fetched, and fetched once more;
- B2, which had not fetched since, saved on the system fields of the toy it held from the first zone;
- C, a new engine with no state, fetched.

In a second zone, E's save was repeated with one difference: the new toy was saved twice, so that its tag differed from the one E held.

**Came back.**

- **B was told nothing of the deletion.** Its fetch reported the zone as modified, then the two records now in it: no zone deletion, no record deletion, no error about its change tokens. Its next fetch reported nothing.
- **B still holds the play of the first zone,** which is no longer in iCloud, beside the new toy and the new play.
- C, new, was told the same as B: the zone as modified, and the records in it.
- **The tags started again.** The toy in the first zone and the new toy both had the tag `3`. The two plays both had `4`.
- **B2's save on the first zone's toy was accepted.** It replaced the new toy, which B2 had never seen. A, fetching afterwards, read the toy B2 had written, its encrypted values decrypted; so did C.
- In the second zone, where the new toy had the tag `4` and E's base `3`, the same save was refused with `serverRecordChanged` and the new toy attached.
- Four runs gave the same; the two earliest had no play in the zones.

**Against the design. This differs, and it answers open point 13.** Of the three outcomes that point names, the engine gives the last: nothing at all. A device that held state for the old zone keeps the old zone's records for good, unless the app finds out otherwise, and the devices disagree. In the same case the toy is not protected either. Principle 2 says a device replaces the toy only if it has seen the one that is there, and section 6 rests this on CloudKit's change tag. Across a zone that is deleted and made again, that does not hold:

- a device that missed the deletion is never told of it, once the zone exists again;
- its base can carry the same tag as the new record, because tags are counters that start again with the zone;
- then the first case of section 6, step 5 ("the record this device already holds as its base, with the same change tag") takes the new toy for the old one, and the device's next save replaces a toy it has never seen.

A zone is deleted and made again after a purge or an encryption reset, as soon as a device joins and saves the zone (sections 8 and 9). How likely it is that the tags coincide depends on how many saves each zone saw. Whether production's tags are counters too is not known.

### 16. A save and a deletion queued for one record

**Did.** A saved two plays. Before any send, it queued for one of them a save and then a deletion, and for the other a deletion and then a save. It did the same for a play never sent: a save, then a deletion. After each send, the probe read the record directly from the database.

**Came back.**

- A save and then a deletion of a record that exists left only the deletion pending. The engine sent the deletion, and the record was gone.
- A save and then a deletion of a record never sent left only the deletion pending. The engine sent it and reported it as a deletion, without error; there was never a record.
- A deletion and then a save of a record that exists left only the save pending. The save was accepted, and the record was there.

**Against the design.** For one record, the later of the two replaces the earlier in the engine's list, in both orders, as Apple's documentation says for a deletion followed by a save (source 3). A device that clears its history while the save of a play is still waiting therefore sends only the deletion.

### 17 and 18. A save whose answer the app never stores

**Did.** In one launch (question 17), A saved the toy, then queued a change to it and a new play. Like the app, it kept the engine's state and its records at every state update. It asked for a send, and **ended the process the moment the confirmation arrived**, before storing it or any later state. The saves had landed: the toy now had the tag `4` and the play `5`. In the next launch (question 18), a new engine started from the state kept, with the records kept. Like the app at launch, the probe queued again what was not yet received, then sent and fetched.

**Came back.**

- **The kept state still listed both saves as pending.** It was the state of the last update before the confirmation, while the saves were under way.
- Queuing them again changed nothing; the engine drops duplicates.
- Sent again, the play was refused with "record to insert already exists", with the play that had landed attached.
- The toy, sent again on its old base (tag `3`), was refused with "client oplock error updating record", with the toy that had landed attached: the device's own save.
- The fetch then delivered both records as they had landed.

**Against the design.** As sections 6, 7 and 10 expect for an answer that is lost. The toy comes back as a refusal carrying the device's own save, and its stamp is how the device can tell (section 6, step 5, second case). The play comes back as an "already exists" refusal, which rule 4 of section 7 settles. This is an app ended between the send and storing its answer, not an answer lost on the network. The state at the next start is the same in both cases, but the engine's own handling of `serverResponseLost` was not seen.

### 19. A zone given up for another name

This tests the facts that a correction now weighed by the coordinating session would rest on: a deleted zone's name is never used again, and the devices go on in a zone with the next number.

**Did.** A made zone 1 with a toy. B, B1 and B2 fetched it. A deleted zone 1 and made zone 2, another name, with a toy in it; zone 1 was not made again. Then:

- B, which held state for zone 1, fetched every zone;
- B1, which held state for zone 1, fetched zone 1 only;
- C, a new engine with no state, fetched every zone;
- B2, which held state for zone 1 and had not fetched since, saved into zone 1: first a new record, then the toy on the system fields it held. Then it asked for a send with nothing queued again.

**Came back.**

- **B was told that zone 1 was deleted, with the reason `deleted`, and that zone 2 had changed.** The two reports came in one event, which gives changed and deleted zones as two lists, so there is no order between them. Then the engine fetched zone 2 by itself and delivered its toy. The app had not named zone 2; its fetch covered every zone.
- **B1, fetching zone 1 only, was told the same two zone reports**, but the engine did not fetch zone 2's records. Afterwards its state listed zone 2 among the zones with changes it has not fetched.
- **C, new, was told the same as B**: zone 2 as changed, zone 1 deleted with the reason `deleted`, then zone 2's toy. It was also told of every probe zone deleted earlier that day (see point 9).
- **B2's new record into zone 1 was refused with `zoneNotFound`** (26), "Zone does not exist". **So was its save on the system fields it held**, the same code and message. No record was attached to either, and the engine dropped both saves. The send that followed, with nothing queued again, sent nothing. Zone 1 did not come back into being.
- Neither B nor B1 got an error about its change tokens.
- The probe's own store still held zone 1's toy after these fetches. That is the probe's doing, not CloudKit's: it removes records when they are reported deleted, and a zone's deletion does not report its records one by one.

One run, at 17:42 Pacific time.

**Against the design.** These are facts for the correction being weighed, not a judgment of it. A zone that is deleted and never made again is reported deleted, with its reason, to every engine that knew it and to every new one; a fetch limited to the old zone is still told of the new zone; and saves into the old zone fail with `zoneNotFound` without creating it. Section 9 then applies, since the zone is missing.

### 20. Saving a zone that exists, and one new zone saved by two engines

**Did.** A made a zone with three plays and fetched. B, a new engine, saved the same zone again. The probe read the three plays directly before and after, and A fetched again. Then C and D, two new engines, each queued the save of one new zone and a play in it, and both asked for a send at the same moment.

**Came back.**

- **B's save of the zone that exists was accepted, without error.** The three plays kept their tags and dates. A's next fetch was told nothing.
- **C's and D's zone saves were both accepted,** and both plays were saved, in one zone. The zone's counter went on: C's play got `3` and D's `4`.
- The two sends began together, but D's zone save was confirmed only after C's zone and C's play were saved. CloudKit's client in one process appears to queue its operations (its log speaks of a "container throttle queue"). So this shows that a second save of a zone keeps what the first engine saved in it; it does not show two saves at the same instant from two devices.

Two runs for the first part (in the first, A had not fetched before B's save, so its later fetch proved nothing, and it is set aside); one for the second.

**Against the design.** As section 8 expects: saving a zone that exists changes nothing (source 10).

### 21. A zone made again, seen through a token far ahead of its counter

**Did.** A saved twelve plays in a zone, with the tags `3` to `e`, and B fetched them all. A deleted the zone, made it again under the same name, and saved one play in it (tag `3`). B fetched. A saved twelve more, and B fetched again.

**Came back.**

- **B received the play of the zone made again**, though its token came from a zone whose counter stood at `e`, and then all twelve later plays.
- B was told of no deletion, and still held the twelve plays of the first zone, which iCloud no longer has.

One run, at 17:42 Pacific time.

**Against the design.** A token from the old zone did not make B miss new records. What it does is what point 15 shows: the old zone's records are never reported deleted.

## What the probe could not find out

- **Anything that needs a second device:** whether a push reaches the Mac or wakes an iPhone, and whether the other device then fetches by itself; whether a fetch from nothing on a second device is told of deletions of records it did not create.
- **A purge and an encryption reset.** No interface makes either. The reasons `purged` and `encryptedDataReset` were never seen.
- **The person's side:** the app's switch in Settings, signing out, another account.
- **Production:** whether change tags are counters there too, and anything else about production.
- **An answer lost on the network** (`serverResponseLost`), and a send cut short when the app is suspended. Points 17 and 18 show the same state at the next start, by ending the process instead.
- **A long absence:** expired change tokens, and how long deletions are kept beyond the 40 minutes seen (point 9).
- **A real return to the front.** The probe only posted the notification (point 14).

## The design's open points

| Open point (section 15) | What the probe shows |
|---|---|
| 1. A first save under a name that exists | Answered: refused with `serverRecordChanged`, with iCloud's record attached (point 1). |
| 2. The engine's save policy | Answered by behaviour: a stale tag and a missing tag are both refused (points 1, 2). A save on a base from a deleted zone can pass (point 15). |
| 3. The app's switch in Settings | Not tried. |
| 4. A state from a backup | In part: two engines from a copied state went on normally (point 12). |
| 5. A device away for a long time | In part: on one Mac, a fetch from nothing delivered deletions (point 8). New engines are told of old zone deletions, at least 40 minutes old (point 9). Expiry was not reached. |
| 6. Pushes | In part: the engine registers for pushes by itself when automatic syncing is on (point 11). Delivery needs a second device. |
| 7. Sending on leaving the front, fetching on coming to it | In part: the engine fetches by itself when it hears the app become active (point 14). A real return to the front, and sending on leaving it, were not tried. |
| 13. A zone created again before a device fetched | **Answered: nothing at all.** The device is told of no deletion and no token problem, and keeps the old zone's records (points 15, 21). Its base can also pass the tag check. A zone given up for another name, by contrast, is reported deleted with its reason (point 19). |
| 14. The sign-in at a first launch | Answered on this Mac: every engine that started from nothing reported a sign-in with the account's own id, at its first operation or at once (point 10). |

Not in section 15, but found here for the delegate:

- A refused save, a save into a missing zone, and a save on a record that is gone all leave the engine's list (points 1, 5, 7). The app queues again what it still wants sent, as the design already does in each case.
- A refusal's ancestor record is empty for a first save, and holds only system fields for a stale one (points 1, 2).
- Deleting a record that is already gone is reported as a plain deletion (point 6).
- For one record, a save and a deletion queued before sending: the later one is the one sent (point 16).
- The engine's saved state lists a save that is under way as pending, so a save whose answer is never stored is sent again after the next start (points 17, 18).
