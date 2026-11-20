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
    /// The ids of the plays the devices began, each made by the seeded generator, so that an order of events replays.
    var playIDs: Set<UUID> = []

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

    /// The device was restored from a backup: what it knows of purges is the backup's.
    func restored(device: String) {
        purged[device] = nil
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

    // MARK: The ledger of plays (failures 1 and 3)

    /// A counter that orders what the ledger notes.
    private var ledgerMoment = 0
    /// When each play was last finished on a device.
    private var finishedAt: [String: Int] = [:]
    /// When a clearing last took each play away: the clearing device showed it.
    private var clearedAt: [String: Int] = [:]
    /// When a clearing took a play away while a device held its own finish of that play, unsent. On another device,
    /// that finish comes back if it is sent before the record reaches that device, and goes with the clearing if it is
    /// not. On the clearing device, the unsent entry is removed and no deletion is sent, so a copy that another device
    /// finished and sent stays in iCloud (section 7, rules 1 and 7).
    private var clearedWhileUnsent: [String: Int] = [:]
    /// The plays the other devices hold unsent than the one named: their own finishes, which iCloud never had, and which
    /// a clearing elsewhere does not reach (section 7, an arriving deletion leaves an unsent play alone).
    var unsentElsewhere: (String) -> Set<String> = { _ in [] }
    /// When a device last lost each play with data the design lets go: in a purge it was told of, or, while the play
    /// had not reached iCloud, with another account's data, a backup brought back, or an app that was deleted.
    private var lostAt: [String: Int] = [:]
    /// When the app's data was last deleted from iCloud.
    private var purgedAt = 0

    func finished(play name: String) {
        ledgerMoment += 1
        finishedAt[name] = ledgerMoment
    }

    func cleared(plays: Set<String>, on device: String, unsentThere: Set<String>) {
        ledgerMoment += 1
        let unsent = unsentElsewhere(device).union(unsentThere)
        for name in plays {
            clearedAt[name] = ledgerMoment
            if unsent.contains(name) { clearedWhileUnsent[name] = ledgerMoment }
        }
    }

    func lost(plays: Set<String>) {
        ledgerMoment += 1
        for name in plays { lostAt[name] = ledgerMoment }
    }

    func purgedInICloud() {
        ledgerMoment += 1
        purgedAt = ledgerMoment
    }

    /// A zone went with its records, by a reset of the encrypted data or without a reason anyone is told: the devices
    /// bring what they hold into the next zone, and what only iCloud held, `keeping` aside, is lost (section 9).
    func lostInICloud(keeping held: Set<String>) {
        lost(plays: Set(finishedAt.keys).subtracting(held))
    }

    /// The plays `account`'s iCloud lacks at the end, of those `inICloud` names: finished under that account, never
    /// cleared, and since their last finish not lost with data the design lets go, nor deleted with the app's data. A
    /// play that was cleared once is not counted even when a device finishes it again, as a device that held the same
    /// play in progress does: a deletion queued by the clearing removes the record of that play whenever it lands.
    func playsLost(account: String, inICloud: Set<String>) -> [String] {
        finishedAt.compactMap { name, finished in
            guard owner[name] == account, !inICloud.contains(name), finished > purgedAt, clearedAt[name] == nil,
                  finished > lostAt[name] ?? 0 else { return nil }
            return name
        }.sorted()
    }

    /// The plays a clearing took away, not finished again since, that `inICloud` names; but not one that a device held
    /// unsent at the last clearing.
    func clearedPlaysBack(inICloud: Set<String>) -> [String] {
        clearedAt.compactMap { name, cleared in
            inICloud.contains(name) && (finishedAt[name] ?? 0) < cleared && clearedWhileUnsent[name] != cleared ? name : nil
        }.sorted()
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
    /// The zones reports have named to this device as deleted.
    private(set) var zonesToldDeleted: Set<String> = []
    /// Whether a result said that the held toy changed: the app looks at it again a moment later.
    private(set) var wantsToLookAtTheHeldToy = false
    /// Whether the app keeps background time, as it left the front while the gate waited.
    private(set) var keepsBackgroundTime = false
    /// Whether the last answer about the toy was a refusal without iCloud's record: the case the design accepts when no
    /// fetch brings the toy (section 16).
    private(set) var toyRefusedWithoutRecord = false
    /// Whether, in this run, fetched changes were applied before the account was confirmed, and then removed with another
    /// account's data: the case the design accepts, in which the device lacks them until its engine next starts from
    /// nothing (section 16).
    private(set) var lostFetchedChangesWithAnotherAccount = false
    private var appliedChangesBeforeConfirmation = false
    /// The records this device's engine fetched, since it last started from nothing, that the device did not apply: of a
    /// zone other than the one it used, or of a play it had cleared. Two cases the design accepts leave the device
    /// without such records until its engine next starts from nothing (section 16): it joins a zone whose records its
    /// engine had fetched while it used another, or a play it cleared comes back and its deletion is answered afterwards.
    private(set) var recordsNotApplied: Set<RecordID> = []
    /// The plays the history showed at the last look, to tell which leave it, and why.
    private var shownPlays: Set<UUID> = []
    /// Why shown plays may leave the history during the event under way.
    private var leaving = Leaving.none
    /// The zone note when the latest fetch began.
    private var noteWhenFetchBegan: ZoneNote?
    /// Where a trace of every call goes, for a test that looks into one order of events.
    var trace: ((String) -> Void)?
    /// Whether the next write of fetched records fails, as a full disk would make it fail (section 10).
    var failsNextWriteOfFetchedChanges = false
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
        container = try RecordStore.syncContainer(in: .memory)
        if let backup { try Backup.copy(from: backup, into: container) }
        launch()
    }

    /// The device is restored from `backup`, a copy of a store, and the app starts again.
    func restore(from backup: ModelContainer) throws {
        engine.delegate = nil
        lookAtShownPlays()
        watcher.lost(plays: playsICloudLacks)
        watcher.restored(device: name)
        cloud.forgetOwnChanges(device: name)
        try Backup.copy(from: backup, into: container)
        let outer = leaving
        leaving = .any
        launch()
        lookAtShownPlays()
        leaving = outer
    }

    /// A copy of the device's store, as a device backup keeps it.
    func backUp() throws -> ModelContainer {
        let copy = try RecordStore.syncContainer(in: .memory)
        try Backup.copy(from: container, into: copy)
        return copy
    }

    // MARK: The app

    /// The app starts: the rules over the store, the toy from it, and an engine from the state saved last; then it asks
    /// for the account's id and a fetch. As the app's launch row says, the toy is not kept until it next changes.
    func launch() {
        sync = ICloudSync(
            store: RecordStore(container: container), madeOn: kind, appVersion: "2.0",
            makeID: { [random] in random.uuid() }, freshToy: { [unowned self] in seeded(PlayState()).snapshot }
        )
        if let kept = must({ try sync.toy() }) ?? nil, let restored = PlayState(kept) {
            play = restored
        } else {
            play = PlayState()
        }
        seedPlayID()
        let saved = must { try sync.engineState() } ?? nil
        wantsAccount = false
        wantsFetch = false
        wantsSend = false
        wantsToLookAtTheHeldToy = false
        keepsBackgroundTime = false
        appliedChangesBeforeConfirmation = false
        lostFetchedChangesWithAnotherAccount = false
        if saved == nil, account != nil { watcher.tally.count("start from nothing at launch") }
        trace?("\(name) launches, signed in to \(account ?? "none"), the engine's saved account \(saved.flatMap { try? JSONDecoder().decode(StandInEngine.State.self, from: $0) }.map { $0.account ?? "none" } ?? "no saved state")")
        let launched = must { try sync.launched(engineStartsFromNothing: saved == nil) }
        engine = StandInEngine(cloud: cloud, device: name, savedState: saved, account: account, choices: engineChoices, seed: random.next())
        engine.isOnline = isOnline
        engine.delegate = self
        apply(launched)
    }

    /// The app ends without warning and starts again: what was not saved is gone.
    func relaunch() {
        engine.delegate = nil
        launch()
    }

    /// The engine cannot go on from its saved state: the app discards it, and the next launch is a start from nothing.
    func discardEngineState() {
        must { try sync.discardEngineState() }
        recordsNotApplied = []
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
    ///
    /// It takes them in any order: CloudKit's first answer about the account may take longer than a fetch (source 58).
    @discardableResult
    func doWhatWasAsked() -> Bool {
        var asked: [() -> Void] = []
        if wantsAccount { asked.append(answerAccountQuestion) }
        if wantsFetch { asked.append(requestFetch) }
        if wantsSend {
            asked.append { [self] in
                wantsSend = false
                engineSends()
            }
        }
        if wantsToLookAtTheHeldToy {
            // The moment is not always calm: a move may be playing, or the lesson open.
            asked.append { [self] in
                wantsToLookAtTheHeldToy = false
                if random.chance(0.7) { calmMoment() }
            }
        }
        guard !asked.isEmpty else { return false }
        random.pick(asked)()
        return true
    }

    /// The app asks CloudKit for the account's id, and hands the answer to the rules.
    func answerAccountQuestion() {
        wantsAccount = false
        let answer: AccountAnswer
        if !isOnline || random.chance(accountQuestionFails) {
            // `userRecordID()` fails without a network.
            answer = .failed
        } else if let account {
            answer = .account(account)
        } else {
            answer = .noAccount
        }
        trace?("\(name) asks for the account: \(answer)")
        let named: String? = if case .account(let account) = answer { account } else { nil }
        namingAccount(named) {
            let result = must { try sync.accountAnswered(answer) }
            if result?.replacedToy != nil, appliedChangesBeforeConfirmation { lostFetchedChangesWithAnotherAccount = true }
            apply(result)
        }
    }

    /// The app asks the engine to fetch, as one request.
    func requestFetch() {
        wantsFetch = false
        let request = sync.fetchWillBeRequested()
        let outcome = engine.fetch(manual: true)
        var userDeleted: [String] = []
        if case .zones(let errors)? = outcome.error {
            userDeleted = errors.filter { $0.value == .zoneGone(.userDeletedZone) }.map(\.key)
        }
        watchingPurges(userDeleted: userDeleted, inFetch: true) {
            apply(must {
                try sync.fetchRequestReturned(request, error: outcome.error, pendingZoneSaves: Set(engine.state.pendingZoneSaves))
            })
        }
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
        apply(must { try sync.keep(play.snapshot, at: clock.tick()) })
    }

    /// The play in progress is finished, and every ring goes back on for the next.
    func finishPlay() {
        guard let current = play.play else { return }
        let finished = current.finished(in: play.own.state, at: clock.tick())
        // A play is recorded once on a device: a store that holds its id already keeps what it holds.
        let isNew = (must { try sync.store.plays([finished.playID]) } ?? [:]).isEmpty
        apply(must { try sync.finished(finished) })
        if isNew { watcher.finished(play: finished.playID.uuidString) }
        trace?("\(name) finished the play \(finished.playID.uuidString.prefix(8)), noted \(notedAccount ?? "none")")
        noteOwnership()
        let before = play.snapshot
        play.reset()
        playToRest()
        personChanged(from: before)
    }

    func clearHistory() {
        watcher.cleared(plays: Set(shownPlayIDs.map(\.uuidString)), on: name, unsentThere: playsNeverSent)
        trace?("\(name) clears \(shownPlayIDs.map { $0.uuidString.prefix(8) }.sorted())")
        allowingLeaving(.any) { apply(must { try sync.clearHistory() }) }
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
        if let trace {
            switch event {
            case .stateUpdate: break
            case .fetched(let changes):
                trace("\(name) fetched \(changes.records.map { "\($0.zone?.prefix(14) ?? "-")/\($0.name.prefix(6))" }) deletions \(changes.deletions.map { "\($0.id.zone.prefix(14))/\($0.id.name.prefix(6))" })")
            case .sent(let changes):
                trace("\(name) sent: saved \(changes.saved.map { "\($0.zone?.prefix(14) ?? "-")/\($0.name.prefix(6))" }) failed \(changes.failedSaves.map { "\($0.id.zone.prefix(14))/\($0.id.name.prefix(6)) \($0.reason)".prefix(80) }) deleted \(changes.deleted.count)")
            default: trace("\(name) event \(event)".prefix(400).description)
            }
        }
        switch event {
        case .stateUpdate(let state):
            must { try sync.engineStateUpdated(state) }
        case .accountChange(let change):
            switch change {
            case .signIn: watcher.tally.count("engine reported a sign-in")
            case .signOut: watcher.tally.count("engine reported a sign-out")
            case .switchAccounts: watcher.tally.count("engine reported a switch")
            }
            let named: String? = switch change {
            case .signIn(let account), .switchAccounts(_, let account): account
            case .signOut: nil
            }
            namingAccount(named) {
                let removed = must { try sync.accountChanged(change) }
                if removed?.replacedToy != nil, appliedChangesBeforeConfirmation { lostFetchedChangesWithAnotherAccount = true }
                apply(removed)
            }
            noteOwnership()
        case .willFetch(let manual):
            noteWhenFetchBegan = zoneNote
            // A fetch from nothing brings every record again.
            if engine.state.databaseToken == nil { recordsNotApplied = [] }
            sync.fetchBegan(manual: manual)
        case .databaseChanged(let changes):
            if !sync.run.accountConfirmed { appliedChangesBeforeConfirmation = true }
            zonesToldDeleted.formUnion(changes.deleted.map(\.zone))
            watchingPurges(deleted: changes.deleted) { apply(must { try sync.databaseChanged(changes) }) }
        case .fetched(let changes):
            for record in changes.records where record.type == CloudRecord.finishedPlayType {
                watcher.received(play: record.name, on: name)
            }
            let before = toySide
            if !sync.run.accountConfirmed { appliedChangesBeforeConfirmation = true }
            let used = zoneNote.flatMap { $0.knowledge == .deleted ? nil : $0.zone.name }
            let entries = must { try sync.store.plays(changes.records.compactMap(\.playID)) } ?? [:]
            for record in changes.records {
                guard let zone = record.zone, let id = record.playID else { continue }
                if zone != used || entries[id]?.sync == .cleared { recordsNotApplied.insert(RecordID(zone: zone, name: record.name)) }
            }
            if changes.records.contains(where: \.isToy) { toyRefusedWithoutRecord = false }
            let writeFails = failsNextWriteOfFetchedChanges && !sync.run.writeFailed
            if writeFails {
                failsNextWriteOfFetchedChanges = false
                sync.store.failsNextSyncSave = true
                expectsAFailedWrite = true
            }
            allowingLeaving(.these(Set(changes.deletions.compactMap(\.id.playID)))) { apply(must { try sync.fetched(changes) }) }
            if writeFails {
                // A write that changed nothing did not fail: the failure goes to no later save.
                if sync.run.writeFailed { watcher.tally.count("a write of fetched changes failed") }
                sync.store.failsNextSyncSave = false
                expectsAFailedWrite = false
            }
            tallyToy(before, toySide, arrived: changes.records.contains(where: \.isToy))
            watcher.tally.count("play arrived", changes.records.count { $0.type == CloudRecord.finishedPlayType })
            watcher.tally.count("deletion arrived", changes.deletions.count)
            noteOwnership()
        case .zoneFetchEnded(let zone, let error):
            if error != nil { watcher.tally.count("zone's fetch ended with an error") }
            watchingPurges(userDeleted: error == .zoneGone(.userDeletedZone) ? [zone] : [], inFetch: true) {
                apply(must { try sync.zoneFetchEnded(zone: zone, error: error) })
            }
        case .didFetch(let manual):
            apply(must { try sync.fetchEnded(manual: manual) })
        case .sentZones(let changes):
            watcher.tally.count("zone created", changes.saved.count)
            apply(must { try sync.zonesSent(changes) })
        case .sent(let changes):
            let before = toySide
            let userDeleted = changes.failedSaves.filter { $0.reason == .zoneGone(.userDeletedZone) }.map(\.id.zone)
                + changes.failedDeletions.filter { $0.reason == .zoneGone(.userDeletedZone) }.map(\.id.zone)
            let refusedAsUnknown = Set(changes.failedSaves.filter { $0.reason == .unknownItem }.compactMap(\.id.playID))
            watchingPurges(userDeleted: userDeleted, alsoLeaving: refusedAsUnknown) { apply(must { try sync.sent(changes) }) }
            let toyRefused = changes.failedSaves.contains { failure in
                if case .refused(let record) = failure.reason { failure.id.isToy && record != nil } else { false }
            }
            let toyRefusedBare = changes.failedSaves.contains { failure in
                if case .refused(let record) = failure.reason { failure.id.isToy && record == nil } else { false }
            }
            if toyRefusedBare {
                toyRefusedWithoutRecord = true
            } else if toyRefused || changes.saved.contains(where: \.isToy) {
                toyRefusedWithoutRecord = false
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

    /// Whether the engine has fetched everything iCloud holds for its account, or cannot: it is offline or signed out.
    var isUpToDate: Bool {
        guard isOnline, let account, engine.state.account == account else { return true }
        return engine.state.databaseToken == cloud.database(account).seq && engine.state.zonesToFetch.isEmpty
    }

    /// Whether the device has nothing more to do but wait: its engine is up to date, and its account is confirmed in this
    /// run, unless it has none or CloudKit's answer always fails.
    var isSettled: Bool {
        isUpToDate && (account == nil || sync.run.accountConfirmed || accountQuestionFails >= 1)
    }

    /// Whether the store marks anything as not yet received by iCloud.
    var hasMarks: Bool { marksPlays || toySide.isChanged }

    /// Whether the store marks a play as not yet received by iCloud.
    var marksPlays: Bool {
        guard let plays = must({ try sync.store.playsNotInICloud() }) else { return true }
        return !plays.isEmpty
    }

    // MARK: Inside

    /// Runs `body`, an event or an answer, and tells the watcher of a purge the device was told of: a deletion with the
    /// reason *purged* or *deleted* that counts for it by section 9's rule (a zone higher than its note's, or its note's
    /// zone while not yet marked deleted), or `userDeletedZone` for the zone it uses. The watcher learns of it from what
    /// the device was told, not from what the rules made of it; and in a fetch, also from iCloud's side: an error for the
    /// zone the device used when the fetch began tells it of that zone's purge, even after it joined another. Shown plays
    /// may leave the history for a purge it was told of, and for a save in `alsoLeaving` refused as unknown.
    private func watchingPurges(
        deleted: [ZoneDeletion] = [], userDeleted zones: [String] = [], inFetch: Bool = false,
        alsoLeaving: Set<UUID> = [], _ body: () -> Void
    ) {
        let plays = Set((must { try sync.store.allPlays() } ?? []).map(\.playID.uuidString))
        let toy = play.snapshot
        let note = zoneNote
        var told = false
        // After a failed write of fetched changes the rules take nothing more from the engine in that run, and the
        // engine's state is not saved, so that the next launch hears the same again (section 10).
        if let note, !sync.run.writeFailed {
            told = deleted.contains { deletion in
                guard deletion.reason != .encryptedDataReset, let zone = ZoneName(deletion.zone) else { return false }
                return zone > note.zone || (zone == note.zone && note.knowledge != .deleted)
            }
            told = told || (note.knowledge != .deleted && zones.contains(note.zone.name))
        }
        var toldByTheFetchsZone: ZoneName?
        if !told, inFetch, !sync.run.writeFailed, let began = noteWhenFetchBegan, began.knowledge != .deleted, zones.contains(began.zone.name),
           !(note?.zone == began.zone && note?.knowledge == .deleted) {
            toldByTheFetchsZone = began.zone
        }
        allowingLeaving(told || toldByTheFetchsZone != nil ? .any : .these(alsoLeaving), body)
        if let began = toldByTheFetchsZone, let now = zoneNote, now.zone > began {
            // Accepted (section 16, open point 15): a purge met only as an error of the zone the device used, after it
            // joined the next zone in the same fetch, whatever became of that zone since. It brings the purged data back.
            watcher.tally.count("accepted: a purge met only as an error after joining the next zone")
            trace?("\(name) met a purge of \(began.number) only as an error after joining \(now.zone.number)")
        } else if told || toldByTheFetchsZone != nil {
            watcher.tally.count("purge handled")
            trace?("\(name) was told of a purge\(toldByTheFetchsZone != nil ? " by the fetch's zone" : ""), holding \(plays.map { $0.prefix(8) }.sorted())")
            watcher.handledPurge(on: name, plays: plays, toy: toy)
            // Accepted (section 16): a device played on before it heard of the purge removes those plays too.
            watcher.lost(plays: plays)
        }
    }

    /// Runs `body`, a report of the engine's or an answer of CloudKit's that names `account`. When the store's data
    /// belongs to another account, the account table removes it: shown plays may leave the history, and those that had
    /// not reached iCloud are lost.
    private func namingAccount(_ account: String?, _ body: () -> Void) {
        guard let account, let noted = notedAccount, noted != account else {
            body()
            return
        }
        let unsent = playsICloudLacks
        allowingLeaving(.any, body)
        if notedAccount == account {
            watcher.lost(plays: unsent)
            trace?("\(name) lost \(unsent.map { $0.prefix(8) }.sorted()) with \(noted)'s data")
        }
    }

    /// Why shown plays may leave the history: for no cause, for a few named ones, or for any.
    private enum Leaving {
        case none
        case these(Set<UUID>)
        case any
    }

    /// Runs `body`, during which shown plays may leave the history for `cause`, and looks at the history before and
    /// after.
    private func allowingLeaving(_ cause: Leaving, _ body: () -> Void) {
        lookAtShownPlays()
        let outer = leaving
        leaving = switch (outer, cause) {
        case (.any, _), (_, .any): .any
        case (.these(let a), .these(let b)): .these(a.union(b))
        case (.none, let cause): cause
        case (let outer, .none): outer
        }
        body()
        lookAtShownPlays()
        leaving = outer
    }

    /// Tells the watcher of the plays that left the history since the last look without a cause the design names: a
    /// clearing here, a purge this device was told of, a deletion that arrived, a save refused as unknown, another
    /// account's data, or a backup brought back (failure 5, and failures 1 and 3 on one device).
    private func lookAtShownPlays() {
        let now = shownPlayIDs
        let left = shownPlays.subtracting(now)
        shownPlays = now
        guard !left.isEmpty else { return }
        switch leaving {
        case .any: return
        case .these(let allowed) where left.isSubset(of: allowed): return
        case .these, .none: watcher.note("\(name): \(left.count) shown plays left the history with no cause the design names")
        }
    }

    /// The plays the history shows, readable or not.
    private var shownPlayIDs: Set<UUID> {
        Set((must { try sync.store.allPlays() } ?? []).filter { $0.sync != .cleared }.map(\.playID))
    }

    /// Every play the store holds, cleared or not.
    var playsHeld: Set<String> {
        Set((must { try sync.store.allPlays() } ?? []).map(\.playID.uuidString))
    }

    /// The plays finished here and never handed over.
    var playsNeverSent: Set<String> {
        Set((must { try sync.store.allPlays() } ?? []).filter { $0.sync == .unsent }.map(\.playID.uuidString))
    }

    /// The plays held here that iCloud lacks, in every zone of the account the store's data belongs to: what goes when
    /// the store's data goes. The store's own marks can be behind iCloud, as after a reset it has not heard of.
    var playsICloudLacks: Set<String> {
        guard let account = notedAccount else { return playsHeld }
        let inICloud = cloud.zoneNames(account: account).reduce(into: Set<String>()) { names, zone in
            names.formUnion(cloud.records(zone: zone, account: account).compactMap { $0.playID?.uuidString })
        }
        return playsHeld.subtracting(inICloud)
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

    /// Gives a play that the toy began by itself, under an id from the system's generator, an id from the seeded one, so
    /// that an order of events replays from its seed.
    private func seedPlayID() {
        play = seeded(play)
    }

    /// `state`, with a play the toy began by itself given an id from the seeded generator.
    private func seeded(_ state: PlayState) -> PlayState {
        guard let current = state.play, !watcher.playIDs.contains(current.id) else { return state }
        var snapshot = state.snapshot
        let id = random.uuid()
        snapshot.play?.id = id
        watcher.playIDs.insert(id)
        return PlayState(snapshot) ?? state
    }

    private func playToRest() {
        var steps = 0
        while play.toy.isPlaying, steps < 1_000 {
            play.advance(by: 10)
            steps += 1
        }
        if play.isCongratulating { play.dismissCongratulation() }
    }

    /// The move ended: the app keeps the toy first, and only then judges the moment, which is calm, so that a held toy
    /// still waiting to be taken up is taken up, and one the move turned into an offer is not.
    private func personChanged(from before: ToySnapshot) {
        seedPlayID()
        watcher.personChanged(from: before, to: play.snapshot, account: notedAccount)
        apply(must { try sync.keep(play.snapshot, at: clock.tick()) })
        calmMoment()
    }

    /// Shows `toy`, as the app does after a take-up, a choice, or a toy put back.
    private func show(_ toy: ToySnapshot) {
        if !play.takeUp(toy) { play = PlayState(toy) ?? PlayState() }
        seedPlayID()
        apply(must { try sync.keep(play.snapshot, at: clock.now) })
    }

    private func apply(_ result: SyncResult?) {
        guard let result else { return }
        if let trace, result != SyncResult() {
            trace("  -> \(name) note=\(zoneNote.map { "\($0.zone.number)-\($0.zone.id.prefix(4)) \($0.knowledge)" } ?? "none") plays=\(history.plays.count) \(result.engine.withdrawsEverything ? "withdrawAll " : "")\(result.engine.withdrawsEverythingOutside.map { "withdrawOutside \($0.prefix(14)) " } ?? "")\(result.engine.savesZone.map { "saveZone \($0.prefix(14)) " } ?? "")saves \(result.engine.saves.count) dels \(result.engine.deletions.count)\(result.engine.fetches ? " fetch" : "")\(result.engine.asksForAccount ? " account?" : "")\(result.replacedToy != nil ? " replacedToy" : "")")
        }
        apply(result.engine)
        if let toy = result.replacedToy {
            play = PlayState(toy) ?? PlayState()
        }
        if result.changesHeldToy { wantsToLookAtTheHeldToy = true }
        if result.keepsBackgroundTime { keepsBackgroundTime = true }
        if result.endsBackgroundTime { keepsBackgroundTime = false }
        lookAtShownPlays()
    }

    private func apply(_ requests: EngineRequests?) {
        guard let requests else { return }
        engine?.apply(requests)
        if requests.asksForAccount { wantsAccount = true }
        if requests.fetches { wantsFetch = true }
        if requests.sendsNow { wantsSend = true }
    }

    /// Whether a call may throw because the store failed a write on purpose (``RecordStore/failsNextSyncSave``).
    var expectsAFailedWrite = false

    /// Runs `body`; a throw is a test failure, and gives nil.
    @discardableResult
    private func must<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            if expectsAFailedWrite, (error as? CocoaError)?.code == .fileWriteOutOfSpace {
                expectsAFailedWrite = false
                return nil
            }
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
        // Contexts of their own that never save by themselves, as the rules' own: the containers' main contexts are
        // left alone, so that no autosave of theirs meets the rules' saves.
        let from = ModelContext(source)
        let into = ModelContext(target)
        from.autosaveEnabled = false
        into.autosaveEnabled = false
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
