# Nine Rings: the iCloud design

*As of 19 November 2026.*

This document describes how the Nine Rings app keeps a person's play on all of their devices through iCloud. It can be read without knowing anything else about the app.

## How to read this document

Three kinds of statement appear here, and they are kept apart.

- **Facts about Apple's platform** carry a number in square brackets, such as [9]. The number leads to a source in section 18. Each source says what kind it is: Apple's documentation, Apple outside its documentation (its engineers on the developer forums, its sample code, its conference talks), reports from other developers, or "not documented". The facts were gathered on 18 November 2026, from the documentation that comes with Xcode 27.3 and from Apple's websites. Several of these interfaces are recent or were revised in 2026, so a reader's memory of them may be older than the sources.
- **Choices of this design** are written as choices, with their reasons. Section 16 collects them, each with what was set aside.
- **Open points** are in section 15: what Apple does not document, and what has to be verified in the running app before release.

## 1. The design in brief

- Each device keeps the person's data in **a store of its own**. The app works from that store and needs no network.
- Between the devices runs **`CKSyncEngine`**, Apple's sync engine for CloudKit, on the person's private database. The app has no server.
- **The toy**, which is the puzzle as the person left it, is one record in iCloud. A device replaces it only if it has seen the one that is there, and CloudKit checks this. When two devices have each changed the toy, the person chooses which one to keep.
- **Each finished play** is one record under its own id, written once. The history is the set of these records.
- **Everything the app stores in iCloud is in encrypted fields.** The app has no encryption code of its own.
- **Data leaves a device only through an act of the person:** clearing the history, deleting the app's data from iCloud in Settings, or another account signing in on the device.
- **No decision depends on a device's clock or on a device's identity.**
- The app has **no iCloud switch of its own**. The system's switch in Settings is the control.

## 2. The app and its data

### The app

Nine Rings shows the nine linked rings puzzle as a 3D toy and lets a person play it. The puzzle is a wire sword with nine rings on it, each held by a rod that links it to the next. The aim is to take every ring off.

The person taps a ring to take it off the sword or to put it back on. The puzzle's rule decides which rings can move: ring 1 always can, and any other ring can only when the ring before it is on and all the rings before that one are off. The 512 arrangements lie on one path, and the shortest way from every ring on to every ring off is 341 moves. The app can also take a move back, play the shortest way by itself, put every ring back on, or let the person set the rings by hand.

| Word | Meaning |
|---|---|
| the toy | The puzzle on screen, with everything needed to bring it back as it was. |
| a move | One ring going on or coming off. |
| at rest | No move is playing and none is waiting. |
| a play | The way from every ring on toward every ring off. A play begins whenever every ring is on. It is finished when the person's own move takes the last ring off. |
| a finished play | The record of one finished play: when it was, how many moves and undos it took, and how long. |
| the history | Every finished play, newest first. |

The app runs on iPhone and iPad with iOS 27.2 or later, and on the Mac, as a native app, with macOS 27.2 or later. It has one window. It keeps its data with SwiftData.

### The two things that go to the other devices

| | The toy | A finished play |
|---|---|---|
| How many | One for the person | One for each finished play |
| What it holds | The arrangement the moves start from, the moves made since (at most 2,000), a move stopped part way, the rings still waiting, the play in progress with its id and its counts, and the progress toward two achievements | The play's id, when it began and when it was finished, the number of moves and undos, the moves the app played for the person, the time spent, and the kind of device |
| Size | 264 bytes when untouched, about 1 KB in the middle of a play, at most about 5.4 KB | About 100 bytes |
| When it changes | At almost every rest, which is about once per move at a person's pace | Never. It is written once. |
| When it goes away | Never. Putting every ring back on starts it afresh. | Only when the person clears the history, which removes them all |

Two details matter later.

- **Time alone changes the toy's bytes.** The play in progress counts the seconds the person spends in front of it. The design treats two toys that differ only in that count as *the same toy*.
- **A play has an id from the moment it begins**, a random UUID. A toy carries its play's id with it.

A full play takes at least four and a half minutes at the app's fastest speed. A large history is therefore some hundreds or a few thousands of finished plays, well under a megabyte.

### What stays on each device

Settings stay on each device. Achievements are kept by Game Center for the signed-in player, and the app's note of what it has reported to Game Center stays on each device too.

## 3. What the design is for

1. **Continuity.** The person leaves one device, picks up another, and finds the toy as they left it.
2. **One history.** Every finished play appears on every device, once. A play that was finished on two devices appears once as well (section 7).
3. **Nothing replaced without a choice.** When two devices have each been played on separately, neither play is dropped unless the person says so.
4. **The device first.** The app works fully without iCloud. When iCloud goes away on a device, the data stays there.
5. **Private.** The data sits in the person's own iCloud, protected by Apple's encryption, where the developer cannot read it.
6. **Small.** Where Apple provides a mechanism, the design prefers it to code of the app's own for the same job.

The design is not for sharing between people, for showing one device's moves on another as they happen, for syncing settings, for reading the data on the web, or for devices on older systems.

## 4. The principles

Every rule in the later sections follows from these seven.

1. **The device's store is the person's copy, and it says for itself what iCloud has not yet received.** The app reads and writes only this store. Whether a change still has to go to iCloud is marked in the store, next to the data. The engine's list of pending changes can therefore always be rebuilt from the store.
2. **The toy is one record, and a device replaces it only if it has seen the one that is there.** CloudKit enforces this with the record's change tag [9]. A device whose own toy is unchanged takes up a newer one. When both have changed, the person chooses.
3. **A finished play is written once under its own id.** Records that never change cannot conflict. The history is the set of the records, and clearing it removes the records the device knows.
4. **A device knows iCloud only through its engine state.** When the engine starts from nothing, the device offers iCloud everything it holds and takes everything iCloud holds. Joining for the first time, returning after a sign-out and recovering from a lost state are the same act.
5. **Data leaves a device only by an act of the person.** There are three such acts: clearing the history, deleting the app's data from iCloud in Settings, and another account signing in on the device.
6. **Everything in iCloud is in encrypted fields.**
7. **No decision uses a clock or a device's identity.** Which toy is newer is CloudKit's answer, not a comparison of times. No device has a name or a number in the data. Two devices set up from one backup therefore behave like any two devices.

## 5. The parts

### On each device: the store

A SwiftData store whose own syncing through CloudKit is switched off (`cloudKitDatabase: .none`). SwiftData would otherwise mirror the store by itself as soon as the app has the CloudKit entitlement [22].

| Kept in the store | What it is for |
|---|---|
| The toy | The person's toy on this device. |
| Toy changed | A mark: the toy differs, in more than time spent, from the one last exchanged with iCloud. |
| Toy base | CloudKit's system fields of the Toy record as this device last saw it, with the stamps that record carried. The system fields carry the change tag. Empty when the device has never seen the record. |
| Last send | The stamp under which the toy was last handed to iCloud, and whether the toy has changed since then. |
| Own stamps | The stamps of this device's last twenty sends of the toy (section 6). |
| Held toy | Another device's toy, kept until the person has chosen, or until a calm moment lets the device take it up. Usually empty. |
| The finished plays | Each with a state: *unsent* (it has never left this device), *sent* (it was handed to iCloud, or was once known there, and iCloud has not confirmed it since), *in iCloud*, or *cleared* (the person cleared it here, and iCloud has not yet confirmed the deletion). |
| Engine state | The engine's saved state, as the engine hands it over [3]. |
| Account | The id of the iCloud account this data last synced with. Empty before the first time. |

Everything in this table except the toy and the plays themselves is called the *sync notes* below. All of it is in the one store, so it is saved together and comes back together from a device backup.

### Between the devices: the engine

One `CKSyncEngine` for the private database of the app's iCloud container, created at every launch, with automatic syncing on. The engine does the scheduling, the pushes, the change tokens, the retries and the watching of the account [1][2][3][4]. The app writes the engine's delegate. The delegate hands over records when the engine sends, stores what the engine fetched, and answers the events and errors described in sections 6 to 10.

Apple's own advice names the engine for an app that brings its own storage [19].

### In iCloud: one zone, two kinds of record

| Record type | How many | Record name | Fields |
|---|---|---|---|
| `Toy` | One | `toy` | `format` (encrypted integer) and `payload` (encrypted bytes) |
| `FinishedPlay` | One for each finished play | The play's id | `format` (encrypted integer) and `payload` (encrypted bytes) |

Both live in one custom zone of the private database. `payload` is JSON, and `format` says which version of that JSON it is.

- **The toy's payload** holds the toy, the time and the kind of device of its last change, the app's version, and its *stamps*. A stamp is a random id for one version of the record. The payload carries the stamp of this version, preceded by the stamps of the versions before it, twenty at most.
- **A finished play's payload** holds the values listed in section 2.

The sizes are far below CloudKit's limits [12].

## 6. The toy between devices

### What CloudKit does

CloudKit gives every stored record a change tag, which changes with each save. A device sends a save together with the tag it last saw. If the record in iCloud has changed since then, CloudKit refuses the save and returns the record it has [9].

A device that has never seen the record sends no tag. If a record of that name already exists, the save is refused in the same way, with iCloud's record attached. Apple's documentation does not describe this case; an Apple engineer and a developer's report do [49] (open points 1 and 2).

### What a device does

1. **The person changes the toy.** The store marks the toy as changed. A change in time spent alone does not set the mark.
2. **A sending moment comes** (section 11). If the toy is marked as changed and no toy is held, the device queues the Toy record. The record is built when the engine asks for it, from the toy as it then is, the base's tag, and the stamps: the base's stamps, followed by this version's own. A toy that has not changed since it was last handed over keeps its stamp, so sending it again uses no new one. The stamp is saved in the store before the record is handed over. If a toy is held by then, no record is built.
3. **iCloud accepts the save.** The returned record becomes the base. If the toy has not changed since it was handed over, the mark is cleared. An answer can arrive late, when a later version is already the base or is held. The returned record is then an earlier version, as the second case of step 5 describes, and the base stays as it is.
4. **iCloud refuses the save,** because the record there is not the one this device saw. The device treats the record that came back as an arriving toy. Should a refusal ever come without the record [49], the device asks the engine to fetch, and the record arrives that way.
5. **A toy arrives,** through a fetch or with a refusal. The first of these seven cases that fits is the one that applies.
   - *It is the record this device already holds as its base,* with the same change tag. Nothing is new, and nothing happens. A fetch from nothing delivers the record again in this way.
   - *It is an earlier version than one this device already holds.* Its own stamp is among the earlier stamps of the base, or of a held toy. Nothing happens. Answers and records can arrive out of order, and the base never goes back.
   - *Its own stamp is one of this device's own stamps.* It is this device's own send coming back, and it becomes the base. If it is the same toy as the one here, the mark is cleared. If the toy here has changed since, the mark stays and the toy is queued again.
   - *It is the same toy as the one here.* It becomes the base, and the mark is cleared.
   - *The toy here is not marked as changed.* The device **takes the arriving toy up**: it replaces the toy here at the next calm moment. At that moment it becomes the base, and the note of the last send is emptied, because the toy here has then never been handed over. Until then the base stays as it was. If the person changes the toy before that moment comes, the last case applies.
   - *The toy here is marked as changed, but it has not changed since it was handed over, and its stamp is among the arriving toy's earlier stamps.* This device's save reached iCloud, although its answer did not come back, and whoever wrote the arriving toy had that save before them. The device takes the arriving toy up, as in the case before.
   - *Otherwise.* Both devices have changed the toy. The device **holds** the arriving toy and shows the offer. The base stays as it was.

   When an arriving toy becomes the base in the third or the fourth case, a toy that was held is no longer held: iCloud has gone on from the record it came from.
6. **The person answers the offer.**
   - *Play That One.* The held toy replaces the toy here and becomes the base. The mark is cleared, and the note of the last send is emptied. Nothing is sent.
   - *Keep This One.* The held toy becomes the base, so the device has now seen it, and the toy here is sent at once. The other device takes it up when it arrives there.

A *calm moment* is one in which no move is playing, the person is not dragging a move, and no lesson, hand-setting of rings or congratulation is open.

While a toy is held, the device sends no toy: none is queued and none is built, at launch as at any other time. The person can go on playing, and their toy stays on the device until they answer. If a still newer toy arrives in the meantime, it takes the held one's place.

### Why this keeps goal 3

The toy in iCloud is only ever replaced by a device that has seen it. That device either had nothing of its own to lose and took it up, or showed it to the person, who chose. A play therefore disappears from a device in two ways only: the person went on from that same toy on another device, or the person chose the other play.

The stamps serve the cases that the change tag alone cannot settle. A device's own save can come back to it before the answer to that save, or the answer can be lost. The record's own stamp then shows the device that the toy is its own. And when another device has gone on from such a save, the earlier stamps show that the arriving toy was written with this device's toy in view: its writer either went on from it, or was shown it and chose their own.

### Three walks through it

**From the iPhone to the iPad.** The person plays on the iPhone and puts it down. As the app leaves the front, the iPhone sends its toy. iCloud accepts it, because the iPhone had seen the record that was there. The person opens the iPad. The iPad fetches as it comes to the front, and a toy arrives that is not the one it last saw. The iPad's own toy is not marked as changed, so the iPad takes the arriving toy up. The person goes on where they stopped.

**Two devices played apart.** On a flight the person plays on the iPad, offline. At home, before the iPad has synced, they play on the iPhone, and the iPhone sends its toy. When the iPad comes online it tries to send its own toy. iCloud refuses, because the record is no longer the one the iPad saw, and returns the iPhone's toy. The iPad holds it and shows "Another device has a different play." If the person taps Keep This One, the iPad sends its toy again, this time with the tag of the record it was shown, and the iPhone takes it up. If they tap Play That One, the iPad shows the iPhone's play and sends nothing.

**A new device.** The app starts on a new Mac with an untouched toy, which is not marked as changed. The engine starts from nothing and fetches everything. The toy in iCloud arrives and is taken up, and the finished plays fill the history. Had the person made a few moves on the Mac before the fetch came in, the Mac's toy would be marked as changed, and they would be asked.

## 7. The history between devices

1. **A play is finished.** The store adds it as *unsent* and queues its record. The record's name is the play's id. A play is recorded once on a device: finishing under an id the store already holds changes nothing.
2. **The record is handed to iCloud.** When the engine asks for the record, the entry becomes *sent*. This is saved in the store before the record is handed over.
3. **iCloud accepts the record.** The play becomes *in iCloud*. If the entry is no longer here, a deletion arrived while the save was on its way: another device had cleared the play. The entry then comes back as *cleared*, and its deletion is queued, so that the clearing stands.
4. **iCloud refuses the record because one of that name exists.** Either the same play was also finished on another device, or this device is offering what iCloud already has. The record in iCloud stands. Its content replaces the entry here, which becomes *in iCloud*. Whichever arrived first is kept. Should the refusal come without the record [49], the entry becomes *in iCloud* with the content it has, and the device asks the engine to fetch.
5. **A finished play arrives.** It is added, or replaces the entry of the same id, as *in iCloud*. An entry that is *cleared* stays cleared.
6. **A deletion arrives.** The entry is removed. An entry that is *unsent* stays, because iCloud never had it. If the entry was *cleared*, its own queued deletion is withdrawn.
7. **The person clears the history.** Entries that are *unsent* are removed at once. All other entries become *cleared*: they vanish from the screen, and their deletions are queued. When iCloud confirms a deletion, or reports that the record is already gone, the entry is removed for good.

The history on screen is every entry that is not *cleared*, newest first. Entries in a format this version of the app does not know are counted and not shown (section 14).

The state *sent* exists for a save whose answer never came back. iCloud may have such a play, and another device may already show it. Clearing therefore queues a deletion for it too, and a deletion that arrives for it removes it.

Clearing removes what this device knew was in iCloud, or might be there. A play that another device finishes afterwards is a new record and stays. So does a play that another device had finished, but not yet sent, when the clearing happened.

## 8. Joining, leaving and returning

### At every launch

1. The app opens the store and shows the toy from it. It never waits for iCloud.
2. It creates the engine, with the saved state or with none.
3. If the engine has its saved state, the app queues again whatever the store marks as not yet received: plays that are *unsent* or *sent*, deletions for plays that are *cleared*, and the toy if it is marked as changed and no toy is held. The engine drops duplicates [3]. A crash between a change and its sending therefore loses nothing.
4. If the engine started from nothing, the app queues nothing and builds no record until the account is known. Then the device joins, as described next, and the join queues everything. What the store holds may belong to another account, and Apple does not document that an engine which starts from nothing clears what was queued before it named the account [18].
5. It asks the engine to fetch.

### Joining

A device joins when its engine starts from nothing. That happens on its first launch with iCloud, after the account signed in (the engine has then reset its own state [4]), and after the saved state was lost or had to be discarded.

1. The device notes the account, as described below.
2. Every finished play marked *in iCloud* goes back to *sent*. Entries that are *cleared* stay cleared.
3. The zone is queued for saving. The engine saves zones before records [10], and saving a zone that exists changes nothing.
4. The device fetches. Plays that arrive are matched by id and become *in iCloud*. Deletions that arrive remove their entries, by rule 6 of section 7.
5. What is still *unsent* or *sent* is queued for saving, and what is *cleared* for deletion. The toy is queued if it is marked as changed and no toy is held.
6. For the toy there is no other step. Its base stays as it is, and the rules of section 6 decide.

Joining gives a union: afterwards iCloud and the device both have every play that either of them had. The one exception is a play whose deletion iCloud still delivers to the joining device: that play is removed.

### The account

The engine reports what happened to the account [4]. The store's own note of the account decides what the device does. The note is written at every join, from the account the engine names. If a join comes without a sign-in report (open point 14), the app asks CloudKit for the account's id.

| The engine reports | The store's account is | The device |
|---|---|---|
| A sign-in | empty | notes the account and joins. Whatever was made on the device without iCloud goes into the account. |
| A sign-in | the same account | joins. |
| A sign-in | another account | puts the toy back to its untouched start, removes the history and the sync notes, notes the new account, and joins with nothing. |
| A switch of account | any | does the same as for a sign-in to another account. |
| A sign-out | any | keeps everything and works from the store alone. If the note is empty, it notes the account that signed out. |

With no account, with iCloud turned off for the app in Settings, or under a restriction, the engine stays dormant [4] and the app works from its store. Apple does not document whether turning off the app's switch is reported as a sign-out (open point 3). The table covers both cases.

Apple's guidance for the engine is to delete the previous account's data on a sign-out as well [5]. Apple's pages for people say something else: with the app's switch off, the app's data exists only on the device [39], and a person who signs out can keep most data on the device [43]. This design departs from the guidance for developers on purpose. It keeps the data, for goal 4, and removes it when another account arrives, so that one person's plays never go into another person's iCloud.

## 9. When iCloud's copy is deleted

The engine reports the deletion of the zone together with a reason [6].

| Reason | What it means | The device |
|---|---|---|
| Purged | The person deleted the app's data from iCloud in Settings. Apple tells them it is then removed from every device that syncs [42]. | removes the history, puts the toy back to its untouched start, and empties the toy's notes: its base, its marks, its stamps and any held toy. The account note and the engine's state stay. It sends nothing again [7]. |
| Encrypted data reset | The person had to reset their encrypted data to recover their account. The zone could no longer be decrypted and is gone [34]. They did not ask for the app's data to be deleted. | keeps everything. It empties the toy's base and the system fields of a held toy, marks the toy as changed unless it is untouched, and joins, so that its copy goes to iCloud again. |
| Deleted | Another copy of the app deleted the zone. No version in this design does that. | treats it as purged. A later version that wants to delete everything everywhere can then do so by deleting the zone. |

A save can also fail because the zone is missing. The device does not answer that by creating the zone at once. It fetches first, so that a deletion and its reason are seen before anything is sent again. If the failure itself is marked as an encryption reset [34], the device acts on that. If no deletion is reported, the zone was never created, and the device queues the zone and the save again [10].

Apple's pages disagree about what to do after an encryption reset [7]. This design sends the data again, because after such a reset the copies on the devices are the only ones left.

After a reset the first device to send its toy creates the record. Every other device that sends is refused, and handles the record that comes back by section 6. A held toy can still be chosen after a reset. Because iCloud no longer has it, Play That One then marks the toy as changed.

## 10. When something fails

| What fails | Who acts | What happens |
|---|---|---|
| The network, a server limit, a busy zone, or the service or the account being unavailable for a while | The engine [8] | It tries again later. The app does nothing and deletes nothing [45]. |
| A save of the toy is refused | The app | Section 6. |
| A save of a finished play is refused | The app | Section 7, rule 4. |
| The answer to a save is lost, although the save may have landed [51] | The app | The marks stay, so the change is queued again at the next sending moment, the next return to the front or the next launch. The stamps, and the state *sent*, let the rules recognise a save that had landed (sections 6 and 7). |
| iCloud no longer knows the record the device wanted to change | The app | The base is emptied and the toy is sent as a new record [10][52]. |
| A deletion of the Toy record arrives | The app | No version in this design deletes that record. The base is emptied, and nothing else changes. |
| The zone is missing | The app | Section 9. |
| The person's iCloud storage is full [13] | The app | The data stays in the store, marked as not received. The engine drops such a save from its list [17], so the app queues it again at the next launch and the next time it comes to the front, and never in a loop. A line in the app's settings says so. |
| Writing fetched changes into the store fails | The app | It stops saving the engine's state for this run, so that the same changes are fetched again [3][17]. Applying a change twice gives the same result as applying it once. |
| A setup error, such as a missing entitlement or a record type that is not in the production schema | The app | It is logged. The data stays on the device. |

## 11. When things are sent and fetched

| Moment | What the app does |
|---|---|
| Launch | Creates the engine, queues what the store marks, and asks for a fetch. |
| The app comes to the front | Asks for a fetch, so that the toy is the latest before the person plays. Queues again what a full storage left unsent. |
| A play is finished | Queues the play's record and the toy. |
| The toy changes | Queues the toy at most once a minute. The last change of a session is thus on its way within a minute, also on a Mac whose app stays in front while the person walks away. |
| The app leaves the front | Queues the toy if it is marked as changed, and asks the engine to send within the background time the system grants, so that the save is out before the app is suspended. |
| A push arrives | Nothing. The engine fetches by itself [2]. |

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

The record names reveal little: the toy's record has the same name for everyone, and a play's record name is a random id. The times of saves show when a person played.

### On the device

The store has the system's default protection [35]. A stronger class would lock the store while the device is locked, and so stop syncing in the background. Device backups include the store [36].

### No encryption of the app's own

Goal 5 is met by CloudKit's encrypted fields. An inner layer of the app's own would add one thing: Apple could not read the data of people who do not use Advanced Data Protection. It would cost a key that has to reach the person's other devices through iCloud Keychain, data that is lost when the key is, and code to write and test. The design does not include such a layer. It does not rule one out either: the payload is opaque bytes, and a later format number could mark a payload that is encrypted once more.

### Declarations

The app uses only the encryption that Apple's system provides, which needs no export documents [37]. Whether data that only the person can read counts as collected, for the App Store's privacy details, is not settled by Apple's text (open point 9).

## 13. What the person sees

- **Nothing to set up.** With iCloud available, the app syncs. There is no switch in the app and no question at first launch [40]. A person who does not want it turns iCloud off for the app in the system's Settings [39].
- **One line in the app's settings.** It normally reads "Your finished plays, and the toy as you left it, go to your other devices through iCloud." When they cannot, the line says why: iCloud is not available on this device, the iCloud storage is full, or another device uses a newer version of the app. There is no alert [40]. For this line alone the app asks CloudKit for the account's status. No rule about data depends on the answer.
- **The offer.** A quiet line over the toy: "Another device has a different play.", with the buttons *Play That One* and *Keep This One*. The Toy record carries the kind of device and the time of its last change, so that the line can help to tell the two plays apart [40].
- **Taking up.** At a calm moment the toy changes to the other device's arrangement. VoiceOver says where the toy now rests.
- **Clearing the history.** The confirmation says how far the clearing reaches: this device at once, and the other devices as they sync. It promises no more than section 7 delivers. A device that was signed out at the time can bring cleared plays back when it returns (section 16).
- **Plays from a newer version.** They are counted in one line, such as "2 plays need a newer version of Nine Rings to show here."

## 14. Setup, schema, formats and tests

### Setup

The app has the iCloud capability with CloudKit and one container, push notifications, and on iPhone and iPad the background mode for remote notifications [2][15]. It uses neither iCloud Documents nor iCloud key-value storage. Apart from the status question for the line in its settings, only the engine talks to CloudKit.

### Schema and environments

The schema is the table in section 5: two record types with two encrypted fields each, and no indexes. It is kept as a text file in the app's repository and applied to CloudKit's development environment with Apple's `cktool`. It is deployed to production by hand in CloudKit Console, once, before the first release [20]. A production schema can only grow [20][31]. Because `payload` is opaque to CloudKit, a later change to what the app stores needs no change to the schema.

Builds run from Xcode use the development environment, and TestFlight and App Store builds use production [20]. A store belongs to one environment, so a debug build keeps its store in a folder of its own.

### Formats

Each payload's `format` starts at 1. The JSON is read leniently, so a version that meets a value it does not know ignores it. Adding a value therefore needs no new format number. A new number is for a change that an older version would misread.

A version that meets a higher format number than it knows never interprets the payload.

- A finished play in a higher format is kept as it is and counted, not shown.
- A toy in a higher format is held without an offer. It is neither taken up nor replaced, and while it is held this device sends no toy. This device's toy stays on the device until a version that can read the other one is installed, or until a readable toy arrives. A toy in a known format that this version still cannot read, because its JSON is broken or its moves break the puzzle's rule, is handled in the same way.

### Tests

- **The rules** of sections 6 to 9 are plain code that knows nothing of CloudKit. Their inputs are events such as "a toy arrived", "a save was refused" or "the account signed in". They change the store and say what to queue. Tests run them in memory, with several simulated devices against a small stand-in for iCloud that keeps records with change tags and refuses stale saves. Over many orders of events they check three things: no toy is replaced except by taking up or by choice, all devices end with the same history, and nothing is sent after a purge.
- **The delegate** is a thin layer between the engine and the rules. It is tested against CloudKit's development environment with two engines on one machine, automatic syncing off, fetching and sending by hand [21], in a zone that only the tests use.
- **The open points** of section 15 are verified by hand on real devices.
- Continuous integration has no iCloud account and runs the first kind only.

## 15. Open points

Apple does not document these. Each is to be verified in the running app, on real devices, before release.

1. **A first save under a name that exists.** A developer reports that it is refused like a save with an old tag, with iCloud's record attached. An older report describes a refusal that came without the record [49]. Apple's documentation does not describe the case.
2. **The engine's save policy.** An Apple engineer has stated that the engine checks the change tag on every save [49]. The documentation does not name the policy [18]. The toy's rule rests on points 1 and 2, so they are tested first, with two devices.
3. **The app's switch in Settings.** What the engine reports when only this switch is turned off, and when it is turned on again [18]. The design covers both a sign-out and a dormant engine.
4. **A state that returns from a backup or a device-to-device transfer** [18][44]. The design expects the engine to go on from its saved tokens, and the toy's rule to settle the rest. If the engine cannot continue from a restored state, the app discards the state and the device joins (principle 4).
5. **A device that was away for a long time.** CloudKit discards old deletions after a time that Apple does not publish, and a device that was away for longer has to fetch again from nothing [50]. By Apple's engineers' account, such a fetch brings every record iCloud has, and only some of the deletions the device missed [50]. Joining does not depend on deletions. If the engine reports that its tokens are no longer valid, the app discards the state and the device joins. If the engine instead fetches from nothing without telling the app, the device could keep plays that were cleared on another device in the meantime. Which of the two the engine does is not documented [18].
6. **Pushes.** Whether the engine registers for them by itself, as Apple's sample suggests [10], whether they arrive on the Mac, and whether they wake the app on an iPhone [15].
7. **Sending as the app leaves the front, and fetching as it comes to the front.** Apple gives no guidance on asking the engine to send while the app moves to the background. The general rule is to begin a background task before the work [51]. Whether the send completes within the time the system grants is to be measured. The engine's own code suggests that it already fetches when the app becomes active [53]. If that is confirmed, the app's own request for a fetch is dropped.
8. **The encryption reset.** Developers have not managed to provoke it [34], so its rule can only be tested without CloudKit. Apple's advice on it conflicts, and the advice to delete stands on the engine's own deletion reason [7]. Deleting and keeping are both defensible, and they follow different intentions. This design keeps the data, as a choice of the product (section 9).
9. **The privacy declaration.** Apple's definition of collected data and its line about game saves point in different directions for data in a private database [38].
10. **Viewing, exporting and deleting.** A CloudKit article asks apps to let people view, export and delete their data [47]. The history shows the plays, clearing deletes them, and the system's Settings can delete everything. The app has no export.
11. **The sending rate.** Apple publishes no numbers for CloudKit's limits [48]. Once a minute is this design's estimate of a safe rate, and the number is easy to change.
12. **Accounts in unusual states.** Developers have reported errors about user keys on some accounts [46].
13. **A zone that was created again before a device fetched.** After a purge or a reset, the first device that syncs creates the zone again. What the engine then reports to a device that still holds state for the old zone is not documented [18][50]: the deletion with its reason, tokens that are no longer valid, or nothing at all. In the last case that device would keep its old plays for good, and the devices would disagree. This is tested with two engines in the development environment, and the rule for it is fixed from what the test shows.
14. **The sign-in at a first launch.** A developer reports that an engine that starts from nothing always reports a sign-in [17]. Apple's documentation does not say so. If no such report comes, the app asks CloudKit for the account's id when it joins (section 8).

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

**5. A joining device offers everything it holds.**
- *Why:* it always ends with iCloud and the device agreeing, and it never deletes on a guess.
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

**11. The toy is sent at most once a minute, and when the app leaves the front.**
- *Why:* the other devices need the toy as it was left, not every move.
- *Set aside:* sending at every rest, which means a request and a push for almost every move.
- *Set aside:* sending only when the app leaves the front. A Mac app can stay in front while the person walks away.

**12. The Toy record carries the stamps of its last twenty versions.**
- *Why:* a device's own save can come back as a fetched change before its confirmation [17]. Its confirmation can also be lost, and the save that is sent again is then refused because of the device's own first save [49][51]. Without its own stamp on the record, the device would take its own toy for another device's. And when another device has gone on from a save whose answer was lost, the earlier stamps show the first device that the arriving toy was written with its own in view. Without them it would ask the person about a play that only continues the one here. The earlier stamps also show a device that a record is older than the one it holds, when an answer or a record arrives out of order.
- *What the stamps are not:* they name versions of the one record, in the order in which CloudKit accepted them. They name no device, and they compare no times.
- *Set aside:* comparing change tags alone.

**13. The zone's keys stay per record, which is CloudKit's default.**
- *Set aside:* one key for the zone, available from iOS 26. It saves some storage and cannot be changed later.

### What the design accepts

- A device sees another device's play up to a minute late. It is not a live mirror.
- The Mac receives changes only while the app runs.
- There is one toy for the person. After two devices were played apart, one play is kept.
- A device that was signed out while the history was cleared on another device brings the cleared plays back when it returns, unless iCloud still delivers their deletions to it. A device that was signed out while the app's data was deleted from iCloud brings its copy back.
- A device whose unconfirmed save lies more than twenty versions back shows the offer, although the toy in iCloud continues its own.
- If another account signs in on a device, plays that had not yet reached iCloud are lost with the rest.
- Under standard protection Apple holds the keys. Record names, counts and times are readable by Apple in any case.
- When the same play was finished on two devices, the record that arrived first is kept.
- An older version of the app cannot share a toy written in a newer format.

## 17. Cases, one by one

| Situation | What happens |
|---|---|
| The device has no iCloud account | The app works from its store. The engine is dormant. |
| A new device, and iCloud has data | The device joins. The history fills in and the toy is taken up. If the person played before the fetch came in, they are asked. |
| The app is deleted and installed again | The same as a new device. |
| The person plays on one device, then opens another | The first sends as it leaves the front. The second fetches as it comes to the front and takes the toy up. |
| Two devices were played apart | The device that syncs second is refused, holds the other toy, and shows the offer. |
| The offer is never answered | That device's toy stays on that device. The other devices go on sharing. |
| Three devices | The third takes up whichever toy is in iCloud. |
| A device is restored from a backup, with the same account | The store and the engine state return as they were. The engine goes on from its tokens. The toy is taken up, or the person is asked, by the usual rule (open point 4). |
| A backup is restored on a device with another account | The engine reports a switch of account. The data is removed, and the device joins with nothing. |
| Two devices are set up from one backup | They are two devices with the same starting point. Nothing in the data tells devices apart, so nothing is confused. |
| The person signs out of iCloud, or turns iCloud off for the app | The data stays. The app works from its store. |
| The same account returns | The device joins: the histories unite, and the toy's rule decides. |
| Another account signs in | The previous data is removed. The new account's data arrives. |
| The iCloud storage is full | Saves are refused. The data stays, marked as not received, and is offered again at the next launch or return to the front. A line says so. |
| The device is offline | The engine waits. The store keeps the marks. |
| The person deletes the app's data from iCloud in Settings | Every device that hears of it removes the history and puts the toy back to its start. |
| The person resets their encrypted data | Every device that hears of it keeps its data and sends it again. The first toy to arrive becomes the record, and a device with a different toy shows the offer. |
| The history is cleared while another device is offline | The other device removes those plays when it syncs. Plays it finished meanwhile stay. |
| The history is cleared while another device is signed out | When that device returns, it removes the plays whose deletions iCloud still delivers, and brings the others back. |
| The app is closed between a held toy and the person's answer | The toy stays held. Nothing is sent at the next launch, and the offer shows again. |
| The same play is finished on two devices | One entry: the record that arrived first. |
| The app crashes between a change and its sending | The store's marks queue the change again at the next launch. |
| The answer to a save is lost | The record's stamp shows the device that the record in iCloud is its own. A finished play stays *sent*, so clearing still reaches it. |
| A save lands, its answer is lost, and the person plays on elsewhere | The first device finds its own stamp among the arriving toy's earlier stamps and takes the toy up. |
| An answer or a record arrives out of order | A version older than the one the device holds changes nothing. The base never goes back. |
| A play's save lands after another device cleared that play | The play stays cleared, and its deletion is sent. |
| An older version meets a newer format | A finished play is counted and not shown. A toy is neither taken up nor replaced. |
| A device's clock is wrong | Only the order and the times shown in the history are affected. |

## 18. Sources

Each entry says what kind of source it is. *Doc* is Apple's documentation, including the headers in the Xcode 27.3 SDK, the Human Interface Guidelines and Apple's support pages. *Apple, other* is Apple outside its documentation. *Reports* are other developers. *Not documented* means that nothing was found.

### CloudKit and `CKSyncEngine`

1. *Doc.* `CKSyncEngine`, overview and `Configuration.automaticallySync`. The engine schedules sending and fetching through the system's scheduler, schedules again after recoverable errors and server limits, and its schedule is not determinate. `fetchChanges` and `sendChanges` run a sync on request.
2. *Doc.* `CKSyncEngine`, overview. The engine finds or creates a database subscription and fetches after silent pushes. It needs the CloudKit and remote-notification entitlements.
3. *Doc.* `CKSyncEngine.State` and `Event.StateUpdate`. The engine keeps the change tokens and its other state. The app has to save the serialized state with its own data, together with the changes fetched before it. Pending changes are kept without duplicates, and changes that failed recoverably stay in the list.
4. *Doc.* `CKSyncEngine`, "Accounts", and `Event.AccountChange`. The engine watches the account. With no account, or with sync turned off in Settings, it stays dormant. When the account changes it resets its state, pending changes included, and reports a sign-in, a sign-out or a switch with the user record ids. Changes made while the app was not running arrive as one event.
5. *Doc.* `Event.AccountChange`. Apple's advice is to delete the previous account's local data on a sign-out and on a switch, and at a sign-in to keep local data apart, merge it, delete it, or ask.
6. *Doc.* `CKDatabase.DatabaseChange.Deletion.Reason` and `CKSyncEngineZoneDeletionReason`. A zone's deletion comes with a reason: deleted, purged by the person in Settings, or lost in a reset of the person's encrypted data.
7. *Doc.* The same pages and the article "Encrypting User Data". For a purge: delete the local data and do not send it again; the article says to ask the person first. For an encryption reset Apple's pages disagree: the article, the Swift reference and the older fetch operation say to send the local data again, and the note on the engine's own deletion reason in the 27 SDK says to delete it and not to send it again.
8. *Doc.* `CKSyncEngine` and `CKError`. The engine itself retries network failures, rate limits, a busy zone, an unavailable service, a missing sign-in and a temporarily unavailable account. Other errors are left to the app.
9. *Doc.* `CKError.Code.serverRecordChanged`, `CKRecord`, `Event.SentRecordZoneChanges`. A save is refused when the server's record has a newer change tag. The error carries the server's record, the client's record and their ancestor. After a successful save the app keeps the record's system fields, which carry the new tag, for its next save.
10. *Apple, other.* Apple's sample app for the engine (`sample-cloudkit-sync-engine`, which Apple publishes on GitHub) and WWDC23 session 10188, "Sync to iCloud with CKSyncEngine". Zones are saved before records. A refused save is resolved and queued again. A missing zone is created and the save queued again. A record the server does not know is uploaded again. The sample has no code that registers for pushes.
11. *Doc.* `CKSyncEngineDelegate` and `CKSyncEngine`. Events arrive one at a time. The delegate does not call the engine's fetch or send from inside a callback, and the framework stops an app that does. Production allows one engine per database; development allows several, for tests. The engine is to be created early in the launch.
12. *Doc.* `CKRecord`, `CKError.Code.limitExceeded`, technote TN3164. A record holds at most 1 MB. The engine's documentation gives 250 records per request; another Apple page gives 400 items and 2 MB. A container holds at most 1,000 zones.
13. *Doc.* `CKContainer`, `CKError.Code.quotaExceeded`. The private database counts against the person's iCloud storage. When it is full, saves fail, and the app is to point the person to their storage settings.
14. *Apple, other.* WWDC23 session 10188. In normal conditions a change syncs within seconds. Without a network or with a low battery it waits.
15. *Doc.* "Pushing background updates to your App", `NSApplicationDelegate`, "Configuring background execution modes". On iPhone and iPad a silent push can start or wake the app in the background, with low priority, possibly throttled, and not after the person force-quit the app. A Mac app receives pushes only while it runs, and macOS has no background modes.
16. *Apple, other.* Developer Forums thread 756315 (an Apple engineer, June 2024). On the Mac, CloudKit syncing mostly when the app comes to the front is as designed.
17. *Reports.* Developers who shipped the engine, in published notes of 2026 and in Developer Forums threads 771941 and 774014. A save refused for a full quota drops out of the pending list. A device's own changes sometimes come back as fetched changes. The state must be saved only after the fetched changes are safely stored. An engine created without saved state reports a sign-in. One developer saw a fetch from nothing replay the zone's history, deletions included; see [50].
18. *Not documented.* What the engine does with a state restored from a backup, or with an expired change token. Its save policy, which only an engineer's answer names; see [49]. Whether it registers for pushes by itself. What it reports when only the app's iCloud switch is turned off. Whether an engine created without saved state clears changes that were queued before it reported the account.
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
35. *Doc.* UIKit, "Encrypting Your App's Files", and the Apple Platform Security guide. On iPhone and iPad an app's files are by default protected until the first unlock after a restart. On a Mac the volume's encryption protects them.
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

49. *Apple, other, and Reports.* Developer Forums thread 782333 (April 2025). An Apple engineer: the engine saves with the policy that refuses a save when the server's record has changed. The developer in that thread: a new record under an id that already exists is refused in the same way, with the server's record attached. An older report, thread 125786 (2019), describes such a refusal that carried no record. Apple's documentation describes the refusal for an old tag, and not for a record without a tag.
50. *Apple, other, and Reports.* Developer Forums threads 813286 and 813992 (Apple engineers, early 2026). A fetch from nothing returns every record the server has, which an app can use to build its local cache again. It returns a deletion only for a record that the fetching device itself created, or that was deleted while the fetch ran. A developer in the second thread saw tens of thousands of deletions arrive on a new device. A 2018 paper by Apple's CloudKit team says that old deletions are discarded once all recently active devices have seen them, that a device away for longer has to sync again from the start, and that creating a zone again makes the tokens for the old one invalid. Apple publishes no time span.
51. *Doc.* UIKit, "Extending your app's background execution time". An app that has to finish work as it moves to the background begins a background task before it starts the work. `CKError.Code.serverResponseLost`: a save whose answer was lost may be sent again if doing it twice does no harm. *Not documented:* asking the engine to send at that moment, what becomes of a send that is under way when the app is suspended, and whether the engine sends such a save again by itself.
52. *Apple, other.* The tests in Apple's sample for the engine [10]. After a record was deleted, a save under the same name with the old system fields fails because the server does not know the record, and a save without them succeeds as a new record.
53. *Not documented.* The CloudKit framework in macOS 27.3 contains names that suggest the engine schedules a fetch when the app becomes active. No documentation says so.
