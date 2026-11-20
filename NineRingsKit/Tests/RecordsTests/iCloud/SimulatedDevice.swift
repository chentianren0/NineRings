import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// A clock the tests turn: one tick for each thing a person does, so that no two moments are alike and none is the
/// device's own.
@MainActor
final class TestClock {
    private var ticks = 0.0
    /// How far this clock is from the others: a device whose clock is wrong.
    var offset: TimeInterval = 0

    var now: Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + ticks + offset) }

    @discardableResult
    func tick() -> Date {
        ticks += 1
        return now
    }
}

/// A seeded random generator that several owners share.
@MainActor
final class SharedRandom {
    var generator: SeededRandom

    init(seed: UInt64) {
        generator = SeededRandom(seed: seed)
    }

    func next() -> UInt64 { generator.next() }
    func uuid() -> UUID { generator.uuid() }
    func chance(_ p: Double) -> Bool { generator.chance(p) }
    func pick<T>(_ choices: [T]) -> T { choices[Int.random(in: 0..<choices.count, using: &generator)] }
    func int(_ range: Range<Int>) -> Int { Int.random(in: range, using: &generator) }
}

/// How often each thing happened across an order of events, to show what the orders reach.
@MainActor
final class Tally {
    private(set) var counts: [String: Int] = [:]

    func count(_ what: String, _ times: Int = 1) {
        guard times > 0 else { return }
        counts[what, default: 0] += times
    }
}

/// What the checks of docs/icloud.md section 14 watch, across every device of an order of events: every version of the
/// toy and the version it was made from, every toy the person chose to drop, every record a device sends after a purge,
/// and whose account each play and each toy belongs to.
@MainActor
final class Watcher {
    /// A toy for the checks: the toy with the time spent on its play left out, since two toys that differ only in that are
    /// the same toy.
    typealias Version = Data

    /// For each version of the toy, the versions it was made from by a person's change.
    private(set) var madeFrom: [Version: Set<Version>] = [:]
    /// The versions a person chose to drop: the other toy kept over, or their own toy given up for the other.
    private(set) var dropped: Set<Version> = []
    /// What broke a check, in words.
    private(set) var problems: [String] = []
    /// How often each thing happened.
    let tally = Tally()
    /// For each device that handled a purge, the plays and the toy it held then and has not received again since.
    private var purged: [String: (plays: Set<String>, toys: Set<Version>)] = [:]
    /// The account each play belongs to: the account of the store it was finished in, or that it came from.
    private var owner: [String: String] = [:]
    /// The account each version of the toy belongs to: the account of the store in which the person made it.
    private var toyOwner: [Version: String] = [:]

    static func version(_ toy: ToySnapshot) -> Version {
        var copy = toy
        copy.play?.secondsSpent = 0
        return (try? copy.encoded()) ?? Data()
    }

    func personChanged(from old: ToySnapshot, to new: ToySnapshot, account: String?) {
        guard !old.isSameToy(as: new) else { return }
        madeFrom[Self.version(new), default: []].insert(Self.version(old))
        if let account, toyOwner[Self.version(new)] == nil { toyOwner[Self.version(new)] = account }
    }

    func chose(toDrop toy: ToySnapshot) {
        dropped.insert(Self.version(toy))
    }

    /// The first check: a toy is replaced only by taking up or by the person's choice. A toy taken up may replace only a
    /// toy with nothing of its own to lose: an untouched one, one the taken toy was made from, or one a person chose to
    /// drop, or made a version that was dropped.
    func takenUp(on device: String, replacing old: ToySnapshot, with new: ToySnapshot) {
        guard !old.isSameToy(as: new), !old.isUntouched else { return }
        let oldVersion = Self.version(old)
        if isMadeFrom(Self.version(new), oldVersion) { return }
        if dropped.contains(where: { isMadeFrom($0, oldVersion) }) { return }
        problems.append("\(device) took a toy up over one with moves of its own that nobody chose to drop")
    }

    /// Whether `version` is `ancestor` or was made from it, through any number of changes.
    func isMadeFrom(_ version: Version, _ ancestor: Version) -> Bool {
        guard version != ancestor else { return true }
        var seen: Set<Version> = [version]
        var next = [version]
        while let current = next.popLast() {
            for parent in madeFrom[current] ?? [] where seen.insert(parent).inserted {
                if parent == ancestor { return true }
                next.append(parent)
            }
        }
        return false
    }

    // MARK: Whose account

    /// A play belongs to `account` from when a store that belongs to it holds it.
    func belongs(play name: String, to account: String) {
        if owner[name] == nil { owner[name] = account }
    }

    /// The fourth check: nothing of one account reaches another account's iCloud. A device hands `record` over for
    /// `account`'s iCloud while its store belongs to `noted`.
    func handedOver(_ record: RecordToSend, by device: String, into account: String, noted: String?) {
        if noted != account {
            problems.append("\(device) handed a record over for \(account)'s iCloud while its data belongs to \(noted ?? "no account")")
        }
        if record.type == CloudRecord.finishedPlayType, let belongs = owner[record.name], belongs != account {
            problems.append("\(device) handed \(belongs)'s play over for \(account)'s iCloud")
        }
        if record.type == CloudRecord.toyType, let payload = ToyPayload(format: record.format, payload: record.payload),
           let belongs = toyOwner[Self.version(payload.toy)], belongs != account {
            problems.append("\(device) handed \(belongs)'s toy over for \(account)'s iCloud")
        }
    }

    // MARK: The third check: nothing a purge removed is sent again

    func handledPurge(on device: String, plays: Set<String>, toy: ToySnapshot) {
        var held = purged[device] ?? ([], [])
        held.plays.formUnion(plays)
        if !toy.isUntouched { held.toys.insert(Self.version(toy)) }
        purged[device] = held
    }

    func received(play name: String, on device: String) {
        purged[device]?.plays.remove(name)
    }

    func received(toy: ToySnapshot, on device: String) {
        purged[device]?.toys.remove(Self.version(toy))
    }

    func sent(_ record: RecordToSend, by device: String) {
        guard let held = purged[device] else { return }
        if record.type == CloudRecord.finishedPlayType, held.plays.contains(record.name) {
            problems.append("\(device) sent a play it held when it handled a purge")
        }
        if record.type == CloudRecord.toyType, let payload = ToyPayload(format: record.format, payload: record.payload),
           held.toys.contains(Self.version(payload.toy)) {
            problems.append("\(device) sent the toy it held when it handled a purge")
        }
    }

    func note(_ problem: String) {
        problems.append(problem)
    }
}

/// One simulated device: its own store in memory, its toy as a person plays it, the rules over the store, and a stand-in
/// engine against the stand-in iCloud. It is its engine's delegate, and does what ``ICloudSync``'s documentation asks of
/// the app's delegate: it translates each event into one call, applies what the call asks of the engine, and does the
/// fetches, the sends and the questions for the account a moment later, outside the engine's callback.
@MainActor
final class SimulatedDevice: StandInEngineDelegate {
    let name: String
    let kind: MadeOn
    let cloud: StandInICloud
    let watcher: Watcher
    let clock: TestClock
    private let random: SharedRandom
    /// The device's disk: it outlives a relaunch.
    let container: ModelContainer
    private(set) var sync: ICloudSync!
    private(set) var engine: StandInEngine!
    /// The toy on screen.
    private(set) var play = PlayState()
    /// The account the device is signed in to.
    private(set) var account: String?
    var engineChoices: StandInEngine.Choices
    /// How often CloudKit's answer to the question for the account's id fails.
    var accountQuestionFails = 0.0
    /// What the rules asked that the app does outside the engine's callback, a moment later.
    private(set) var wantsAccount = false
    private(set) var wantsFetch = false
    private(set) var wantsSend = false
    /// Whether the app keeps background time, as it left the front while the gate waited.
    private(set) var keepsBackgroundTime = false
    /// Whether the engine is to be offline.
    var isOnline = true {
        didSet { engine.isOnline = isOnline }
    }

    init(
        name: String, kind: MadeOn, cloud: StandInICloud, account: String?, watcher: Watcher, clock: TestClock,
        random: SharedRandom, engineChoices: StandInEngine.Choices = StandInEngine.Choices(),
        restoredFrom backup: ModelContainer? = nil
    ) throws {
        self.name = name
        self.kind = kind
        self.cloud = cloud
        self.account = account
        self.watcher = watcher
        self.clock = clock
        self.random = random
        self.engineChoices = engineChoices
        container = try RecordStore.deviceContainer(in: .memory)
        if let backup { try Backup.copy(from: backup, into: container) }
        launch()
    }

    /// The device is restored from `backup`, a copy of a store, and the app starts again.
    func restore(from backup: ModelContainer) throws {
        engine.delegate = nil
        try Backup.copy(from: backup, into: container)
        launch()
    }

    /// A copy of the device's store, as a device backup keeps it.
    func backUp() throws -> ModelContainer {
        let copy = try RecordStore.deviceContainer(in: .memory)
        try Backup.copy(from: container, into: copy)
        return copy
    }

    // MARK: The app

    /// The app starts: the rules over the store, the toy from it, and an engine from the state saved last; then it asks
    /// for the account's id and a fetch.
    func launch() {
        sync = ICloudSync(
            store: RecordStore(container: container), madeOn: kind, appVersion: "2.0",
            makeID: { [random] in random.uuid() }, freshToy: { PlayState().snapshot }
        )
        if let kept = must({ try sync.toy() }) ?? nil, let restored = PlayState(kept) {
            play = restored
        } else {
            play = PlayState()
        }
        must { try sync.keep(play.snapshot, at: clock.now) }
        let saved = must { try sync.engineState() } ?? nil
        wantsAccount = false
        wantsFetch = false
        wantsSend = false
        keepsBackgroundTime = false
        engine = StandInEngine(cloud: cloud, device: name, savedState: saved, account: account, choices: engineChoices, seed: random.next())
        engine.isOnline = isOnline
        engine.delegate = self
        apply(must { try sync.launched(engineStartsFromNothing: saved == nil) })
    }

    /// The app ends without warning and starts again: what was not saved is gone.
    func relaunch() {
        engine.delegate = nil
        launch()
    }

    /// The engine cannot go on from its saved state: the app discards it, and the next launch is a start from nothing.
    func discardEngineState() {
        must { try sync.discardEngineState() }
        relaunch()
    }

    /// The toy changes: the app asks the gate, at most once a minute.
    func toyChanged() {
        apply(must { try sync.toyChanged() })
    }

    func cameToFront() {
        keepsBackgroundTime = false
        apply(must { try sync.cameToFront() })
    }

    func leftFront() {
        apply(must { try sync.leftFront() })
    }

    /// The person signs in to `account`, signs out with nil, or another account signs in, while the app runs.
    func signIn(to account: String?) {
        self.account = account
        engine.accountMayHaveChanged()
    }

    /// The account changes while the app is not running: at the next launch the engine reports it, and CloudKit names it.
    func signInWhileNotRunning(to account: String?) {
        engine.delegate = nil
        self.account = account
        launch()
    }

    // MARK: What the app does outside the engine's callback

    /// The app answers what the rules asked, one thing: the question for the account, a fetch, or a send. Returns whether
    /// it did anything.
    @discardableResult
    func doWhatWasAsked() -> Bool {
        if wantsAccount {
            answerAccountQuestion()
            return true
        }
        if wantsFetch {
            requestFetch()
            return true
        }
        if wantsSend {
            wantsSend = false
            engineSends()
            return true
        }
        return false
    }

    /// The app asks CloudKit for the account's id, and hands the answer to the rules.
    func answerAccountQuestion() {
        wantsAccount = false
        let answer: AccountAnswer
        if random.chance(accountQuestionFails) {
            answer = .failed
        } else if let account {
            answer = .account(account)
        } else {
            answer = .noAccount
        }
        apply(must { try sync.accountAnswered(answer) })
    }

    /// The app asks the engine to fetch, as one request.
    func requestFetch() {
        wantsFetch = false
        let request = sync.fetchWillBeRequested()
        let outcome = engine.fetch(manual: true)
        apply(must {
            try sync.fetchRequestReturned(request, error: outcome.error, pendingZoneSaves: Set(engine.state.pendingZoneSaves))
        })
    }

    /// Everything the rules asked, and every pending change sent, until nothing more is asked.
    func syncFully(limit: Int = 60) {
        for _ in 0..<limit {
            if doWhatWasAsked() { continue }
            if isOnline, account != nil, engine.hasPendingChanges, engineSends() { continue }
            break
        }
    }

    // MARK: The person

    /// The person taps a ring that can move, and the move plays to its end. Ring 1, which can always move, is tapped
    /// more often than the others, so that two devices now and then make the same move from the same toy.
    func move() {
        let rings = play.own.state.movableRings
        guard !rings.isEmpty else { return }
        let before = play.snapshot
        play.tap(random.chance(0.6) ? 1 : random.pick(rings))
        playToRest()
        personChanged(from: before)
    }

    /// The person taps `ring`, or ring 1 when that one cannot move, and the move plays to its end: for a scenario that
    /// needs two devices' toys to differ.
    func move(ring: Int) {
        let before = play.snapshot
        play.tap(play.own.state.canMove(ring) ? ring : 1)
        playToRest()
        personChanged(from: before)
    }

    /// The person takes the last move back.
    func undo() {
        let before = play.snapshot
        play.undo()
        playToRest()
        personChanged(from: before)
    }

    /// Time passes in front of the toy, which changes only the time spent.
    func spendTime() {
        play.spend(Double(random.int(1..<90)))
        must { try sync.keep(play.snapshot, at: clock.tick()) }
    }

    /// The play in progress is finished, and every ring goes back on for the next.
    func finishPlay() {
        guard let current = play.play else { return }
        let finished = current.finished(in: play.own.state, at: clock.tick())
        apply(must { try sync.finished(finished) })
        noteOwnership()
        let before = play.snapshot
        play.reset()
        playToRest()
        personChanged(from: before)
    }

    func clearHistory() {
        apply(must { try sync.clearHistory() })
    }

    /// The person picks the device up: the app comes to the front and syncs, the toy is taken up at the calm moment, and
    /// the person makes a few moves.
    func pickUp(moves: Int) {
        cameToFront()
        syncFully()
        calmMoment()
        for _ in 0..<moves { move() }
        if moves > 0 { toyChanged() }
    }

    /// The person puts the device down: the app leaves the front and sends.
    func putDown() {
        leftFront()
        syncFully()
    }

    /// A calm moment: a held toy that waits to be taken up replaces the toy here.
    func calmMoment() {
        guard (must { try sync.heldToy() } ?? nil)?.kind == .toTakeUp else { return }
        let before = play.snapshot
        guard let result = must({ try sync.takeUpHeldToy() }), let taken = result.replacedToy else { return }
        apply(result.engine)
        watcher.tally.count("toy taken up")
        watcher.takenUp(on: name, replacing: before, with: taken)
        watcher.received(toy: taken, on: name)
        show(taken)
    }

    /// Whether the offer line shows.
    var isOffered: Bool { (must { try sync.heldToy() } ?? nil)?.kind == .offered }

    /// The person answers the offer: Keep This One, or Play That One.
    func answerOffer(keepThisOne: Bool) {
        guard isOffered, let held = toySide.held?.payload else { return }
        watcher.tally.count(keepThisOne ? "kept this one" : "played that one")
        if keepThisOne {
            watcher.chose(toDrop: held.toy)
            apply(must { try sync.keepThisOne() })
        } else {
            watcher.chose(toDrop: play.snapshot)
            guard let result = must({ try sync.playThatOne() }), let taken = result.replacedToy else { return }
            apply(result.engine)
            watcher.received(toy: taken, on: name)
            show(taken)
        }
    }

    // MARK: The engine, by itself

    /// The engine sends by itself, as automatic syncing does.
    @discardableResult
    func engineSends() -> Bool {
        engine.send()
    }

    /// The engine fetches by itself, as automatic syncing does: its fetch delivers changes and never counts.
    func engineFetchesByItself() {
        engine.fetch(manual: false)
    }

    func deliverLateAnswers() {
        engine.deliverLateAnswers()
    }

    /// The engine sends, the changes reach iCloud, and the process ends before any answer is handled; the app starts
    /// again.
    func crashDuringSend() {
        if engine.send(crashesBeforeTheAnswer: true) { watcher.tally.count("crash during a send") }
        relaunch()
    }

    // MARK: The delegate

    var currentAccount: String? { account }

    func engine(_ engine: StandInEngine, handle event: StandInEngine.Event) {
        guard engine === self.engine else { return }
        switch event {
        case .stateUpdate(let state):
            must { try sync.engineStateUpdated(state) }
        case .accountChange(let change):
            apply(must { try sync.accountChanged(change) })
            noteOwnership()
        case .willFetch(let manual):
            sync.fetchBegan(manual: manual)
        case .databaseChanged(let changes):
            watchingPurges { apply(must { try sync.databaseChanged(changes) }) }
        case .fetched(let changes):
            for record in changes.records where record.type == CloudRecord.finishedPlayType {
                watcher.received(play: record.name, on: name)
            }
            let before = toySide
            apply(must { try sync.fetched(changes) })
            tallyToy(before, toySide, arrived: changes.records.contains(where: \.isToy))
            watcher.tally.count("play arrived", changes.records.count { $0.type == CloudRecord.finishedPlayType })
            watcher.tally.count("deletion arrived", changes.deletions.count)
            noteOwnership()
        case .zoneFetchEnded(let zone, let error):
            if error != nil { watcher.tally.count("zone's fetch ended with an error") }
            watchingPurges { apply(must { try sync.zoneFetchEnded(zone: zone, error: error) }) }
        case .didFetch(let manual):
            apply(must { try sync.fetchEnded(manual: manual) })
        case .sentZones(let changes):
            watcher.tally.count("zone created", changes.saved.count)
            apply(must { try sync.zonesSent(changes) })
        case .sent(let changes):
            let before = toySide
            watchingPurges { apply(must { try sync.sent(changes) }) }
            let toyRefused = changes.failedSaves.contains { failure in
                if case .refused(let record) = failure.reason { failure.id.isToy && record != nil } else { false }
            }
            tallyToy(before, toySide, arrived: toyRefused)
            watcher.tally.count("toy accepted", changes.saved.count(where: \.isToy))
            watcher.tally.count("play accepted", changes.saved.count { $0.type == CloudRecord.finishedPlayType })
            watcher.tally.count("save refused as existing", changes.failedSaves.count { if case .refused = $0.reason { true } else { false } })
            watcher.tally.count("save refused as unknown", changes.failedSaves.count { $0.reason == .unknownItem })
            watcher.tally.count("save found the zone gone", changes.failedSaves.count { if case .zoneGone = $0.reason { true } else { false } })
            watcher.tally.count("answer lost", changes.failedSaves.count { $0.reason == .answerLost })
            watcher.tally.count("storage full", changes.failedSaves.count { $0.reason == .storageFull })
            watcher.tally.count("deletion answered", changes.deleted.count + changes.failedDeletions.count)
        }
    }

    func engine(_ engine: StandInEngine, batchFor pending: [PendingChange]) -> Batch {
        let batch = must { try sync.batch(for: pending) } ?? {
            var nothing = Batch()
            nothing.withdrawn = pending
            return nothing
        }()
        let noted = must { try sync.store.existingSyncNotes()?.account } ?? nil
        for record in batch.records {
            watcher.sent(record, by: name)
            if let account = engine.state.account { watcher.handedOver(record, by: name, into: account, noted: noted) }
            if let fields = record.systemFields, let decoded = try? JSONDecoder().decode(StandInICloud.SystemFields.self, from: fields),
               decoded.zone != record.zone {
                watcher.note("\(name) built a record for \(record.zone) from system fields of \(decoded.zone)")
            }
        }
        return batch
    }

    // MARK: Looking

    /// The toy the store keeps.
    var keptToy: ToySnapshot? { must { try sync.store.toySide().toy?.snapshot } ?? nil }

    /// The history as the screen shows it.
    var history: PlayHistory { must { try sync.history() } ?? .empty }

    /// The store's notes about the toy.
    var toySide: ToySide { must { try sync.store.toySide() } ?? ToySide() }

    /// The zone note.
    var zoneNote: ZoneNote? {
        guard let notes = must({ try sync.store.existingSyncNotes() }) ?? nil else { return nil }
        return sync.zoneNote(notes)
    }

    /// The account the store's data belongs to.
    var notedAccount: String? { must { try sync.store.existingSyncNotes()?.account } ?? nil }

    /// Whether the store marks anything as not yet received by iCloud.
    var hasMarks: Bool {
        guard let plays = must({ try sync.store.playsNotInICloud() }) else { return true }
        return !plays.isEmpty || toySide.isChanged
    }

    // MARK: Inside

    /// Runs `body`, an event that may make the device handle a purge, and tells the watcher if it did.
    private func watchingPurges(_ body: () -> Void) {
        let plays = Set((must { try sync.store.allPlays() } ?? []).map(\.playID.uuidString))
        let toy = play.snapshot
        let before = zoneNote
        body()
        if let after = zoneNote, after.knowledge == .deleted, after != before, (must { try sync.store.allPlays() } ?? []).isEmpty,
           keptToy?.isUntouched ?? true {
            watcher.tally.count(plays.isEmpty && toy.isUntouched ? "zone deleted" : "purge handled")
            watcher.handledPurge(on: name, plays: plays, toy: toy)
        } else if let after = zoneNote, after.knowledge == .deleted, after != before {
            watcher.tally.count("zone left, data kept")
        }
    }

    /// Tells the watcher whose account the plays in the store belong to.
    private func noteOwnership() {
        guard let account = notedAccount else { return }
        for entry in must({ try sync.store.allPlays() }) ?? [] { watcher.belongs(play: entry.playID.uuidString, to: account) }
    }

    /// Counts what a toy that arrived did to the notes.
    private func tallyToy(_ before: ToySide, _ after: ToySide, arrived: Bool) {
        guard arrived else { return }
        let tally = watcher.tally
        if after.held != nil, after.held != before.held {
            switch after.held?.kind {
            case .offered?: tally.count("toy held and offered")
            case .toTakeUp?: tally.count(after.isChanged ? "toy held to take up although marked (case 6)" : "toy held to take up")
            default: tally.count("toy held unread")
            }
        } else if after.base != before.base, let stamp = after.base?.stamps.last, before.ownStamps.contains(stamp) {
            tally.count("own send came back")
        } else if after.base != before.base {
            tally.count("same toy arrived")
        } else {
            tally.count("toy arrival changed nothing")
        }
    }

    private func playToRest() {
        var steps = 0
        while play.toy.isPlaying, steps < 1_000 {
            play.advance(by: 10)
            steps += 1
        }
        if play.isCongratulating { play.dismissCongratulation() }
    }

    private func personChanged(from before: ToySnapshot) {
        watcher.personChanged(from: before, to: play.snapshot, account: notedAccount)
        must { try sync.keep(play.snapshot, at: clock.tick()) }
    }

    /// Shows `toy`, as the app does after a take-up, a choice, or a toy put back.
    private func show(_ toy: ToySnapshot) {
        if !play.takeUp(toy) { play = PlayState(toy) ?? PlayState() }
        must { try sync.keep(play.snapshot, at: clock.now) }
    }

    private func apply(_ result: SyncResult?) {
        guard let result else { return }
        apply(result.engine)
        if let toy = result.replacedToy {
            play = PlayState(toy) ?? PlayState()
        }
        if result.keepsBackgroundTime { keepsBackgroundTime = true }
        if result.endsBackgroundTime { keepsBackgroundTime = false }
    }

    private func apply(_ requests: EngineRequests?) {
        guard let requests else { return }
        engine?.apply(requests)
        if requests.asksForAccount { wantsAccount = true }
        if requests.fetches { wantsFetch = true }
        if requests.sendsNow { wantsSend = true }
    }

    /// Runs `body`; a throw is a test failure, and gives nil.
    @discardableResult
    private func must<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            Issue.record(error, "\(name)")
            return nil
        }
    }
}

/// A device backup: every model of the iCloud rules copied from one store into another, as a backup brings the store
/// back.
@MainActor
enum Backup {
    static func copy(from source: ModelContainer, into target: ModelContainer) throws {
        let from = source.mainContext
        let into = target.mainContext
        for play in try into.fetch(FetchDescriptor<KeptPlay>()) { into.delete(play) }
        for toy in try into.fetch(FetchDescriptor<KeptToy>()) { into.delete(toy) }
        for notes in try into.fetch(FetchDescriptor<SyncNotes>()) { into.delete(notes) }
        for play in try from.fetch(FetchDescriptor<KeptPlay>()) {
            let copy = KeptPlay(id: play.playID)
            copy.finishedAt = play.finishedAt
            copy.state = play.state
            copy.format = play.format
            copy.payload = play.payload
            copy.systemFields = play.systemFields
            copy.systemFieldsZone = play.systemFieldsZone
            into.insert(copy)
        }
        for toy in try from.fetch(FetchDescriptor<KeptToy>()) {
            let copy = KeptToy()
            copy.snapshot = toy.snapshot
            copy.format = toy.format
            copy.changedAt = toy.changedAt
            copy.changedOn = toy.changedOn
            copy.isChanged = toy.isChanged
            copy.base = toy.base
            copy.lastSend = toy.lastSend
            copy.ownStamps = toy.ownStamps
            copy.held = toy.held
            into.insert(copy)
        }
        for notes in try from.fetch(FetchDescriptor<SyncNotes>()) {
            let copy = SyncNotes()
            copy.engineState = notes.engineState
            copy.zoneName = notes.zoneName
            copy.zoneKnowledge = notes.zoneKnowledge
            copy.highestNumber = notes.highestNumber
            copy.account = notes.account
            copy.storageFull = notes.storageFull
            into.insert(copy)
        }
        try into.save()
    }
}
