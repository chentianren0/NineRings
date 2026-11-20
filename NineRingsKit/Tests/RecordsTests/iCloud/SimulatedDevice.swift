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
/// toy and the version it was made from, every toy the person chose to drop, and every record a device sends after a
/// purge.
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

    static func version(_ toy: ToySnapshot) -> Version {
        var copy = toy
        copy.play?.secondsSpent = 0
        return (try? copy.encoded()) ?? Data()
    }

    func personChanged(from old: ToySnapshot, to new: ToySnapshot) {
        guard !old.isSameToy(as: new) else { return }
        madeFrom[Self.version(new), default: []].insert(Self.version(old))
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

    // MARK: The third check: nothing is sent after a purge

    func handledPurge(on device: String, plays: Set<String>, toy: ToySnapshot) {
        var held = purged[device] ?? ([], [])
        held.plays.formUnion(plays)
        held.toys.insert(Self.version(toy))
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
           held.toys.contains(Self.version(payload.toy)), !payload.toy.isUntouched {
            problems.append("\(device) sent the toy it held when it handled a purge")
        }
    }

    func note(_ problem: String) {
        problems.append(problem)
    }
}

/// One simulated device: its own store in memory, its toy as a person plays it, the rules over the store, and a stand-in
/// engine against the stand-in iCloud. It is its engine's delegate, and does what ``ICloudSync`` asks of the app's
/// delegate.
@MainActor
final class SimulatedDevice: StandInEngineDelegate {
    let name: String
    let kind: MadeOn
    let cloud: StandInICloud
    let zone: String
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
    /// What the rules asked of the engine that the app does outside the delegate's callback.
    private(set) var wantsFetch = false
    private(set) var wantsSend = false
    /// Whether the engine is to be offline.
    var isOnline = true {
        didSet { engine.isOnline = isOnline }
    }

    init(
        name: String, kind: MadeOn, cloud: StandInICloud, zone: String = "Plays", account: String?, watcher: Watcher,
        clock: TestClock, random: SharedRandom, engineChoices: StandInEngine.Choices = StandInEngine.Choices(),
        restoredFrom backup: ModelContainer? = nil
    ) throws {
        self.name = name
        self.kind = kind
        self.cloud = cloud
        self.zone = zone
        self.account = account
        self.watcher = watcher
        self.clock = clock
        self.random = random
        self.engineChoices = engineChoices
        container = try RecordStore.deviceContainer(in: .memory)
        if let backup {
            try Backup.copy(from: backup, into: container)
            launch()
        } else {
            launch(first: true)
        }
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

    /// The app starts: the rules over the store, the toy from it, and an engine from the state saved last.
    func launch(first: Bool = false) {
        sync = ICloudSync(
            store: RecordStore(container: container), madeOn: kind, appVersion: "2.0",
            makeStamp: { [random] in random.uuid() }, freshToy: { PlayState().snapshot }
        )
        if let kept = must({ try sync.toy() }) ?? nil, let restored = PlayState(kept) {
            play = restored
        } else {
            play = PlayState()
        }
        if first { must { try sync.keep(play.snapshot, at: clock.now) } }
        let saved = must { try sync.engineState() } ?? nil
        engine = StandInEngine(cloud: cloud, zone: zone, device: name, savedState: saved, choices: engineChoices, seed: random.next())
        engine.isOnline = isOnline
        engine.delegate = self
        wantsFetch = false
        wantsSend = false
        apply(must { try sync.start(engineStartsFromNothing: saved == nil) })
        let reportedSignIn = engine.start()
        if saved == nil, !reportedSignIn, let account {
            // The engine reported no sign-in: the app asks CloudKit for the account's id (open point 14).
            apply(must { try sync.accountChanged(.signIn(account)) })
        }
    }

    /// The app ends without warning and starts again: what was not saved is gone.
    func relaunch() {
        engine.delegate = nil
        launch()
    }

    func sendingMoment() {
        apply(must { try sync.queueToy() })
    }

    func cameToFront() {
        apply(must { try sync.notYetReceived() })
        wantsFetch = true
    }

    func leftFront() {
        apply(must { try sync.queueToy() })
        wantsSend = true
    }

    /// The person signs in to `account`, signs out with nil, or another account signs in.
    func signIn(to account: String?) {
        self.account = account
        engine.accountMayHaveChanged()
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
        apply(must { try sync.record(finished) })
        let before = play.snapshot
        play.reset()
        playToRest()
        personChanged(from: before)
    }

    func clearHistory() {
        apply(must { try sync.clearHistory() })
    }

    /// The person picks the device up: the app comes to the front and fetches, the toy is taken up at the calm moment,
    /// and the person makes a few moves.
    func pickUp(moves: Int) {
        cameToFront()
        engineFetches()
        calmMoment()
        for _ in 0..<moves { move() }
    }

    /// The person puts the device down: the app leaves the front and sends.
    func putDown() {
        leftFront()
        engineSends()
    }

    /// A calm moment: a held toy that waits to be taken up replaces the toy here.
    func calmMoment() {
        guard (must { try sync.heldToy() } ?? nil)?.kind == .toTakeUp else { return }
        let before = play.snapshot
        guard let taken = must({ try sync.takeUpHeldToy() }) ?? nil else { return }
        watcher.tally.count("toy taken up")
        watcher.takenUp(on: name, replacing: before, with: taken)
        watcher.received(toy: taken, on: name)
        show(taken)
    }

    /// Whether the offer line shows.
    var isOffered: Bool { (must { try sync.heldToy() } ?? nil)?.kind == .offered }

    /// The person answers the offer: Keep This One, or Play That One.
    func answerOffer(keepThisOne: Bool) {
        guard isOffered, let held = must({ try sync.store.toySide().heldPayload }) ?? nil else { return }
        watcher.tally.count(keepThisOne ? "kept this one" : "played that one")
        if keepThisOne {
            watcher.chose(toDrop: held.toy)
            apply(must { try sync.keepThisOne() })
        } else {
            watcher.chose(toDrop: play.snapshot)
            guard let taken = must({ try sync.playThatOne() }) ?? nil else { return }
            watcher.received(toy: taken, on: name)
            show(taken)
        }
    }

    // MARK: The engine

    @discardableResult
    func engineSends() -> Bool {
        wantsSend = false
        return engine.send()
    }

    @discardableResult
    func engineFetches() -> Bool {
        wantsFetch = false
        return engine.fetch()
    }

    func deliverLateAnswers() {
        engine.deliverLateAnswers()
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
        case .zoneDeleted(let reason):
            let plays = Set((must { try sync.store.allEntries() } ?? []).map(\.recordName))
            let toy = play.snapshot
            apply(must { try sync.zoneDeleted(reason) })
            if reason != .encryptedDataReset { watcher.handledPurge(on: name, plays: plays, toy: toy) }
        case .fetched(let changes):
            for record in changes.records where record.type == CloudRecord.finishedPlayType {
                watcher.received(play: record.name, on: name)
            }
            let before = toySide
            apply(must { try sync.fetched(changes) })
            tallyToy(before, toySide, arrived: changes.records.contains(where: \.isToy))
            watcher.tally.count("play arrived", changes.records.count { $0.type == CloudRecord.finishedPlayType })
            watcher.tally.count("deletion arrived", changes.deletions.count)
        case .sent(let changes):
            let before = toySide
            apply(must { try sync.sent(changes) })
            let toyRefused = changes.failedSaves.contains { failure in
                if case .refused(let record) = failure.reason { failure.type == CloudRecord.toyType && record != nil } else { false }
            }
            tallyToy(before, toySide, arrived: toyRefused)
            watcher.tally.count("toy accepted", changes.saved.count(where: \.isToy))
            watcher.tally.count("toy refused", changes.failedSaves.count { failure in
                if case .refused = failure.reason { failure.type == CloudRecord.toyType } else { false }
            })
            watcher.tally.count("play accepted", changes.saved.count { $0.type == CloudRecord.finishedPlayType })
            watcher.tally.count("play refused", changes.failedSaves.count { failure in
                if case .refused = failure.reason { failure.type == CloudRecord.finishedPlayType } else { false }
            })
            watcher.tally.count("answer lost", changes.failedSaves.count { $0.reason == .answerLost })
            watcher.tally.count("deletion answered", changes.deleted.count + changes.failedDeletions.count)
        case .fetchFinished:
            apply(must { try sync.fetchFinished() })
        }
    }

    func engine(_ engine: StandInEngine, recordsToSend names: [String]) -> [String: RecordToSend] {
        let records = must { try sync.recordsToSend(named: names) } ?? [:]
        for record in records.values { watcher.sent(record, by: name) }
        return records
    }

    // MARK: Looking

    /// The toy the store keeps.
    var keptToy: ToySnapshot? { must { try sync.store.toySide().toy?.snapshot } ?? nil }

    /// The history as the screen shows it.
    var history: PlayHistory { must { try sync.history() } ?? .empty }

    /// The store's notes about the toy.
    var toySide: ToySide { must { try sync.store.toySide() } ?? ToySide() }

    /// Whether the store marks anything as not yet received by iCloud.
    var hasMarks: Bool {
        guard let marked = must({ try sync.store.notYetReceived(toyIsDue: toySide.isDue) }) else { return true }
        return !marked.saves.isEmpty || !marked.deletions.isEmpty
    }

    // MARK: Inside

    /// Counts what a toy that arrived did to the notes.
    private func tallyToy(_ before: ToySide, _ after: ToySide, arrived: Bool) {
        guard arrived else { return }
        let tally = watcher.tally
        if after.held != nil, after.held != before.held {
            switch after.heldFate {
            case .offered?: tally.count("toy held and offered")
            case .toTakeUp?: tally.count(after.isChanged ? "toy held to take up although marked (case 5)" : "toy held to take up")
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
        watcher.personChanged(from: before, to: play.snapshot)
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
    }

    private func apply(_ requests: EngineRequests?) {
        guard let requests else { return }
        engine.apply(requests)
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

/// A device backup: every model of one store copied into another, as a backup brings the store back.
@MainActor
enum Backup {
    static func copy(from source: ModelContainer, into target: ModelContainer) throws {
        let from = source.mainContext
        let into = target.mainContext
        for play in try into.fetch(FetchDescriptor<FinishedPlay>()) { into.delete(play) }
        for toy in try into.fetch(FetchDescriptor<KeptToy>()) { into.delete(toy) }
        for notes in try into.fetch(FetchDescriptor<SyncNotes>()) { into.delete(notes) }
        for play in try from.fetch(FetchDescriptor<FinishedPlay>()) { into.insert(FinishedPlay.copy(of: play)) }
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
            copy.account = notes.account
            into.insert(copy)
        }
        try into.save()
    }
}
