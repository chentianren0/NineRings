# Nine Rings: the iCloud design

*As of 20 November 2026.*

This document describes how the Nine Rings app keeps a person's play on all of their devices through iCloud. It can be read without knowing anything else about the app.

## How to read this document

Three kinds of statement appear here, and they are kept apart.

- **Facts about Apple's platform** carry a number in square brackets, such as [9]. The number leads to a source in section 18. Each source says what kind it is: Apple's documentation, Apple outside its documentation (its engineers on the developer forums, its sample code, its conference talks), reports from other developers, tests of this project's own in CloudKit, or "not documented". The tests are called *the probe* below [54]. The facts were gathered on 18 and 20 November 2026, from the documentation that comes with Xcode 27.3 and from Apple's websites, and the tests ran on 19 and 20 November 2026. Several of these interfaces are recent or were revised in 2026, so a reader's memory of them may be older than the sources.
- **Choices of this design** are written as choices, with their reasons. Section 16 collects them, each with what was set aside.
- **Open points** are in section 15: what Apple does not document, and what has to be verified in the running app before release.

## 1. The design in brief

- Each device keeps the person's data in **a store of its own**. The app works from that store and needs no network.
- Between the devices runs **`CKSyncEngine`**, Apple's sync engine for CloudKit, on the person's private database. The app has no server.
- **The toy**, which is the puzzle as the person left it, is one record in iCloud. A device replaces it only if it has seen the one that is there, and CloudKit checks this. When two devices have each changed the toy, the person chooses which one to keep.
- **Each finished play** is one record under its own id, written once. The device keeps what CloudKit last said of each play, so CloudKit tells it whether a play it knew is still there. The history is the set of these records.
- **One rule decides what is sent.** The store marks what iCloud has not yet received, and one gate lets it go. A device fetches before it sends, in every run and after every change of zone.
- **The records live in one zone, whose name carries a number and a random id.** No name is used twice. When the zone has been deleted, the devices go on in a zone with a higher number.
- **Everything the app stores in iCloud is in encrypted fields.** The app has no encryption code of its own.
- **Data leaves a device only through an act of the person:** clearing the history, deleting the app's data from iCloud in Settings, or another account signing in on the device.
- **No decision depends on a device's clock or on a device's identity.**
- The app has **no iCloud switch of its own**. The system's switch in Settings is the control.

## 2. The app and its data

### The app

Nine Rings shows the nine linked rings puzzle as a 3D toy and lets a person play it. The puzzle is a wire sword with nine rings on it, each held by a rod that links it to the next. The aim is to take every ring off.

The person taps a ring to take it off the sword or to put it back on. The puzzle's rule decides which rings can move: ring 1 always can, and any other ring can only when the ring before it is on and all the rings before that one are off. The 512 arrangements lie on one path, and the shortest way from every ring on to every ring off is 341 moves. The app can also take a move back, play the shortest way by itself, put every ring back on, let the person set the rings by hand, and teach the rule in a lesson.

| Word | Meaning |
|---|---|
| the toy | The puzzle on screen, with everything needed to bring it back as it was. |
| a move | One ring going on or coming off. |
| at rest | No move is playing and none is waiting. |
| untouched | Every ring on, no move made and none under way, no progress toward the achievements, and a play that has counted nothing. It is the toy a first launch has. A toy whose rings were all put back on, but which carries progress, is not untouched. |
| a play | The way from every ring on toward every ring off. A play begins whenever every ring is on. It is finished when the person's own move takes the last ring off. |
| a finished play | The record of one finished play: when it was, how many moves and undos it took, and how long. |
| the history | Every finished play, newest first. |
| the lesson | Twelve steps that explain the puzzle's rule with the first six moves of the shortest way. Its last step gives the person their own toy back. |
| the congratulation | The card that shows when the person's own move takes the last ring off, the move that finishes the play. |

The app runs on iPhone and iPad with iOS 27.2 or later, and on the Mac, as a native app, with macOS 27.2 or later. It has one window. It keeps its data with SwiftData.

### The two things that go to the other devices

| | The toy | A finished play |
|---|---|---|
| How many | One for the person | One for each finished play |
| What it holds | The arrangement the moves start from, the moves made since (at most 2,000), a move stopped part way, the rings still waiting, the play in progress with its id and its counts, and the progress toward two achievements | The play's id, when it began and when it was finished, the number of moves and undos, the moves the app played for the person, the time spent, the kind of device, the arrangements the play began from and ended in, and the app's version |
| Size | Its payload, with twenty stamps: 1,131 bytes when untouched, 1,827 bytes in the middle of a play, about 6.3 KB at most | Its payload: 263 bytes |
| When it changes | At almost every rest, which is about once per move at a person's pace | Never. It is written once. |
| When it goes away | Never. Putting every ring back on starts it afresh. | Only when the person clears the history, which removes them all |

Two details matter later.

- **Time alone changes the toy's bytes.** The play in progress counts the seconds the person spends in front of it. The design treats two toys that differ only in that count as *the same toy*.
- **A play has an id from the moment it begins**, a random UUID. A toy carries its play's id with it.

A full play takes at least four and a half minutes at the app's fastest speed. A large history is therefore some hundreds or a few thousands of finished plays, about a megabyte at most.

### What stays on each device

Settings stay on each device. Achievements are kept by Game Center for the signed-in player, and the app's note of what it has reported to Game Center stays on each device too.

### Before this design

No version of the app was released before this design. Only internal builds existed, and they have no users. Those builds synced in another way, and while their own iCloud switch was on, they kept the finished plays in a second store on the device. The version built on this design does not read that store, and it neither reads nor deletes anything those builds put into iCloud. Nothing of those builds is in CloudKit's production environment, and the development environment was reset. So no older version shares an iCloud with this design, and this document describes no such case.

## 3. What the design is for

1. **Continuity.** The person leaves one device, picks up another, and finds the toy as they left it.
2. **One history.** Every finished play appears on every device, once. A play that was finished on two devices appears once as well (section 7).
3. **Nothing replaced without a choice.** When two devices have each been played on separately, neither play is dropped unless the person says so.
4. **The device first.** The app works fully without iCloud. When iCloud goes away on a device, the data stays there.
5. **Private.** The data sits in the person's own iCloud, protected by Apple's encryption, where the developer cannot read it.
6. **Small.** Where Apple provides a mechanism, the design prefers it to code of the app's own for the same job.

The design is not for sharing between people, for showing one device's moves on another as they happen, for syncing settings, for reading the data on the web, for devices on older systems, or for carrying over data from the internal builds before it (section 2).

## 4. The principles

Every rule in the later sections follows from these eight.

1. **The device's store is the person's copy, and it says for itself what iCloud has not yet received.** The app reads and writes only this store. The rules mark in the store, next to the data, what still has to go to iCloud, and one gate decides what is queued in the engine and handed over (section 11). The engine's list of pending changes can therefore always be rebuilt from the store.
2. **The toy is one record, and a device replaces it only if it has seen the one that is there.** CloudKit enforces this with the record's change tag [9]. A device whose own toy is unchanged takes up a newer one. When both have changed, the person chooses.
3. **A finished play is written once under its own id, and the device keeps what CloudKit last said of it.** Records whose content never changes cannot conflict. Each play keeps CloudKit's system fields of its record, so when the device offers the play again, CloudKit says whether the record it knew is still there (section 7). The history is the set of the records, and clearing it removes the records the device knows.
4. **A device knows iCloud only through its engine state and what its store kept of each record.** When the engine starts from nothing, the device offers iCloud everything it holds, each record with what it knew of it, and takes everything iCloud holds. Joining for the first time, returning after a sign-out, recovering from a lost state and going on in another zone are the same act: a join (section 8).
5. **Data leaves a device only by an act of the person.** There are three such acts: clearing the history, deleting the app's data from iCloud in Settings, and another account signing in on the device.
6. **Everything in iCloud is in encrypted fields.**
7. **No decision uses a clock or a device's identity.** Which toy is newer is CloudKit's answer, not a comparison of times. No device has a name or a number in the data. Two devices set up from one backup therefore behave like any two devices.
8. **A zone's name is unique by how it is made.** The records live in one zone, whose name carries a number and a random id. The number orders the zones, the random id makes every name new, and no device has to remember the names that were used. When a zone has been deleted, the devices go on in a zone with a higher number. CloudKit keeps change tags, tokens and the report of a deletion under the zone's name [54]. Because no name is used twice, every device learns what became of the zone it knew, as long as iCloud still delivers the report (open point 13), and a change tag is only ever compared within the zone it came from.

## 5. The parts

### On each device: the store

A SwiftData store whose own syncing through CloudKit is switched off (`cloudKitDatabase: .none`). SwiftData would otherwise mirror the store by itself as soon as the app has the CloudKit entitlement [22].

| Kept in the store | What it is for |
|---|---|
| The toy | The person's toy on this device. |
| Toy changed | A mark: the toy has to be sent. It is set when the person changes the toy (section 6, step 1), when the person keeps their own toy over another device's, when the device leaves a zone while its toy is not untouched (section 9), and when the person chooses another device's toy that iCloud no longer has (section 6, step 6). Section 6 says when it is cleared. |
| Toy base | CloudKit's system fields of the Toy record as this device last saw it, with the stamps that record carried. The system fields carry the change tag and the zone the record belongs to, so the base keeps its zone. A base can have stamps and no system fields: it is then a toy whose zone is gone, which the person chose to keep (section 6, step 6). Empty when the device has seen no Toy record. |
| Last send | The stamp under which the toy was last handed to iCloud, and whether the toy has changed since then. A change by the person sets "changed since then"; time spent does not. |
| Own stamps | The stamps of this device's last twenty sends of the toy (section 6). |
| Held toy | Another device's toy, with its system fields and its stamps, and one of three kinds: *to take up* at a calm moment, *offered* to the person, or *unreadable* by this version of the app (section 14). The kind is saved with it. A held toy whose zone is gone has no system fields. Usually empty. |
| The finished plays | Each with CloudKit's system fields of its record, from the answer that accepted it or from its arrival, or none. Each with a state: *unsent* (it has never left this device), *sent* (it was handed to iCloud, or was once known there, and iCloud has not confirmed it since), *in iCloud*, or *cleared* (the history was cleared, on this device or on another, and iCloud has not yet confirmed this device's deletion of the record). |
| Engine state | The engine's saved state, as the engine hands it over [3]. |
| Zone note | The name of the zone this device uses or last used, with what the device knows of it: *not yet confirmed* (the device created it, and iCloud has not confirmed it), *existing*, or *deleted*. Empty before the first join and after a sign-out. |
| Highest number | The highest zone number this device has heard of. |
| Account | The id of the iCloud account this data belongs to. Empty before the first time. |

Everything in this table except the toy and the finished plays is called the *sync notes* below. All of it is in the one store, so it is saved together and comes back together from a device backup.

### On each device: the notes of one run

A *run* lasts from the launch of the app's process to its end. Being suspended does not end it. The rules also keep a few notes that hold for one run only. They are not saved, and every launch starts without them.

- When the device began to use its zone in this run, and whether a fetch has finished since then (section 11, condition 3). After a start from nothing, whether the account has been named yet (section 8).
- When each play that is *sent* was last handed over (section 11, condition 5).
- Whether section 6, step 4 has stopped the toy.
- Whether a save was refused because the iCloud storage is full, since the launch or the last return to the front (section 10).
- When the device came to use no zone, and when the creation of a zone not yet confirmed was queued (section 9).
- Whether the device has given up a zone as missing, and whether it has stopped sending after that (section 9).

No note about a join that waits for its fetch is saved, because every launch waits for a fetch anyway (section 11).

### Between the devices: the engine

One `CKSyncEngine` for the private database of the app's iCloud container, created at every launch, with automatic syncing on, and with fetches that are not limited to some zones. The engine does the scheduling, the pushes, the change tokens, the retries and the watching of the account [1][2][3][4]. The app writes the engine's delegate. The delegate hands over records when the engine sends, stores what the engine fetched, and answers the events and errors described in sections 6 to 11.

Apple's own advice names the engine for an app that brings its own storage [19].

### In iCloud: one zone, two kinds of record

| Record type | How many | Record name | Fields |
|---|---|---|---|
| `Toy` | One | `toy` | `format` (encrypted integer) and `payload` (encrypted bytes) |
| `FinishedPlay` | One for each finished play | The play's id | `format` (encrypted integer) and `payload` (encrypted bytes) |

Both live in one custom zone of the private database. The zone's name is `NineRings-`, the zone's number, a hyphen and a random id, and no name is used twice (principle 8, section 9). `payload` is JSON, and `format` says which version of that JSON it is.

- **The toy's payload** holds the toy, the time and the kind of device of its last change, the app's version, and its *stamps*. A stamp is a random id for one version of the record. The payload carries the stamp of this version, preceded by the stamps of the versions before it, twenty at most.
- **A finished play's payload** holds the values listed in section 2.

The sizes are far below CloudKit's limits [12].

## 6. The toy between devices

### What CloudKit does

CloudKit gives every stored record a change tag, which changes with each save. A device sends a save together with the tag it last saw. If the record in iCloud has changed since then, CloudKit refuses the save and returns the record it has [9].

A device that has never seen the record sends no tag. Apple's documentation says that a new record under a name that exists is refused under CloudKit's default save policy, but it names neither the policy the engine uses nor what the refusal carries [9]. An Apple engineer has said that the engine saves with the policy that refuses a save when the server's record has changed, and a developer reports that a first save under a name that exists is refused in the same way, with iCloud's record attached [49]. The probe saw iCloud's record attached to every such refusal [54] (open points 1 and 2).

A change tag holds within one zone. Tags are counters for each zone, and they start again when a zone is made again under its name, so a tag from the old zone can equal a tag in the new one [54]. No zone's name is used twice (principle 8). A base from another zone is emptied when the device leaves that zone (section 9), before any record of the zone it joins is applied (section 8).

### What a device does

1. **The person changes the toy.** This is any change of the toy on this device other than time spent and other than taking a toy up, also a move the app plays for the person. The store marks the toy as changed, and notes that it has changed since its last send. A change in time spent alone does neither. When a move ends, the change is recorded before the moment is judged calm, so the last case of step 5 applies and the person's move is never replaced.
2. **The gate lets the toy go** (section 11). The record is built when the engine asks for it, from the toy as it then is, the base's system fields, and the stamps: the base's stamps, followed by this version's own. A base without system fields gives a record without them, which iCloud takes as a new record. A toy that has not changed since it was last handed over keeps its stamp, so sending it again uses no new one. The stamp is saved in the store before the record is handed over. If the gate does not let the toy through by then, for example because a toy is now held, no record is built.
3. **iCloud accepts the save.** The returned record becomes the base. If the toy has not changed since it was handed over, the mark is cleared. An answer can arrive late, when a later version is already the base or is held. The returned record is then an earlier version, as case 2 of step 5 describes, and the base stays as it is.
4. **iCloud refuses the save,** because the record there is not the one this device saw. The device treats the record that came back as an arriving toy. Should a refusal ever come without the record [49], the device asks the engine to fetch, and the record arrives that way. If a fetch that began after the refusal finishes without bringing a toy either, the gate stops the toy for the rest of the run. The toy stays marked, and it goes out again at the next launch or when a toy arrives, so that a device cannot send, be refused and fetch in a loop. The probe saw the record attached to every such refusal [54], so this guards a case that was not seen.
5. **A toy arrives,** through a fetch or with a refusal. Only a toy of the zone the device uses counts; a toy of another zone is ignored (section 9). The first of these cases that fits is the one that applies.
   - *Case 1. It is the record this device already holds as its base:* in the same zone, with the same change tag. Nothing is new, and nothing happens. A fetch from nothing delivers the record again in this way.
   - *Before case 2: this version cannot read it,* because its format is higher than this version knows, its JSON is broken, or its moves break the puzzle's rule. It is held as unreadable (section 14). Its stamps are not read.
   - *Case 2. It is an earlier version than one this device already holds.* Its own stamp is among the earlier stamps of the base, or of a held toy that this version can read. Nothing happens. Answers and records can arrive out of order, and the base never goes back.
   - *Case 3. Its own stamp is one of this device's own stamps.* It is this device's own send coming back, and it becomes the base. If it is the same toy as the one here, the mark is cleared. Otherwise the mark stays, and the toy goes out again.
   - *Case 4. It is the same toy as the one here.* It becomes the base, and the mark is cleared.
   - *Case 5. The toy here is not marked as changed.* The device **takes the arriving toy up**: it replaces the toy here at the next calm moment. At that moment it becomes the base, the mark is cleared, and the note of the last send is emptied, because the toy here has then never been handed over. Until then the base stays as it was. If the person changes the toy before that moment comes, the last case applies.
   - *Case 6. The toy here is marked as changed, but it has not changed since it was handed over, and its stamp is among the arriving toy's earlier stamps.* This device's save reached iCloud, although its answer did not come back, and whoever wrote the arriving toy had that save before them. The device takes the arriving toy up, as in case 5, and at that moment the mark is cleared and the note of the last send is emptied.
   - *Case 7. Otherwise.* Both devices have changed the toy. The device **holds** the arriving toy and shows the offer. The base stays as it was.
6. **The person answers the offer.**
   - *Play That One.* The held toy replaces the toy here and becomes the base. The mark is cleared, and the note of the last send is emptied. Nothing is sent. If the held toy has no system fields, because its zone is gone, iCloud does not have it, so the toy is marked as changed instead.
   - *Keep This One.* The held toy becomes the base, so the device has now seen it, and the toy here is marked as changed. The gate lets it go at once. The other device takes it up when it arrives there. If the held toy has no system fields, its stamps become the base without system fields, and the toy here goes out as a new record.

A *calm moment* is one in which the toy is at rest (section 2), the person is not dragging a move, and no lesson, hand-setting of rings or congratulation is open. While the app plays the shortest way by itself, no moment is calm.

While a toy is held, the device sends no toy (section 11, condition 4), at launch as at any other time. The person can go on playing, and their toy stays on the device until they answer. Whenever a toy arrives and is not ignored by case 1 or case 2, a toy that was held is no longer held. The arriving toy's own case then decides: it becomes the base, or it is held in the other's place, to be taken up at a calm moment, for the offer, or as a toy this version cannot read. At each launch, a held unreadable toy that this version can now read is handled as an arriving toy.

### Why this keeps goal 3

The toy in iCloud is only ever replaced by a device that has seen it. That device either had nothing of its own to lose and took it up, or showed it to the person, who chose. A play therefore disappears from a device in two ways only: the person went on from that same toy on another device, or the person chose the other play.

The stamps serve the cases that the change tag alone cannot settle. A device's own save can come back to it before the answer to that save, or the answer can be lost. The record's own stamp then shows the device that the toy is its own. And when another device has gone on from such a save, the earlier stamps show that the arriving toy was written with this device's toy in view: its writer either went on from it, or was shown it and chose their own.

### Three walks through it

**From the iPhone to the iPad.** The person plays on the iPhone and puts it down. As the app leaves the front, the iPhone sends its toy. iCloud accepts it, because the iPhone had seen the record that was there. The person opens the iPad. The iPad fetches as it comes to the front, and a toy arrives that is not the one it last saw. The iPad's own toy is not marked as changed, so the iPad takes the arriving toy up. The person goes on where they stopped.

**Two devices played apart.** On a flight the person plays on the iPad, offline. At home, before the iPad has synced, they play on the iPhone, and the iPhone sends its toy. When the iPad comes online, it meets the iPhone's toy: a fetch brings it, or iCloud refuses the iPad's save, because the record is no longer the one the iPad saw, and returns it. The iPad holds it and shows "Another device has a different play." If the person taps Keep This One, the iPad sends its toy again, this time with the tag of the record it was shown, and the iPhone takes it up. If they tap Play That One, the iPad shows the iPhone's play and sends nothing.

**A new device.** The app starts on a new Mac with an untouched toy, which is not marked as changed. The engine starts from nothing. Once the account is known, the Mac joins: it fetches everything, the toy in iCloud arrives and is taken up, and the finished plays fill the history. Had the person made a few moves on the Mac before the toy came in, the Mac's toy would be marked as changed, and they would be asked.

## 7. The history between devices

1. **A play is finished.** The store adds it as *unsent*, with no system fields, and the gate lets its record go (section 11). The record's name is the play's id. A play is recorded once on a device: finishing under an id the store already holds changes nothing.
2. **The record is handed to iCloud.** When the engine asks for the record and the gate lets it through, the entry becomes *sent*. This is saved in the store before the record is handed over. The record is built with the play's system fields when it has them, and as a new record otherwise. When the entry is gone or *cleared*, the store no longer wants the record sent: nothing is handed over, and the save is withdrawn. This rule, and the rule below for a play that is *sent*, rest on the engine asking for the record before every attempt to send it (open point 18).
3. **iCloud accepts the record.** The returned record's system fields are kept, and the play becomes *in iCloud*. An entry that is *cleared* stays cleared, and its deletion stays marked. If the entry is no longer here, the play was cleared while the save was on its way, on this device or on another: in the zone the device uses, an entry can be gone for no other reason. The entry then comes back as *cleared*, so that its deletion goes out and the clearing stands. An answer from another zone is ignored (section 9). That covers a purge, after which the device no longer uses the zone, and another account, whose zones have other names.
4. **iCloud refuses the record.** It does so for one of two reasons.
   - *A record of that name exists,* and it is not the one this device last saw, or the device saw none. Either the same play was also finished on another device, or this device is offering what iCloud already has. The record in iCloud stands. Its content and its system fields replace the entry here, which becomes *in iCloud*. Whichever arrived first is kept. An entry that is *cleared* stays cleared, and an entry that is no longer here comes back as *cleared*, as in rule 3. Should the refusal come without the record [49], the entry becomes *in iCloud* with the content and the system fields it has, and the device asks the engine to fetch, which brings the record.
   - *iCloud does not know the record.* Only a play sent with its system fields can be refused in this way [52][54]. Its record was deleted in iCloud since this device knew it, and in the zone the device uses only a clearing deletes a play. The entry is removed, as when its deletion arrives (rule 6).
5. **A finished play arrives.** It is added, or replaces the entry of the same id, as *in iCloud*, with its system fields. An entry that is *cleared* stays cleared.
6. **A deletion arrives.** The entry is removed. An entry that is *unsent* stays, because iCloud never had it. If the entry was *cleared*, its own deletion is withdrawn.
7. **The person clears the history.** The clearing reaches every entry, also the plays that are counted and not shown (section 14). Entries that are *unsent* are removed at once. All other entries become *cleared*: they vanish from the screen, and their deletions are marked. In both cases a save still queued for the play is withdrawn. When iCloud confirms a deletion, or reports that the record is already gone, the entry is removed for good.

The history on screen is every entry that is not *cleared*, newest first. A play this version of the app cannot read is kept as it is, counted and not shown (section 14).

The state *sent* exists for a save whose answer never came back. iCloud may have such a play, and another device may already show it. Clearing therefore deletes it too, and a deletion that arrives for it removes it.

A play that is *sent* goes out again only after a fetch that began after it was last handed over has finished (section 11, condition 5). This holds at a launch, where the engine may ask from its saved state before the first fetch, and in the middle of a run, after an answer was lost. The reason is a save that lands while its answer is lost: another device can clear the play in the meantime, and the play, sent again, would make the record again and undo the clearing. The fetch brings that deletion first, and the deletion removes the entry. The system fields close most of what is left. A play that iCloud has confirmed to this device goes out with its system fields, so if another device cleared it since, CloudKit refuses the save as unknown, and rule 4 removes the entry. A play sent for the first time has no system fields, and if its answer is lost it still has none. For such a play, a clearing made on another device after the fetch began, and before the second save lands, is undone (section 16).

Clearing removes what this device knew was in iCloud, or might be there. A play that another device finishes afterwards is a new record and stays. So does a play that another device had finished, but not yet sent, when the clearing happened.

## 8. Joining, leaving and returning

### At every launch

1. The app opens the store and shows the toy from it. It never waits for iCloud.
2. It creates the engine, with the saved state or with none. If the store notes a zone that is not yet confirmed, the app withdraws any save of that zone that came back with the saved state, before the engine sends (section 9).
3. It asks the engine to fetch. Nothing is queued until a fetch that began in this run has finished (section 11, condition 3). Then the gate queues whatever the store marks, so a crash between a change and its sending loses nothing. A held toy that this version could not read, and now can, is handled as an arriving toy (section 6).
4. If the engine started from nothing, the device joins once the account is known, as described next.

### The account first

After a start from nothing, the app applies no fetched change and queues nothing until the account is known. The account becomes known through the engine's report of a sign-in [4]. If fetched changes arrive, or a fetch ends, before such a report, the app asks CloudKit for the account's id before it applies anything. The engine delivers its events one at a time, and it delivers the next only when the delegate has handled the current one [11], so the changes wait for the answer. If the question fails, it is handled as a failed write (section 10): nothing is applied, the engine's state is not saved for the rest of this run, so the same changes come again, and that fetch does not count. What the store holds may belong to another account, and Apple does not document that an engine which starts from nothing clears what was queued before it named the account [18]. Outside a start from nothing, the store's note of the account stands, and a join asks nothing.

### Joining

A device joins a zone in four cases:

- its engine started from nothing: on its first launch with iCloud, after the account signed in (the engine has then reset its own state [4]), and after the saved state was lost or had to be discarded;
- a fetch names an existing zone higher than the one it uses (section 9);
- it uses no zone, and a fetch names an existing one (section 9);
- iCloud confirms a zone that the device created (section 9).

After a start from nothing, the device joins the highest existing zone that its fetch names, whatever its zone note says. In the probe, a fetch from nothing named the zones that existed [54]. If it names none, the zone in the device's note, if there is one, no longer exists: the note marks it *deleted*, and the device keeps its data. The device then creates a zone, by the rules of section 9, and joins it once iCloud has confirmed it.

A join is, in this order:

1. The zone is noted as the one in use, as *existing*.
2. The device leaves every other zone: whatever it holds of another zone is emptied, as "Leaving a zone" in section 9 says. This happens before any record of the joined zone is applied.
3. If this is the first join since the engine started from nothing, the account is noted (below), and every finished play that is *in iCloud* goes back to *sent*, with its system fields. Entries that are *cleared* stay cleared.
4. The device asks the engine to fetch. Plays that arrive become *in iCloud*, and a *cleared* entry stays cleared (section 7, rule 5). Deletions that arrive remove their entries (rule 6). When a fetch that began after step 1 has finished, the gate opens (section 11). Then what is *unsent* or *sent* goes out, the plays that are *sent* with their system fields, what is *cleared* goes out as deletions, and the toy goes out if it is marked as changed and no toy is held.

Until that fetch has finished, nothing is queued, so that plays the join set back to *sent* do not go out before the deletions iCloud still delivers have removed them. For each play that is still *sent* afterwards, CloudKit answers: the record is still there (rule 3), it is another than the one this device knew (rule 4), or iCloud does not know it, and the entry is removed (rule 4).

Joining gives a union: afterwards iCloud and the device both have every play that either of them had. There are three exceptions. A play whose deletion iCloud still delivers to the joining device is removed. So is a play that this device knew in the zone it joins and that iCloud no longer has. And the joining device's own *cleared* entries are deleted in iCloud.

### The account

The engine reports what happened to the account [4]. The store's note of the account says whom the data belongs to, and it decides what the device does. The note is written at the first join after a start from nothing, from the account that the engine or CloudKit named.

| The engine reports | The store's account is | The device |
|---|---|---|
| A sign-in, or a switch of account | empty | notes the account and joins. Whatever was made on the device without iCloud goes into the account. |
| A sign-in, or a switch of account | the same account | joins. |
| A sign-in, or a switch of account | another account | puts the toy back to its untouched start, removes the history and the sync notes, notes the new account, and joins with nothing. |
| A sign-out | any | keeps everything and works from the store alone. If the note is empty, it notes the account that signed out. Its zone note is emptied, so that it uses no zone, and the highest number it has heard of stays. |

Several changes of account made while the app was not running arrive as one report, from the engine's last known account to the current one [4]. With no account, with iCloud turned off for the app in Settings, or under a restriction, the engine stays dormant [4] and the app works from its store. Apple does not document whether turning off the app's switch is reported as a sign-out (open point 3). The table covers both cases.

Apple's guidance for the engine is to delete the previous account's data on a sign-out as well [5]. Apple's pages for people say something else: with the app's switch off, the app's data exists only on the device [39], and a person who signs out can keep most data on the device [43]. This design departs from the guidance for developers on purpose. It keeps the data, for goal 4, and removes it when another account arrives, so that one person's plays never go into another person's iCloud.

## 9. The zone, and when iCloud's copy is deleted

### The zone's name

A zone's name is `NineRings-`, the zone's number, a hyphen and a random id, for example `NineRings-2-6F9619FF-8B86-4011-B42D-00CF4FC964FF`. The number is written in decimal, from 1, without leading zeros. The random id is a random UUID, in the upper-case form that Swift's `UUID` gives. Only names of exactly this form count as zones of this design, and every other zone is ignored.

Zones are ordered by their number, and zones with the same number by their random id, compared as text. *Higher* and *highest* in this document mean this order.

The zone note (section 5) holds one zone's name, marked *not yet confirmed*, *existing* or *deleted*. A device *has a zone note* when the note is not empty. It *uses a zone* when the note holds a zone that is not marked *deleted*. It *knows its zone to exist* when the note marks it *existing*.

### The zone in use

- **Hearing of zones.** A report from the engine can name zones that exist and zones that were deleted, in two lists with no order between them [54]. From each report the device notes the highest number named. It handles the deleted zones first, then the existing ones.
- **The zone in use** is the existing zone that is highest. A device that uses a zone and hears of a higher existing zone joins that one and brings everything it holds (section 8). A device that uses no zone joins the highest existing zone that a fetch names, whatever its number. A lower zone that was named in an earlier fetch is not looked for.
- **Other zones.** Answers and records of a zone other than the one the device uses are ignored. A device that uses no zone ignores them all. The zones of two accounts have different names, so an answer or a record from the previous account's zone is ignored in the same way.
- **Two zones with one number.** Two devices that create a zone at the same time make two zones with the same number. Each device hears of the other's zone, and the one in the lower zone joins the higher one and brings everything it holds. The lower zone is left behind.
- **Creating a zone.** A device creates a zone when it has something to send, it uses no zone, and a fetch has finished without naming any existing zone. That fetch must have begun after the device came to use no zone, or after the launch if that was in an earlier run. *Something to send* is a play that is *unsent* or *sent*, a *cleared* entry, or a toy that is marked as changed while none is held. The new name takes the number after the highest the device has heard of, and a new random id. The zone note then holds the new name, as *not yet confirmed*, and its number is the highest number. Only the zone's save is queued, and the app asks the engine to send it at once: the gate holds everything else back until the zone exists (section 11). Saving a zone that exists changes nothing [54]. A device that has stopped sending in this run creates no zone (below).
- **A creation is one attempt.** A zone's own save that reaches iCloud after the zone was deleted makes the zone again under its name, and from then on engines are not told that it was deleted [54]. So a zone's save never waits in the engine. When the attempt to send it ends without iCloud's confirmation, for whatever reason, the app withdraws the zone's save from the engine. That covers an error the engine would try again by itself [8], a lost answer, a full storage, and a send that did not reach iCloud. At a launch, if the store notes a zone that is not yet confirmed, the app withdraws any save of that zone that came back with the engine's saved state, before the engine sends (open point 20). The device never queues the same name a second time.
- **A zone not yet confirmed.** When iCloud confirms the creation, the zone is noted as *existing*, and the device joins it (section 8). After an attempt without confirmation, the zone stays noted as *not yet confirmed*, and the app asks the engine to fetch. When a fetch that began after the creation was queued has finished, the first of these that fits applies:
  - it named the zone as existing: the zone is confirmed, and the device joins it;
  - it named a deletion that counts: the rule for it applies (below);
  - it named a higher existing zone: the device joins that one;
  - it named none of these: the device gives the zone up. The zone note marks it *deleted*, the device uses no zone, and the rule for creating applies again, with a new name. A full storage holds that creation back as section 10 says.

  This holds after any fetch that finishes, not only at launch. Whether a fetch names a zone that the device's own engine created is not documented (open point 17). If it does not, a creation whose answer was lost is given up, and the zone, if it was made, is left behind.
- **Leaving a zone.** A device leaves a zone when it joins another (section 8) and when it keeps its data after losing its zone (below). Leaving is one act, and afterwards the store holds nothing that belongs to that zone:
  1. The app withdraws from the engine every save and deletion still queued for that zone. The engine keeps saves queued for a zone after it has reported the zone as deleted, and if it sends them, they are refused and dropped [54].
  2. The toy's base and the system fields of a held toy are emptied, if they belong to that zone. The toy is marked as changed unless it is untouched.
  3. The system fields of every finished play that belong to that zone are emptied, and every play that is *in iCloud* goes back to *sent*.

  What the device holds then goes into the zone it uses next as new records.

### When a zone is deleted

The engine reports the deletion of a zone together with a reason [6]. It tells every engine that held state for the zone, and also an engine that starts from nothing, of every zone that was deleted and whose name is not in use again [54]. Since no name is used twice, that is every deleted zone, for as long as iCloud keeps the report (open point 13).

A deletion counts for a device if the deleted zone is higher than the zone in its zone note, or is that zone while the note does not yet mark it *deleted*. A device with no zone note counts no deletion. Handling a deletion twice therefore changes nothing the second time. When a deletion counts, the reason decides, as the table says, and afterwards the zone note holds the deleted zone, marked *deleted*. If several deletions count in one report, the highest of them becomes the note's zone, and if one of them is a purge or has the reason *Deleted*, the device removes its data as for a purge. An engine that starts from nothing hears of old deletions too. A device that has never joined, or that returns after a sign-out, has no zone note and takes none of them for its own. A device that was asleep has its zone in its note, and does.

In every case the app withdraws from the engine what is still queued for the deleted zone [54].

| Reason | What it means | The device |
|---|---|---|
| Purged | The person deleted the app's data from iCloud in Settings. Apple tells them it is then removed from every device that syncs [42]. | removes the history, puts the toy back to its untouched start, and empties the toy's notes: the mark of a changed toy, the base, the note of the last send, its own stamps and any held toy. The account note, the engine's state and the highest number stay. What was removed is never sent again [7]. Afterwards the device joins the next zone when another device has made it, or creates it when the person plays again. |
| Encrypted data reset | The person had to reset their encrypted data to recover their account. The zone could no longer be decrypted and is gone [34]. They did not ask for the app's data to be deleted. | keeps everything, leaves the zone, and goes on in the next zone at once, as described below the table, so that its copy goes to iCloud again. |
| Deleted | Another copy of the app deleted the zone. No version in this design does that. | treats it as purged. A later version that wants to delete everything everywhere can then do so by deleting the zone. |

A device that keeps its data after losing its zone, because of a reset or because its zone was found missing with no report, leaves the zone (above). It then has something to send, and it goes on in the next zone at once: it joins the next zone if a fetch names it, and creates it otherwise.

Apple's pages disagree about what to do after an encryption reset [7]. This design sends the data again, because after such a reset the copies on the devices are the only ones left.

After a reset the first device to send its toy into the next zone creates the record there. Every other device that sends is refused, and handles the record that comes back by section 6. A held toy can still be chosen after a reset. It has no system fields then, and section 6, step 6 says what each answer does.

### When a save finds no zone

A record's save can also fail because the zone is missing. When it was sent without the zone's own save, iCloud attaches no record and creates nothing, and the engine drops the save [54]. The store's marks stay. The device never saves that zone again: a zone's own save that reaches iCloud after the zone was deleted makes the zone again under its name, and from then on engines are not told that it was deleted [54]. If the failure is marked as an encryption reset [34], the device acts on that. Otherwise it asks the engine to fetch, so that a deletion and its reason are seen before anything is sent again. In the probe an engine was not told of such a deletion by itself within the minute it was watched, on the Mac that had made the deletion [54].

When a fetch that began after the failure has finished, a deletion that counts is handled by its reason, and a higher existing zone is joined. If the fetch reported neither, the device gives up its zone as missing: it keeps everything, notes its zone as *deleted*, leaves it, and goes on in the next zone at once, as described above for a device that keeps its data.

A device gives up a zone as missing in this way at most once in a run. If a save finds no zone after that, in the same run, the device keeps its marks, sends nothing more in that run, and goes on at the next launch.

## 10. When something fails

| What fails | Who acts | What happens |
|---|---|---|
| The network, a server limit, a busy zone, or the service or the account being unavailable for a while | The engine [8] | It tries again later. The app does nothing and deletes nothing [45]. |
| A save of the toy is refused | The app | Section 6. |
| A save of a finished play is refused | The app | Section 7, rule 4. |
| The answer to a save is lost, although the save may have landed [51] | The app | The marks stay, and a play stays *sent*. The gate lets the change go again, a play that is *sent* only after a fetch that began after it was last handed over (section 11). A save whose answer was never stored was refused when it was sent again, with the landed save attached [54]. The stamps, and the state *sent*, let the rules recognise a save that had landed (sections 6 and 7). |
| iCloud no longer knows the Toy record that the device wanted to change | The app | The base is emptied and the toy goes out as a new record [10][52][54]. |
| A deletion of the Toy record arrives | The app | No version in this design deletes that record. The base is emptied, and nothing else changes. |
| The zone is missing | The app | Section 9. |
| The person's iCloud storage is full [13] | The app | The data stays in the store, marked as not received, and a play stays *sent*. The engine drops such a save from its list [17]. The run's note of a full storage holds every save back, and the creation of a zone, until the next launch or the next time the app comes to the front, so nothing repeats in a loop (section 11). A line in the app's settings says so, until a save is accepted again. |
| Writing fetched changes into the store fails | The app | It stops saving the engine's state for this run, so that the same changes are fetched again [3][17], and the fetch does not count (section 11). Applying a change twice gives the same result as applying it once. Storing a fetched change never fails because of its content: a play this version cannot read is kept as it is (section 14). |
| A setup error, such as a missing entitlement or a record type that is not in the production schema | The app | It is logged. The data stays on the device. |

## 11. When things are sent and fetched

### Three words

To *queue* a change is to add it to the engine's list of pending changes. To *hand over* a record is to give it to the engine when the engine asks for it. To *send* something is the whole way: it is queued, handed over, and saved by iCloud. A finished play that has been handed over and not confirmed is in the state *sent* (section 7).

### One rule for sending

The rules of sections 6 to 10 change the store and its marks, and they queue nothing themselves. One gate decides what is queued in the engine and what is handed over.

The gate is asked at a sending moment (the table below), when one of its conditions lifts, and when the engine asks for a record. When the gate opens, the device queues from the store: every play that is *unsent*, every play that is *sent* and that condition 5 lets through, a deletion for every entry that is *cleared*, and the toy if condition 4 lets it through. The engine drops duplicates [3]. When the engine asks for a record that the gate does not let through, or that the store no longer wants sent, the app hands over nothing and withdraws that save.

A save or a deletion of a record is queued or handed over only when all of these hold:

1. The account is known: from the store's note, or, after a start from nothing, once the engine or CloudKit has named it (section 8).
2. The device uses a zone that it knows to exist (section 9).
3. A fetch has finished in this run since the device began to use that zone. It began to use it at the launch, for the zone the store already notes, and at the join, for a zone it joined in this run. After a start from nothing, it has begun to use a zone only once it has joined one.
4. For the toy: it is marked as changed, no toy is held, and section 6, step 4 has not stopped it in this run.
5. For a play that is *sent*: a fetch has finished that began after the play was last handed over. A play that is *unsent*, and a deletion, need nothing more.
6. For a save: no save has been refused for a full storage since the launch or the last return to the front (section 10).
7. The device has not stopped sending in this run (section 9, "When a save finds no zone").

So a device fetches before it sends, in every run and after every change of zone. The zone's own save does not pass the gate: section 9 says when it is queued.

While condition 3 or condition 5 holds something back, each sending moment asks the engine to fetch instead. For the toy that is at most once a minute, and nothing asks in a loop.

### A fetch that has finished

The rules wait for "a fetch that began after a moment has finished". The engine reports the beginning of a fetch with `willFetchChanges`, the changes with `fetchedDatabaseChanges` and `fetchedRecordZoneChanges`, and the end with `didFetchChanges`, one end for each beginning [55]. Only a fetch that the app asked for opens the gate. Such a fetch has finished, in the sense of this document, when all of these hold:

- the app asked for it, with `fetchChanges`, at or after the moment in question;
- the engine reported the beginning of a fetch after that request;
- the request returned without an error;
- no error was reported for the zone in use;
- everything the fetch brought is saved in the store.

Apple's documentation reports a fetch's failure in two places. For a zone, the end of that zone's fetch (`didFetchRecordZoneChanges`) carries an error. For the app's own request, `fetchChanges` throws an error, and it returns only after the delegate has handled the fetch's events [55].

When the app asks while the engine is already fetching, the engine may begin no new fetch and report no beginning [55]. If the request returns and no fetch began after it, the request was served by a fetch already under way, which began before the moment, and the app asks again.

The engine's own fetches deliver changes, which are applied, but they never open the gate. The end of a whole fetch carries no error, and Apple's documentation names no place where a failure in the database phase of a fetch that the engine began by itself is reported [55] (open point 17). A fetch whose changes could not be written does not count either (section 10).

### The moments

| Moment | What the app does |
|---|---|
| Launch | Creates the engine and asks for a fetch. The gate opens once that fetch has finished (section 8). |
| The app comes to the front | Asks for a fetch, so that the toy is the latest before the person plays. Forgets a full storage noted in this run, and asks the gate. |
| A play is finished | Asks the gate at once, for the play and the toy. |
| The toy changes | Asks the gate for the toy, at most once a minute. The last change of a session is thus on its way within a minute, also on a Mac whose app stays in front while the person walks away. |
| The person clears the history | Asks the gate at once, for the deletions. |
| The person taps *Keep This One* | Asks the gate at once, for the toy. |
| The app leaves the front | Asks the gate for the toy, and asks the engine to send within the background time the system grants, so that the save is out before the app is suspended. |
| A push arrives | Nothing. The engine fetches by itself [2]. |

A *sending moment* is one of the moments of this table at which the gate is asked.

In good conditions a change reaches the other devices within seconds [14], but the engine's schedule is not promised [1]. No rule in this design depends on a delay being short.

On iPhone and iPad a push can wake the app in the background, unless the person force-quit it [15]. A Mac app receives pushes only while it runs, so on the Mac the fetches at launch and on coming to the front do most of the work [15][16].

The app never calls the engine's fetch or send from inside a delegate callback [11].

## 12. Encryption and privacy

### In iCloud

Both fields of both record types are encrypted fields [30]. CloudKit encrypts their values on the device before upload. Encrypted fields cannot be indexed or queried, which costs nothing here, because the engine fetches changes and never queries.

Whether a field is encrypted is decided when the field is introduced, and it stands for good once the schema is in production [31]. All four fields are encrypted from the start.

| What | Under standard protection, the default | Under Advanced Data Protection |
|---|---|---|
| The toy and the finished plays | The person can read them. Apple holds the keys [32]. | Only the person can read them: they are end-to-end encrypted [32]. |
| Record names, record types, the zone's name, the times of saves, and how many records there are | Readable by Apple | Readable by Apple [32] |
| The developer | Reads nothing [33] | Reads nothing |

The record names reveal little: the toy's record has the same name for everyone, and a play's record name is a random id. The zone's number shows roughly how many zones there have been, and its random id shows nothing. The times of saves show when a person played.

### On the device

The store has the system's default protection, under which a file can be read from the first unlock after a restart [35]. The strongest class makes a file readable only while the device is unlocked [35]. The store would then be closed whenever the device is locked, and a push that wakes the app in the background could not bring changes in. Device backups include the store [36].

### No encryption of the app's own

Goal 5 is met by CloudKit's encrypted fields. An inner layer of the app's own would add one thing: Apple could not read the data of people who do not use Advanced Data Protection. It would cost a key that has to reach the person's other devices through iCloud Keychain, data that is lost when the key is, and code to write and test. The design does not include such a layer. It does not rule one out either: the payload is opaque bytes, and a later format number could mark a payload that is encrypted once more.

### Declarations

The app uses only the encryption that Apple's system provides, which needs no export documents [37]. Whether data that only the person can read counts as collected, for the App Store's privacy details, is not settled by Apple's text (open point 9).

## 13. What the person sees

- **Nothing to set up.** With iCloud available, the app syncs. There is no switch in the app and no question at first launch [40]. A person who does not want it turns iCloud off for the app in the system's Settings [39].
- **One line in the app's settings.** It normally reads "Your finished plays, and the toy as you left it, go to your other devices through iCloud." When they cannot, the line says why: iCloud is not available on this device, the iCloud storage is full, or another device uses a newer version of the app. The line about a full storage stays until a save is accepted again. There is no alert [40]. For this line alone the app asks CloudKit for the account's status, and no rule about data depends on the answer. The only other question the app asks CloudKit is the account's id, after a start from nothing (section 8).
- **The offer.** A quiet line over the toy: "Another device has a different play.", with the buttons *Play That One* and *Keep This One*. The Toy record carries the kind of device and the time of its last change, so that the line can help to tell the two plays apart [40].
- **Taking up.** At a calm moment the toy changes to the other device's arrangement. VoiceOver says where the toy now rests.
- **Clearing the history.** The confirmation says how far the clearing reaches: this device at once, and the other devices as they sync. It promises no more than section 7 delivers. In a few rare cases a device that was away can bring cleared plays back (section 16).
- **Plays from a newer version.** They are counted in one line, such as "2 plays need a newer version of Nine Rings to show here."

## 14. Setup, schema, formats and tests

### Setup

The app has the iCloud capability with CloudKit and one container, push notifications, and on iPhone and iPad the background mode for remote notifications [2][15]. It uses neither iCloud Documents nor iCloud key-value storage. Apart from the question for the account's status, for the line in its settings, and the question for the account's id in section 8, only the engine talks to CloudKit.

### Schema and environments

The schema is the table in section 5: two record types with two encrypted fields each, and no indexes. It is kept as a text file in the app's repository and applied to CloudKit's development environment with Apple's `cktool`. It is deployed to production by hand in CloudKit Console, once, before the first release [20]. A production schema can only grow [20][31]. Because `payload` is opaque to CloudKit, a later change to what the app stores needs no change to the schema. Zones are not part of the schema: the app creates them as section 9 says.

Builds run from Xcode use the development environment, and TestFlight and App Store builds use production [20]. A store belongs to one environment, so a debug build keeps its store in a folder of its own.

### Formats

Each payload's `format` starts at 1. The JSON is read leniently, so a version that meets a value it does not know ignores it. Adding a value therefore needs no new format number. A new number is for a change that an older version would misread.

A version that meets a higher format number than it knows never interprets the payload.

- A finished play in a higher format is kept as it is and counted, not shown. So is a finished play that this version cannot read for another reason, such as broken JSON. Storing a fetched change therefore never fails because of its content. Clearing the history reaches these plays too (section 7, rule 7).
- A toy in a higher format is held as unreadable, right after case 1 of section 6, step 5. Its stamps are not read. It is neither taken up nor replaced, and while it is held this device sends no toy. This device's toy stays on the device until a version that can read the other one is installed, or until a readable toy arrives. A toy in a known format that this version still cannot read, because its JSON is broken or its moves break the puzzle's rule, is handled in the same way. At each launch, a held unreadable toy that this version can now read is handled as an arriving toy.

### Tests

- **The rules** are everything that decides, in sections 6 to 11. They are plain code that knows nothing of CloudKit. Their inputs are events such as "a toy arrived", "a save was refused", "a fetch began" or "the account signed in". They change the store and say what to queue, what to withdraw and when to fetch. Tests run them in memory, with several simulated devices against a small stand-in for iCloud that keeps records with change tags and refuses stale saves. Like CloudKit, the stand-in numbers its change tags afresh in every zone, refuses a save on the system fields of a record it no longer has, and refuses a save into a zone that does not exist [54]. Over many orders of events they check three things: no toy is replaced except by taking up or by choice, all devices end with the same history, and nothing that a purge removed is sent again.
- **The delegate** is a thin layer between the engine and the rules, and it decides nothing. It is tested against CloudKit's development environment with two engines on one machine, automatic syncing off, fetching and sending by hand [21], in a zone that only the tests use.
- **The open points** of section 15 are verified by hand on real devices.
- Continuous integration has no iCloud account and runs the first kind only.

## 15. Open points

Apple does not document these. Each is to be verified in the running app, on real devices, before release.

1. **A first save under a name that exists.** Apple's documentation says that it is refused under CloudKit's default save policy, but not what the refusal carries [9]. A developer reports that it is refused like a save with an old tag, with iCloud's record attached, and an older report describes a refusal that came without the record [49]. The probe saw it refused with iCloud's record attached, on one Mac, in the development environment [54].
2. **The engine's save policy.** An Apple engineer has stated that the engine checks the change tag on every save [49]. The documentation does not name the policy [18]. The probe saw a save on an old tag refused [54]. The toy's rule rests on points 1 and 2, and the history's guard on point 19, so these three are tested first, with two devices.
3. **The app's switch in Settings.** What the engine reports when only this switch is turned off, and when it is turned on again [18]. The design covers both a sign-out and a dormant engine.
4. **A state that returns from a backup or a device-to-device transfer** [18][44]. The design expects the engine to go on from its saved tokens, and the toy's rule to settle the rest. Two engines started from copies of one saved state behaved as two devices in the probe [54]. If the engine cannot continue from a restored state, the app discards the state and the device joins (principle 4): it offers its plays with their system fields, so plays cleared since the backup are removed (section 8). A backup restored on a device signed in to another account may be reported as a switch of account or as a sign-in. Either way the account differs from the store's note, and the device does the same (section 8).
5. **A device that was away for a long time.** CloudKit discards old deletions after a time that Apple does not publish, and a device that was away for longer has to fetch again from nothing [50]. By Apple's engineers' account, such a fetch brings every record iCloud has, and only some of the deletions the device missed [50]. On one Mac the probe saw a fetch from nothing deliver the deletions of records that were gone before it began, but its engines may count as one device to CloudKit [54]. If the engine reports that its tokens are no longer valid, the app discards the state and the device joins. It then offers its plays with their system fields, and CloudKit refuses the ones that were deleted since (point 19). If the engine instead fetches from nothing without telling the app, no join takes place, and the device could keep plays that were cleared on another device in the meantime. Which of the two the engine does is not documented [18].
6. **Pushes.** An engine with automatic syncing registered the app for remote notifications by itself in the probe, and sent queued changes within seconds. On one Mac it did not fetch another engine's change by itself within four minutes [54]. Whether pushes reach another device, arrive on the Mac, and wake the app on an iPhone is not known [15].
7. **Sending as the app leaves the front, and fetching as it comes to the front.** Apple gives no guidance on asking the engine to send while the app moves to the background. The general rule is to begin a background task before the work [51]. Whether the send completes within the time the system grants is to be measured. The engine's own code suggests that it fetches when the app becomes active [53], and in the probe it began a fetch half a second after the notifications that the app became active were posted; a real return to the front was not produced [54]. Such a fetch is the engine's own and does not count (section 11), so the app still asks for its own fetch.
8. **The encryption reset.** Developers have not managed to provoke it [34], so its rule can only be tested without CloudKit. Apple's advice on it conflicts, and the advice to delete stands on the engine's own deletion reason [7]. Deleting and keeping are both defensible, and they follow different intentions. This design keeps the data, as a choice of the product (section 9).
9. **The privacy declaration.** Apple's definition of collected data and its line about game saves point in different directions for data in a private database [38].
10. **Viewing, exporting and deleting.** A CloudKit article asks apps to let people view, export and delete their data [47]. The history shows the plays, clearing deletes them, and the system's Settings can delete everything. The app has no export.
11. **The sending rate.** Apple publishes no numbers for CloudKit's limits [48]. Once a minute is this design's estimate of a safe rate, and the number is easy to change.
12. **Accounts in unusual states.** Developers have reported errors about user keys on some accounts [46].
13. **How long iCloud keeps the report of a zone's deletion.** In the development environment, a report was still delivered to a new engine 8 hours and 50 minutes after a deletion that the probe had dated, and at least 10 hours after the deletions of an earlier run, and none had expired [54]. Apple publishes no time span. A device that was away for longer is not told why its zone is gone (section 16).
14. **The account's report and the first fetch.** An engine that starts from nothing reported a sign-in with the account's id in the probe, and one started from a saved state reported none [54]; a developer reports the same [17]. Apple's documentation does not say so, nor whether the report comes before the first fetched changes. If fetched changes come first, the app asks CloudKit for the account's id before it applies them (section 8). Also not documented: when an account changed while the app was not running, whether the engine reports it before the first fetched changes of a launch from saved state. The engine resets its state at such a change [4]. Under the gate nothing is sent before that launch's fetch has finished (section 11), but changes fetched before the report would be applied to the previous account's data.
15. **The reasons purged and reset.** Only the reason "deleted" could be produced in the development environment [54]. For a purge it is verified on devices: the app's data is deleted in Settings while a second device is asleep, and a third device joins afterwards. A reset cannot be provoked, so that it is reported in the same way stays an assumption, and its rule is tested without CloudKit only (point 8).
16. **Two devices that create a zone at the same instant.** This needs no test: their zones have different names, and section 9 says which one the devices go on in. On one Mac, the system's CloudKit daemon let one save of a zone go to the server at a time, so the probe could not produce two at the same instant [54].
17. **How a fetch reports what it did.** The end of a zone's fetch carries an error, and the app's own request throws one, but the end of the whole fetch carries none [55]. How the engine reports a failure in the database phase of a fetch it began by itself is not documented, so only the app's own fetches open the gate (section 11). Also not documented: whether a fetch names a zone that the device's own engine created (section 9).
18. **The engine and the records it sends.** The engine asks the delegate for batches of records to send, and keeps a change that failed with a recoverable error in its list [3][56]. Whether it asks the delegate for the record again before every attempt, also when it tries again after a failure, is not documented [51][56]. Section 7's rule for a play that is *sent*, and the stamps of section 6, rest on the delegate being asked each time. In the probe, a save whose answer was never stored was still pending after a restart [54].
19. **A save refused because the record is not known.** Apple's documentation names the error for a record that does not exist [9], but not that a save on the system fields of a deleted record gets it. Apple's sample handles such a refusal [52], and the probe saw it twice, on one Mac, in the development environment, minutes after the deletion [54]. Whether the refusal holds long after the deletion, once iCloud has discarded it, is not tested, and that is the case section 7 most rests on. If CloudKit made the record again instead, a device that comes back to its zone would bring back the plays cleared in the meantime, as section 16 then has to accept.
20. **A zone's save in a restored engine state.** The engine keeps pending changes in its saved state [3]. Whether it can send a zone's save from that state at a launch before the app has withdrawn it is not documented (section 9). If it can, a creation that was not confirmed could reach iCloud after the zone was deleted, and bring its name back.

## 16. The choices, and what was set aside

**1. `CKSyncEngine`, with a store of the app's own.**
- *Why:* the engine does the scheduling, pushes, tokens, retries and account watching [1][2][3][4], it shows the app every refused save [9], and it leaves the local store entirely to the app.
- *Set aside:* SwiftData's or Core Data's own mirroring. It needs the least code, but it removes the local data when iCloud goes away [23], settles conflicts silently [24], leaves duplicates to the app [25], and gives the app no say in timing [25]. These are against goals 3 and 4.
- *Set aside:* GameSave. It syncs one whole directory when the directory is opened and closed, and a conflict is between whole directories [26]. The history would need merging code of the app's own, its behaviour on account changes is not documented, and it is young [27].
- *Set aside:* iCloud key-value storage, which is meant for data that seldom changes and names no conflict rule [28]; files in the app's iCloud container, where coordinating and conflict handling are all the app's work [29]; CloudKit's operations without the engine, which Apple advises only for finer control [19]; and a server of the app's own.

**2. One Toy record, guarded by CloudKit's change tag.**
- *Why:* the question "has this device seen what it is about to replace?" is answered by CloudKit, with no bookkeeping of the app's own.
- *Set aside:* one record per device with version counters kept by the app. It needs a device identity that survives restores and transfers, and more code.
- *Set aside:* comparing the times of the last changes. Device clocks differ.

**3. The person chooses when both devices changed the toy.**
- *Why:* goal 3. Two plays cannot be merged, and Apple's guidelines ask for a quiet prompt that makes the versions easy to tell apart when a conflict cannot be settled automatically [40].
- *Set aside:* letting the latest change win. It needs less code and no line on screen, and it drops one play without a word.

**4. The data stays on the device when iCloud goes away, and goes when another account arrives.**
- *Why:* goal 4, and what Apple tells people about the app's switch and about signing out [39][43].
- *Set aside:* deleting on every sign-out, which is Apple's advice to developers [5]. A person who turned iCloud off for the app would find the history gone from the device.
- *Set aside:* merging the previous account's data into the new account, or keeping one store per account.

**5. A joining device offers everything it holds, each play with what it knew of it.**
- *Why:* it always ends with iCloud and the device agreeing, and it never deletes on a guess: a play is removed only when iCloud delivers its deletion or says it no longer has the record the device knew.
- *Set aside:* trusting the old *in iCloud* marks after the engine state was lost. If deletions from the gap never arrive, the device would show plays that no other device has, for good.
- *Set aside:* treating the store as a cache and building it again from a full fetch, which an Apple engineer suggests for caches [50]. After an encryption reset or a purge that the device did not witness, iCloud is empty, and the device's copy may be the only one left.

**6. A purge removes the data without asking; an encryption reset sends it again.**
- *Why:* in a purge the person chose to delete, and the system told them how far it reaches [42]. In a reset they chose nothing of the kind [34].
- *Set aside:* asking in the app after a purge, as one of Apple's articles suggests [7], and deleting after a reset, as one of Apple's notes says [7].

**7. Two fields, `format` and `payload`.**
- *Why:* fields in production are permanent [20][31], and the server cannot use encrypted fields anyway [30]. With an opaque payload the schema never has to change.
- *Set aside:* one field for each value. Every later addition would need a schema deployment before the app's release.

**8. Clearing deletes each record.**
- *Why:* it removes exactly what the clearing device knew, so a play finished elsewhere in the meantime survives.
- *Set aside:* deleting the zone, which would also hit plays the device never saw.
- *Set aside:* a "cleared before this moment" mark, which depends on clocks or drops plays from a device that had not yet heard of the clearing.

**9. No iCloud switch in the app.**
- *Why:* the system has one for each app [39], people expect apps to follow it [40], and an engineer at Apple advises against a second one [41].
- *Set aside:* a switch of the app's own. It would need a rule for what it does to data already in iCloud.

**10. Apple's encryption only.** Section 12 gives the reasons and what an inner layer would add and cost.

**11. The toy goes out at most once a minute while the person plays, and at once at a few moments.**
- *Why:* the other devices need the toy as it was left, not every move. A finished play, the person's choice of *Keep This One*, and the app leaving the front send the toy at once (section 11).
- *Set aside:* sending at every rest, which means a request and a push for almost every move.
- *Set aside:* sending only when the app leaves the front. A Mac app can stay in front while the person walks away.

**12. The Toy record carries the stamps of its last twenty versions.**
- *Why:* a device's own save can come back as a fetched change before its confirmation [17]. Its confirmation can also be lost, and the save that is sent again is then refused because of the device's own first save [49][51][54]. Without its own stamp on the record, the device would take its own toy for another device's. And when another device has gone on from a save whose answer was lost, the earlier stamps show the first device that the arriving toy was written with its own in view. Without them it would ask the person about a play that only continues the one here. The earlier stamps also show a device that a record is older than the one it holds, when an answer or a record arrives out of order.
- *What the stamps are not:* they name versions of the one record, in the order in which CloudKit accepted them. They name no device, and they compare no times.
- *Set aside:* comparing change tags alone.

**13. Each record has its own encryption key, which is CloudKit's default.**
- *Set aside:* one key for the whole zone, available from iOS 26 and macOS 26. It saves some storage, but a zone with such a key allows only sharing of the whole zone, is not delivered to older systems, and keeps its kind of key for as long as it exists [57]. Every zone of this design is created afresh, so a later version could choose it for its next zone.

**14. A zone's name carries a number and a random id, and no name is used twice.**
- *Why:* CloudKit keeps a zone's change tags, its tokens and the report of its deletion under the zone's name [54]. Under a name that is used again, a device that knew the old zone is told nothing, keeps the old zone's records, and can replace a toy it has never seen when the tags happen to be equal. Apple's 2018 paper says that creating a zone again makes the old tokens invalid [50], but the probe saw no such error, and the engine was told nothing [54]. A number alone does not keep the names apart: a device that has never heard of the old numbers, such as a new device after the report of a deletion has expired, would use an old name again. The random id makes every name new by how it is made, and the number keeps the zones in order. Under a new name, every device that still hears the report is told what became of the zone it knew, and a save into the old zone is refused. A zone's own save never waits in the engine (section 9), so a creation cannot bring a deleted name back, except in one narrow case that this section accepts.
- *Set aside:* making the zone again under its name, as Apple's sample does [10].
- *Set aside:* a number alone, with each device remembering the highest it has heard of. It fails as soon as a device has not heard.
- *Set aside:* one name, with a record of the app's own that marks each copy. It needs a third kind of record, CloudKit cannot check it when a toy is saved, and it rebuilds what the zone's name already provides.

**15. Each finished play keeps CloudKit's system fields of its record.**
- *Why:* it gives the history the guard the toy already has. When a device offers a play it knew, CloudKit says whether the record is still there [52][54], so a device that comes back to its zone after a long absence, a lost state, a restore or a sign-out does not bring back plays that were cleared meanwhile, even when iCloud no longer delivers their deletions.
- *Set aside:* a list of cleared plays kept by the app and synced as records of its own. It needs a third kind of record that grows for good.
- *Set aside:* accepting that a device that comes back brings cleared plays back.

**16. One gate decides what is sent.**
- *Why:* the conditions for sending come from several rules: the account, the zone, the fetch, a held toy, a lost answer, a full storage. Stated once, every rule only marks the store, and two builders build the same behaviour.
- *Set aside:* each rule queueing for itself, with its own conditions.

### What the design accepts

- A device sees another device's play up to a minute late. It is not a live mirror.
- The Mac receives changes only while the app runs.
- There is one toy for the person. After two devices were played apart, one play is kept.
- A device that was signed out, or signed in and not yet in a zone, while the app's data was deleted from iCloud brings its copy back.
- A device that is not told why its zone is gone, because it was away for longer than iCloud keeps the report, keeps its data and brings it into the zone in use. Data deleted from iCloud in the meantime can come back through it.
- A device that was offline when the person deleted the app's data in Settings, and was played on meanwhile, removes the plays and the toy made after the deletion too.
- After a reset of the encrypted data, a device that slept through it brings back plays that another device cleared before the reset. Their deletions went with the zone.
- A device that brings its plays into another zone offers them as new there.
- If a zone's creation lands and its answer is lost, and the zone is deleted before the app has withdrawn the zone's save, the name can come into use a second time. A device that knew the zone and slept through its deletion is then not told.
- A play sent for the first time has no system fields. If its answer is lost, and another device clears it after a fetch began here and before this device's second save lands, the clearing is undone for that play.
- A device whose unconfirmed save lies more than twenty versions back shows the offer, although the toy in iCloud continues its own.
- If another account signs in on a device, plays that had not yet reached iCloud are lost with the rest.
- Under standard protection Apple holds the keys. Record names, counts and times are readable by Apple in any case.
- When the same play was finished on two devices, the record that arrived first is kept.
- An older version of the app cannot share a toy written in a newer format.

## 17. Cases, one by one

| Situation | What happens |
|---|---|
| The device has no iCloud account | The app works from its store. The engine is dormant. |
| A new device, and iCloud has data | The device joins once the account is known. The history fills in and the toy is taken up. If the person played before the toy came in, they are asked. |
| The app is deleted and installed again | The same as a new device. |
| The person plays on one device, then opens another | The first sends as it leaves the front. The second fetches as it comes to the front and takes the toy up. |
| Two devices were played apart | The device that syncs second meets the other toy, through a fetch or a refused save, holds it, and shows the offer. |
| The offer is never answered | That device's toy stays on that device. The other devices go on sharing. |
| Three devices | The third takes up whichever toy is in iCloud. |
| A device is restored from a backup, with the same account | The store and the engine state return as they were. The engine goes on from its tokens. The toy is taken up, or the person is asked, by the usual rule. If the engine cannot go on, the device joins, and CloudKit tells it which of its plays are gone (open point 4). |
| A backup is restored on a device with another account | The engine reports a switch of account or a sign-in. Either way the account differs from the store's note: the data is removed, and the device joins with nothing (open point 4). |
| Two devices are set up from one backup | They are two devices with the same starting point. Nothing in the data tells devices apart, so nothing is confused. |
| The person signs out of iCloud, or turns iCloud off for the app | The data stays. The app works from its store. |
| The same account returns | The device joins: the histories unite, plays cleared meanwhile are removed, and the toy's rule decides. |
| Another account signs in | The previous data is removed. The new account's data arrives. |
| The iCloud storage is full | Saves are refused. The data stays, marked as not received, and goes out again at the next launch or return to the front. A line says so until a save is accepted again. |
| The device is offline | The engine waits. The store keeps the marks. Nothing is sent in a run before a fetch has finished. |
| The person deletes the app's data from iCloud in Settings | Every device for which the deletion counts (section 9) removes the history and puts the toy back to its start. What was removed is never sent again. When the person plays again, the devices go on in the next zone. |
| The person resets their encrypted data | Every device for which the deletion counts (section 9) keeps its data, leaves the zone and goes on in the next zone at once, so that its copy goes to iCloud again. The first toy to arrive there becomes the record, and a device with a different toy shows the offer. |
| A device was asleep while the app's data was deleted from iCloud, and another device played on | When it wakes, it is told of the deletion, removes its data, and joins the new zone. |
| A device joins for the first time after an old deletion | It is told of the old deletion, and keeps what it holds: it has no zone note. |
| A device was away while its zone was reset and the next one was purged | It removes its data. Both deletions count for it, and one of them is a purge. |
| Two devices create the next zone at the same time | There are two zones with one number. The device in the lower one joins the higher one and brings everything, and the lower zone is left behind. |
| The history is cleared while another device is offline | The other device removes those plays when it syncs. Plays it finished meanwhile stay. |
| The history is cleared while another device is signed out, or put away for months | When that device comes back to the same zone, it offers its plays with their system fields. CloudKit refuses the cleared ones as unknown, and the device removes them. |
| The app is closed between a held toy and the person's answer | The toy stays held. Nothing is sent at the next launch, and the offer shows again. |
| The same play is finished on two devices | One entry: the record that arrived first. |
| The app crashes between a change and its sending | The store's marks queue the change again once the next launch's fetch has finished. |
| The answer to a save is lost | The record's stamp shows the device that the record in iCloud is its own. A finished play stays *sent*, so clearing still reaches it. |
| A save lands, its answer is lost, and the person plays on elsewhere | The first device finds its own stamp among the arriving toy's earlier stamps and takes the toy up. |
| An answer or a record arrives out of order | A version older than the one the device holds changes nothing. The base never goes back. |
| A play's save lands after the play was cleared, here or on another device | The play stays cleared, and its deletion is sent. |
| An older version meets a newer format | A finished play is counted and not shown. A toy is neither taken up nor replaced. |
| A device's clock is wrong | Only the order and the times shown in the history are affected. |

## 18. Sources

Each entry says what kind of source it is. *Doc* is Apple's documentation, including the headers in the Xcode 27.3 SDK, the Human Interface Guidelines and Apple's support pages. *Apple, other* is Apple outside its documentation. *Reports* are other developers. *Tested* is what this project's own probe saw in CloudKit. *Not documented* means that nothing was found.

### CloudKit and `CKSyncEngine`

1. *Doc.* `CKSyncEngine`, overview and `Configuration.automaticallySync`. The engine schedules sending and fetching through the system's scheduler, schedules again after recoverable errors and server limits, and its schedule is not determinate. `fetchChanges` and `sendChanges` run a sync on request.
2. *Doc.* `CKSyncEngine`, overview. The engine finds or creates a database subscription and fetches after silent pushes. It needs the CloudKit and remote-notification entitlements.
3. *Doc.* `CKSyncEngine.State` and `Event.StateUpdate`. The engine keeps the change tokens and its other state. The app has to save the serialized state with its own data, together with the changes fetched before it. Pending changes are kept without duplicates, and changes that failed recoverably stay in the list.
4. *Doc.* `CKSyncEngine`, "Accounts", and `Event.AccountChange`. The engine watches the account. With no account, or with sync turned off in Settings, it stays dormant. When the account changes it resets its state, pending changes included, and reports a sign-in, a sign-out or a switch with the user record ids. Changes made while the app was not running arrive as one event, from the last known state to the current one.
5. *Doc.* `Event.AccountChange`. Apple's advice is to delete the previous account's local data on a sign-out and on a switch, and at a sign-in to keep local data apart, merge it, delete it, or ask.
6. *Doc.* `CKDatabase.DatabaseChange.Deletion.Reason` and `CKSyncEngineZoneDeletionReason`. A zone's deletion comes with a reason: deleted, purged by the person in Settings, or lost in a reset of the person's encrypted data.
7. *Doc.* The same pages and the article "Encrypting User Data". For a purge: delete the local data and do not send it again; the article says to ask the person first. For an encryption reset Apple's pages disagree: the article, the Swift reference and the older fetch operation say to send the local data again, and the note on the engine's own deletion reason in the 27 SDK says to delete it and not to send it again.
8. *Doc.* `CKSyncEngine`, "Error Handling", and `CKError`. The engine itself retries `notAuthenticated`, `accountTemporarilyUnavailable`, `networkFailure`, `networkUnavailable`, `requestRateLimited`, `serviceUnavailable` and `zoneBusy`: a missing sign-in, a temporarily unavailable account, network failures, rate limits, an unavailable service and a busy zone. Other errors are left to the app.
9. *Doc.* `CKError.Code.serverRecordChanged`, `CKError.Code.unknownItem`, `CKRecord`, `CKRecord.recordID`, `Event.SentRecordZoneChanges`. A save is refused when the server's record has a newer change tag. The error carries the server's record, the client's record and their ancestor. A new record under an id that exists is refused only under the save policy `ifServerRecordUnchanged`, which is the default. `unknownItem` means that the specified record does not exist. After a successful save the app keeps the record's system fields, which carry the new tag, for its next save, and after a successful deletion it removes them.
10. *Apple, other.* Apple's sample app for the engine (`sample-cloudkit-sync-engine`, which Apple publishes on GitHub) and WWDC23 session 10188, "Sync to iCloud with CKSyncEngine". Zones are saved before records. A refused save is resolved and queued again. A missing zone is created and the save queued again. A record the server does not know is uploaded again. The sample has no code that registers for pushes.
11. *Doc.* `CKSyncEngineDelegate` and `CKSyncEngine`. The engine delivers events one at a time: the delegate receives the next event only when it has finished handling the current one. The delegate does not call the engine's fetch or send from inside a callback, and the framework stops an app that does. Production allows one engine per database; development allows several, for tests. The engine is to be created early in the launch.
12. *Doc.* `CKRecord`, `CKError.Code.limitExceeded`, technote TN3164. A record holds at most 1 MB. The engine's documentation gives 250 records per request; another Apple page gives 400 items and 2 MB. A container holds at most 1,000 zones.
13. *Doc.* `CKContainer`, `CKError.Code.quotaExceeded`. The private database counts against the person's iCloud storage. When it is full, saves fail, and the app is to point the person to their storage settings.
14. *Apple, other.* WWDC23 session 10188. In normal conditions a change syncs within seconds. Without a network or with a low battery it waits.
15. *Doc.* "Pushing background updates to your App", `NSApplicationDelegate`, "Configuring background execution modes". On iPhone and iPad a silent push can start or wake the app in the background, with low priority, possibly throttled, and not after the person force-quit the app. A Mac app receives pushes only while it runs, and macOS has no background modes.
16. *Apple, other.* Developer Forums thread 756315 (an Apple engineer, June 2024). On the Mac, CloudKit syncing mostly when the app comes to the front is as designed.
17. *Reports.* Developers who shipped the engine, in published notes of 2026 and in Developer Forums threads 771941 and 774014. A save refused for a full quota drops out of the pending list. A device's own changes sometimes come back as fetched changes. The state must be saved only after the fetched changes are safely stored. An engine created without saved state reports a sign-in. One developer saw a fetch from nothing replay the zone's history, deletions included; see [50].
18. *Not documented.* What the engine does with a state restored from a backup, or with an expired change token. Its save policy, which only an engineer's answer names; see [49]. Whether it registers for pushes by itself. What it reports when only the app's iCloud switch is turned off. Whether an engine created without saved state clears changes that were queued before it reported the account, and whether its report of the account comes before the first fetched changes.
19. *Apple, other.* WWDC23 session 10188. Apple's advice: the Core Data container for a complete solution that includes storage, the engine for an app that brings its own storage, and the plain operations only for finer control.
20. *Doc.* "Deploying an iCloud Container's Schema", "Integrating a Text-Based Schema into Your Workflow", `CKContainer`. The development schema can be written as text and applied with `cktool`. Deploying to production is done in CloudKit Console and only adds. Record types and fields in production cannot be deleted or changed. App Store and TestFlight builds use production, and Simulator uses only development. A container cannot be deleted or renamed.
21. *Doc and Apple, other.* `Configuration.automaticallySync` and Apple's sample. Apple gives no stand-in for CloudKit in tests. With automatic syncing off, a test fetches and sends by hand, and several engines on the development database stand in for several devices.

### Other ways to sync

22. *Doc.* SwiftData, "Syncing model data across a person's devices". SwiftData syncs through Core Data's `NSPersistentCloudKitContainer`, and by default it does so whenever the app has the CloudKit entitlement. `cloudKitDatabase: .none` turns it off.
23. *Apple, other.* Developer Forums threads 764080, 772015 and 811294 (Apple engineers, 2024 and 2025). That container removes the local store when the person signs out, changes account, or turns iCloud off for the app, changes not yet uploaded included. This is as designed. For other behaviour the engineer points to `CKSyncEngine`.
24. *Apple, other.* WWDC19 session 202, "Using Core Data With CloudKit". The container resolves conflicts by itself, last writer wins. Not documented: whether per record or per field. No interface shows a conflict to the app.
25. *Doc.* The Core Data sample article "Sharing Core Data objects between iCloud users": two devices that each create the same thing end up with duplicates, which the app has to remove itself. Technote TN3164: an app cannot set the timing of this syncing.
26. *Doc.* The GameSave framework and `GameSaveSyncedDirectory`. GameSave syncs one directory through iCloud Drive. Syncing starts when the directory is opened, pauses while it is in use, and resumes when it is closed. A conflict is between whole versions of the directory, settled by the person in a system alert or by the app after merging by itself.
27. *Not documented:* what GameSave does on a change of account, with iCloud off for the app, or with the storage full. *Apple, other:* Developer Forums thread 853970 (2026), a crash at the first opening on iOS 27, which an Apple engineer called Apple's bug.
28. *Doc.* `NSUbiquitousKeyValueStore` and Apple's sample "Synchronizing App Preferences with iCloud". 1 MB and 1,024 keys, meant for data that changes seldom, kept unencrypted on disk. The current page gives no conflict rule.
29. *Doc.* `NSFileVersion`, `NSFileCoordinator`, `NSMetadataQuery`. With files in the app's iCloud container, a conflict is between whole versions of a file. Coordinating access, finding the files and settling conflicts are the app's work.

### Encryption and privacy

30. *Doc.* `CKRecord.encryptedValues` and "Encrypting User Data". Values are encrypted on the device before upload. Strings, numbers, dates, data, locations and lists can be encrypted, and references cannot. Encrypted fields have no indexes and cannot be queried.
31. *Doc.* The same, and `NSAttributeDescription.allowsCloudEncryption`. A field can be encrypted only when it is introduced. Once in production, a field keeps its type and its encryption for good. New fields can be added later.
32. *Doc.* "iCloud data security overview" (support.apple.com/102651, January 2026) and the Apple Platform Security guide (August 2026). Under standard data protection, iCloud data is encrypted in transit and at rest with keys that Apple holds. Under Advanced Data Protection, a third-party app's CloudKit encrypted fields and assets become end-to-end encrypted, while plain fields and some metadata, such as modification dates, stay under keys that Apple holds.
33. *Doc.* `CKContainer.privateCloudDatabase`. The developer cannot see a person's private database.
34. *Doc.* "Encrypting User Data". When the person resets their encrypted data, the zone's data can no longer be decrypted. The app learns of it as a missing zone with a mark for the reset, or as the deletion reason in [6]. *Apple, other:* Developer Forums thread 772544. By an Apple engineer's account this loss happens only under Advanced Data Protection, and developers have not managed to trigger it in tests.
35. *Doc.* UIKit, "Encrypting Your App's Files", `UIApplication.isProtectedDataAvailable`, and the Apple Platform Security guide. On iPhone and iPad an app's files are by default protected until the first unlock after a restart, and stay readable after it. A file under complete protection is readable only while the device is unlocked. On a Mac the volume's encryption protects them.
36. *Doc.* "What does iCloud back up?" (support.apple.com/108770) and the Apple Platform Security guide. A device backup includes the app's data. Under standard protection Apple holds the backup's keys, and under Advanced Data Protection the backup is end-to-end encrypted.
37. *Doc.* App Store Connect Help, "Export compliance documentation for encryption". An app whose encryption is limited to what Apple's system provides needs no documents.
38. *Doc.* "App privacy details on the App Store". Data counts as collected when it leaves the device in a way that lets the developer or its partners access it. The same page tells apps with game saves to declare gameplay content. Not documented: which of the two applies to data that only the person can read.

### The person's side

39. *Doc.* "Change which apps sync and store data with iCloud" (support.apple.com/118225). Settings has a switch for each app. With it off, Apple tells people, the app's data exists only on the device.
40. *Doc.* Human Interface Guidelines, "iCloud". People expect apps to work with iCloud without being asked. No alert is needed when iCloud is unavailable, and a quiet note is welcome. Conflicts are to be settled automatically where possible, and otherwise by a quiet prompt that makes the versions easy to tell apart, as early as possible.
41. *Apple, other.* Developer Forums thread 764080. An Apple engineer advises against a sync switch inside the app and for leaving the control to Settings, as a personal view.
42. *Doc.* Mac User Guide, "Manage iCloud storage on Mac", and "Manage your iCloud storage" (support.apple.com/108922). The person can delete an app's data from iCloud. Apple says it is then removed from every device that syncs.
43. *Doc.* "Sign out of your Apple Account and iCloud on your devices" (support.apple.com/104958) and "What happens after you choose Sign Out But Don't Erase" (support.apple.com/122682). From iOS 26 a person who signs out can keep most data on the device.
44. *Doc.* "Using the file system effectively", `UserDefaults`, the Security framework. A restored device gets the app's files and settings back. Keychain items marked for this device only do not move to another device. Not documented: sync state that returns from a backup.
45. *Doc.* `CKAccountStatus`. While an account is temporarily unavailable, an app keeps its cached data.
46. *Reports.* Developer Forums thread 682652 (2021 and 2022). Errors about syncing user keys on some accounts.
47. *Doc.* CloudKit, "Providing User Access to CloudKit Data" and "Responding to Requests to Delete Data". An app that keeps a person's data in CloudKit should let the person view, export and delete it.
48. *Doc.* Technote TN3162, "Understanding CloudKit throttles". CloudKit throttles apps that send many requests in a short time. Apple publishes no numbers.

### CloudKit in closer detail

49. *Apple, other, and Reports.* Developer Forums thread 782333 (April 2025). An Apple engineer: the engine saves with the policy that refuses a save when the server's record has changed. The developer in that thread: a new record under an id that exists is refused in the same way, with the server's record attached. An older report, thread 125786 (2019), describes such a refusal that carried no record. Apple's documentation describes the refusal for an old tag, and says that a new record under an id that exists is refused under the default policy [9], but not what that refusal carries.
50. *Apple, other, and Reports.* Developer Forums threads 813286 and 813992 (Apple engineers, early 2026). A fetch from nothing returns every record the server has, which an app can use to build its local cache again. It returns a deletion only for a record that the fetching device itself created, or that was deleted while the fetch ran. A developer in the second thread saw tens of thousands of deletions arrive on a new device. A 2018 paper by Apple's CloudKit team says that old deletions are discarded once all recently active devices have seen them, that a device away for longer has to sync again from the start, and that creating a zone again makes the tokens for the old one invalid. Apple publishes no time span.
51. *Doc.* UIKit, "Extending your app's background execution time". An app that has to finish work as it moves to the background begins a background task before it starts the work. `CKError.Code.serverResponseLost`: a save whose answer was lost may be sent again if doing it twice does no harm. *Not documented:* asking the engine to send at that moment, what becomes of a send that is under way when the app is suspended, and whether the engine sends such a save again by itself.
52. *Apple, other.* The tests in Apple's sample for the engine [10]. After a record was deleted, a save under the same name with the old system fields fails because the server does not know the record, and a save without them succeeds as a new record.
53. *Not documented.* The CloudKit framework in macOS 27.3 contains names that suggest the engine schedules a fetch when the app becomes active. No documentation says so.

### Tested in CloudKit

54. *Tested.* This project's probe, in CloudKit's development environment, on macOS 27.3, with two or more engines on one Mac and one account, on 19 and 20 November 2026. Its questions, what each saw and how often, are in `docs/icloud-probe.md`. Production is not known, and the engines on one Mac were most likely one device to CloudKit. What the design uses:
    - **Records.** Every refusal of a save on an old tag, or of a first save under a name that exists, carried iCloud's record. Change tags are counters for each zone: the first record saved together with its zone gets the tag 3, and the count starts again when a zone is made again under its name. A save on the system fields of a record that had been deleted was refused as `unknownItem`, and a save without them made the record anew. Deleting a record that is gone succeeds. Of a save and a deletion queued for one record, the engine keeps the later. An engine's own save came back to it in a later fetch, always after its confirmation. A save whose answer was never stored was still pending after a restart, and sent again, it was refused with the landed save attached. Two engines started from copies of one saved state behaved as two devices.
    - **A zone made again under its name.** An engine that still holds state for the old zone is told of no deletion: its fetch shows the new records, its old token hides none of them, whether it comes back before or after the new zone has passed the tags it saw, and it keeps its old records. A new engine is not told of that zone's deletion either. A save on the old base was accepted when the tags happened to be equal, and it replaced a toy that engine had never seen; the other engines could read the record written this way. With unequal tags it was refused.
    - **A zone deleted and not made again.** An engine that holds state for it is told of the deletion with its reason, and so is an engine with no state, of every such deletion, together with the zones that exist. A report was still delivered to a new engine 8 hours and 50 minutes after a deletion that the probe had dated, and at least 10 hours after the deletions of an earlier run, and none had expired. One report from the engine names changed zones and deleted zones as two lists, with no order between them. The engine then fetches a new zone's records by itself, unless the fetch was limited to other zones: a fetch limited to some zones still reports the changed and deleted zones of the whole database, but brings no records of the other zones.
    - **A save into a missing zone.** A record's save sent without the zone's own save is refused as "zone not found", with no record attached: nothing is created, and the engine drops the save. A zone's own save that reached iCloud after the zone was deleted made the zone again under its name, and from then on engines, also the one that had deleted it, were not told that it was deleted. After a refusal for a missing zone an engine with automatic syncing, on the Mac that had made the deletion, was not told of the deletion within the minute it was watched. Saves already queued for a zone stay in the engine's list after it has reported the zone as deleted; if they are sent, they are refused and dropped. Zones are sent before records. Saving a zone that exists changes nothing, and a save on a base taken before it was still accepted. Two engines that each saved the same new zone both succeeded, with one zone, also from two processes; on the Mac the system's CloudKit daemon let one save of a zone go to the server at a time, so this does not show two saves at the same instant.
    - **The account and scheduling.** An engine that starts from nothing reported a sign-in with the account's id, and one started from a saved state reported none. An engine with automatic syncing registered the app for remote notifications by itself and sent queued changes within seconds, and it did not fetch another engine's change by itself within four minutes. When the notifications that the app became active were posted, the engine began a fetch half a second later, and the fetch reached the server. A fetch from nothing delivered the deletions of records that were gone before it began.
    - **Not reached.** Only the reason "deleted" could be produced: a purge and a reset of encrypted data cannot be provoked in the development environment.

### The engine's fetches and sends, and the zone's keys

55. *Doc.* `CKSyncEngine`, "Fetch changes from iCloud", `Event.WillFetchChanges`, `Event.DidFetchChanges`, `Event.WillFetchRecordZoneChanges`, `Event.DidFetchRecordZoneChanges` and `fetchChanges(_:)`, with their headers in the 27.3 SDK. Before a fetch the engine reports `willFetchChanges`; as changes arrive, `fetchedDatabaseChanges` and `fetchedRecordZoneChanges`; when the fetch has finished, `didFetchChanges`, one for each beginning. The beginning may not be reported when the app calls `fetchChanges` while the engine is already fetching, or when no account is signed in. The end of a zone's fetch carries an error, which is empty for a successful fetch; the end of the whole fetch carries none. `fetchChanges` returns only after the delegate has handled all related fetch events, and throws if the fetch fails. *Not documented:* how a failure of a fetch that the engine began by itself is reported, beyond the ends of the zones' fetches.
56. *Doc.* `CKSyncEngine`, "Batches", `nextRecordZoneChangeBatch(_:syncEngine:)`, `CKSyncEngine.State.pendingRecordZoneChanges` and `PendingRecordZoneChange`. A pending save names a record by its id. A send asks the delegate repeatedly for batches of records and sends each batch as one request. A change that fails with a recoverable error stays in the list. *Not documented:* whether the engine asks the delegate for the record again before every attempt, also when it tries again.
57. *Doc.* `CKRecordZone.EncryptionScope.perZone` and `CKRecordZone.encryptionScope`, with its header in the 27.3 SDK. A key for the whole zone is available from iOS 26 and macOS 26. It is set only when the zone is created and cannot be changed for the zone's lifetime. Such a zone allows only sharing of the whole zone, and older systems do not receive it.
