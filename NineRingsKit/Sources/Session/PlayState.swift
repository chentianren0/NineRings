import Motion
import Puzzle

/// The puzzle as the screen plays it: the person's own toy, the lesson when it is open, the congratulation, and what
/// is heard at each change.
///
/// Only here is it known which changes are jumps: Reset, opening and closing the lesson, going to a step, or starting
/// at a chosen move set the toy somewhere at once, under a cover, while a ring tap, play, undo, Solve, a drag or the
/// clock move it on. From the toy alone the two can look the same (a step played again looks like the slider dragged
/// back), so the rules that depend on it live here, where they can be tested, and the app's player only passes its
/// requests on.
///
/// The rules it keeps:
/// - A jump is silent: nothing is heard and the sword's slide hears no travel across it, whatever the toy before and
///   after. Every other change is heard as ``Hearing`` says.
/// - The congratulation follows the person's own toy: their toy when the lesson is closed, and, on the lesson's last
///   step, the toy it gives back. Arriving there, opening and closing the lesson, and going to another step are not
///   moves: they never congratulate, and hide the card. Solve never congratulates (see ``Congratulation``).
/// - What is said aloud follows ``Narration`` for every change that is heard, with these exceptions. A drag of the
///   slider says nothing: the slider says its own value. While the lesson holds the toy nothing is said: the step's
///   text says what the toy shows, and is heard whole. A move whose end congratulates does not say its ring is off:
///   the congratulation says it. Of the jumps, Reset and closing the lesson say what the toy now is; opening the
///   lesson and going to a step say nothing here, since the lesson's panel says the step. The pause before a jump,
///   while the screen covers the toy, says nothing either: what the jump says is the news.
/// - A request that changes nothing, such as going to a step with the lesson closed, is heard and said as nothing:
///   what the last change said is not said again.
/// - The person can set the rings by hand, to any of the 512 arrangements: they lie on one line of moves, so each is a
///   real position of the puzzle, and the rule forbids none. While they set them, a
///   ring asked for goes on or comes off at once, with no move and no rule, and every request that would move the toy
///   does nothing. Their toy waits as it was. Done makes the arrangement their toy, resting there with no move made,
///   so that play, undo and Solve go on from it; Cancel gives their toy back as it was. Every change of the
///   arrangement is a jump, silent, and says nothing: the ring's own button says its new value. Starting says how to
///   set them; Done and Cancel say what the toy now is. The lesson stays closed meanwhile.
/// - The play in progress follows the person's toy, as the congratulation does (see ``Play``): every move, undo and
///   move made by Solve on it counts, and so do the lesson's moves made on it where it is given back. Reset, and
///   setting the rings to every ring on, begin a new play. The change that congratulates finishes the play, and
///   ``finished`` holds its record for that change.
/// - What is kept between launches is the person's own toy, as closing the lesson or cancelling the rings being set
///   would give it back, with the play in progress (``snapshot``).
public struct PlayState: Sendable, Equatable {
    /// The person's own toy. While the lesson is open it waits, and the lesson's toy is shown instead.
    public private(set) var own: PuzzleSession
    /// The lesson, while it is open.
    public private(set) var lesson: LessonRun?
    /// The arrangement the person is setting the rings to, while they set them.
    public private(set) var settingRings: PuzzleState?
    public private(set) var congratulation = Congratulation()
    /// What the last change made heard.
    public private(set) var hearing = Hearing()
    /// Whether the last change was the moment to congratulate: the card has just appeared.
    public private(set) var congratulates = false
    /// What the last change says aloud.
    public private(set) var narration = Narration()
    /// The play in progress: while the congratulation is armed.
    public private(set) var play: Play?
    /// The play the last change finished, at the moment it congratulated; nil after any other change.
    public private(set) var finished: PlayRecord?
    /// How many times the toy shown has jumped: been set at once where some of its parts are somewhere else. The screen
    /// shows a jump as the parts that change place fading across, where every other change moves them.
    public private(set) var jumps = 0

    /// The person's toy as the congratulation last saw it.
    private var judged: PuzzleSession
    /// The toy shown, as last heard, and as at the last frame.
    private var heard: PuzzleSession
    private var framed: PuzzleSession

    /// The puzzle with the person's toy as `toy`, at the beginning of a play.
    public init(_ toy: PuzzleSession = PuzzleSession()) {
        own = toy
        judged = toy
        heard = toy
        framed = toy
        play = Play(startedAt: .now, startRings: toy.state)
    }

    /// The puzzle as `snapshot` kept it, or nil when the snapshot's moves break the rule. The congratulation is armed
    /// when a play was in progress.
    public init?(_ snapshot: ToySnapshot) {
        guard let toy = snapshot.toy else { return nil }
        self.init(toy)
        play = snapshot.play
        congratulation = Congratulation(isArmed: snapshot.play != nil)
    }

    /// What is kept between launches: the person's own toy, as the lesson or the rings being set would give it back,
    /// and the play in progress.
    public var snapshot: ToySnapshot {
        ToySnapshot(toy: lesson?.closingToy ?? own, play: play)
    }

    /// Adds `seconds` with the app in front to the play in progress.
    public mutating func spend(_ seconds: Double) {
        guard seconds > 0 else { return }
        play?.secondsSpent += seconds
    }

    /// The toy as it is shown: resting in the arrangement being set, the lesson's while the lesson is open, or the
    /// person's own.
    public var toy: PuzzleSession {
        if let settingRings { return PuzzleSession(resting: settingRings) }
        return lesson?.toy ?? own
    }

    public var isSettingRings: Bool { settingRings != nil }

    /// The ring buttons: as the toy is about to be, so that a ring marked as able to move is one a tap would move. While
    /// the lesson holds the toy no ring can be asked for, and they follow the toy move by move as it plays.
    public var markers: [PuzzleSession.Marker] {
        let lessonHoldsToy = lesson.map { !$0.givesToyBack } ?? false
        return toy.markers(asPlanned: !lessonHoldsToy)
    }

    public var isCongratulating: Bool { congratulation.isShowing }

    /// The person's toy, where it is shown: their own, or on the lesson's last step the toy it gives back; nil on the
    /// lesson's other steps.
    private var persons: PuzzleSession? {
        if isSettingRings { return nil }
        guard let lesson else { return own }
        return lesson.givesToyBack ? lesson.toy : nil
    }

    // MARK: - Changes that move the toy on

    /// A ring asked to move; while the rings are being set, put on or taken off at once.
    public mutating func tap(_ ring: Int) {
        precondition(PuzzleState.rings.contains(ring), "rings are numbered 1 to 9")
        if let settingRings {
            return setRings(to: PuzzleState(bits: settingRings.bits ^ 1 << (ring - 1)))
        }
        useToy { $0.tap(ring) }
        settle(tapped: ring)
    }

    public mutating func undo() {
        useToy { $0.undo() }
        settle()
    }

    public mutating func solve() {
        useToy { $0.solve() }
        settle()
    }

    /// A drag of the slider.
    public mutating func scrub(to progress: Double) {
        useToy { $0.scrub(to: progress) }
        settle(quiet: true)
    }

    public mutating func togglePlay() {
        guard !isSettingRings else { return nothingChanged() }
        if lesson != nil { lesson?.togglePlay() } else { own.togglePlay() }
        settle()
    }

    /// Stops the move part way. A `quiet` pause says nothing, as the one before a jump does.
    public mutating func pause(quiet: Bool = false) {
        guard !isSettingRings else { return nothingChanged() }
        if lesson != nil { lesson?.pause() } else { own.pause() }
        settle(quiet: quiet)
    }

    /// The clock: `seconds` of the move's own time, at the playing speed.
    public mutating func advance(by seconds: Double) {
        guard !isSettingRings else { return nothingChanged() }
        if lesson != nil { lesson?.advance(by: seconds) } else { own.advance(by: seconds) }
        settle()
    }

    public mutating func dismissCongratulation() {
        congratulation.dismiss()
        congratulates = false
    }

    // MARK: - Jumps

    /// Every ring on, at once: the toy's Reset, or on the lesson's steps but the last, back to its first step. While the
    /// rings are being set, every ring goes on in the arrangement.
    public mutating func reset() {
        if isSettingRings { return setRings(to: .allOn) }
        if lesson != nil { lesson?.reset() } else { own.reset() }
        settle(jump: true, sayingWhereItRests: true, beginsPlay: true)
    }

    /// The toy set where `move` begins, playing it, with the lesson closed.
    public mutating func begin(at move: Move) {
        lesson = nil
        settingRings = nil
        own = PuzzleSession(at: move)
        own.togglePlay()
        settle(jump: true, rebase: true, beginsPlay: true)
    }

    /// Opens the lesson at step `index`, counted from 0, keeping the toy as it is to give back on closing.
    public mutating func openLesson(at index: Int = 0) {
        guard lesson == nil, !isSettingRings else { return nothingChanged() }
        lesson = LessonRun(opening: own, at: index)
        settle(jump: true, rebase: true, lessonMoves: lessonMovesGiven(wasGivenBack: false))
    }

    /// Closes the lesson: the toy is as it was before, or, on the step that gave it back, as the person has it there.
    public mutating func closeLesson() {
        guard let lesson else { return nothingChanged() }
        own = lesson.closingToy
        self.lesson = nil
        settle(jump: true, rebase: true, sayingWhereItRests: true)
    }

    /// Goes to step `index` of the lesson and plays it from its start.
    public mutating func goToLessonStep(_ index: Int) {
        guard lesson != nil else { return nothingChanged() }
        let wasGivenBack = lesson?.givesToyBack ?? false
        lesson?.go(to: index)
        settle(jump: true, rebase: true, lessonMoves: lessonMovesGiven(wasGivenBack: wasGivenBack))
    }

    // MARK: - Setting the rings

    /// Starts setting the rings by hand, from the arrangement the person's toy is in, or was in when the move in hand
    /// began. The move stops; their toy waits as it is, for Cancel.
    public mutating func startSettingRings() {
        guard lesson == nil, !isSettingRings else { return nothingChanged() }
        own.pause()
        settingRings = own.state
        settle(jump: true, rebase: true)
        narration = Narration([.settingRings])
    }

    /// Sets the arrangement being set to `state`, at once.
    public mutating func setRings(to state: PuzzleState) {
        guard let settingRings, state != settingRings else { return nothingChanged() }
        self.settingRings = state
        settle(jump: true, quiet: true)
    }

    /// Makes the arrangement the person's toy: resting there, with no move made, so that play, undo and Solve go on from
    /// it.
    public mutating func finishSettingRings() {
        guard let settingRings else { return nothingChanged() }
        own = PuzzleSession(resting: settingRings)
        self.settingRings = nil
        congratulation.set(settingRings)
        settle(jump: true, rebase: true, sayingWhereItRests: true, beginsPlay: true)
    }

    /// Stops setting the rings and gives the person's toy back as it was.
    public mutating func cancelSettingRings() {
        guard isSettingRings else { return nothingChanged() }
        settingRings = nil
        settle(jump: true, rebase: true, sayingWhereItRests: !own.isPartWay)
        if own.isPartWay { narration = Narration([.paused(own.status)]) }
    }

    /// Whether starting to set the rings moves the toy to another pose at once, so that the screen should cover it: a
    /// move is in hand, and the toy goes to rest where it began.
    public var settingRingsStartJumps: Bool {
        lesson == nil && !isSettingRings && (own.isPlaying || own.isPartWay)
    }

    /// Whether Cancel moves the toy to another pose at once: the arrangement is not the toy's, or the toy was stopped
    /// part way.
    public var settingRingsCancelJumps: Bool {
        guard let settingRings else { return false }
        return settingRings != own.state || own.isPartWay
    }

    // MARK: - The slide

    /// How far the sword has travelled since the last frame, in millimetres; nothing across a jump.
    public mutating func frame() -> Double {
        let travel = Hearing(from: framed, to: toy).swordTravel
        framed = toy
        return travel
    }

    // MARK: - Inside

    /// After a request that changed nothing: nothing heard, nothing said, no congratulation appearing.
    private mutating func nothingChanged() {
        hearing = Hearing()
        narration = Narration()
        congratulates = false
        finished = nil
    }

    /// How many moves the lesson has just made on the person's toy, giving it back: none unless it gives the toy back
    /// now and did not before.
    private func lessonMovesGiven(wasGivenBack: Bool) -> Int {
        guard let lesson, lesson.givesToyBack, !wasGivenBack else { return 0 }
        return lesson.movesPlayedForThePerson.count
    }

    /// A change to the toy shown, as a ring tap, undo, Solve or a drag makes it: on the lesson's steps but the last,
    /// nothing happens.
    private mutating func useToy(_ change: (inout PuzzleSession) -> Void) {
        if isSettingRings { return }
        if lesson != nil { lesson?.useToy(change) } else { change(&own) }
    }

    /// After a change: what is heard, what the congratulation makes of it, what the play counts, and what is said. A jump
    /// is heard as nothing, and says where the toy rests only when `sayingWhereItRests`. A change that `rebase`s is not a
    /// move of the person's toy: the congratulation hides and takes the toy as it now is, and the play counts only the
    /// `lessonMoves` the lesson made on it. A change that `beginsPlay` begins a new play when the congratulation is armed.
    /// A `quiet` change says nothing.
    private mutating func settle(
        tapped: Int? = nil, jump: Bool = false, rebase: Bool = false, sayingWhereItRests: Bool = false, quiet: Bool = false,
        beginsPlay: Bool = false, lessonMoves: Int = 0
    ) {
        let toy = toy
        let before = heard
        hearing = jump ? Hearing() : Hearing(from: heard, to: toy, tapped: tapped)
        heard = toy
        if jump {
            framed = toy
            if !toy.pose.isClose(to: before.pose) { jumps += 1 }
        }
        let wasShowing = congratulation.isShowing
        let judgedBefore = judged
        if let persons {
            if rebase {
                congratulation.dismiss()
            } else {
                congratulation.update(from: judged, to: persons)
            }
            judged = persons
        } else {
            congratulation.dismiss()
        }
        congratulates = congratulation.isShowing && !wasShowing
        keepPlay(from: judgedBefore, to: persons, counting: !rebase, lessonMoves: lessonMoves, begins: beginsPlay)
        narration = narrate(from: before, to: toy, jump: jump, sayingWhereItRests: sayingWhereItRests, quiet: quiet)
    }

    /// Counts the change from `before` to `persons`, the person's toy, into the play in progress, and finishes, ends or
    /// begins a play as the congratulation now stands.
    private mutating func keepPlay(from before: PuzzleSession, to persons: PuzzleSession?, counting: Bool, lessonMoves: Int, begins: Bool) {
        finished = nil
        guard let persons else { return }
        if var play {
            if counting {
                play.moves = max(0, play.moves + persons.moveCount - before.moveCount)
                play.undos += persons.unmadeCount - before.unmadeCount
                play.movesPlayedForThePerson += persons.madeBySolveCount - before.madeBySolveCount
            }
            play.moves += lessonMoves
            play.movesPlayedForThePerson += lessonMoves
            self.play = play
        }
        if congratulates, let play {
            finished = play.finished(in: persons.state, at: .now)
            self.play = nil
        } else if !congratulation.isArmed {
            play = nil
        } else if begins || play == nil || (before.state != .allOn && persons.state == .allOn) {
            play = Play(startedAt: .now, startRings: persons.state)
        }
    }

    private func narrate(from before: PuzzleSession, to toy: PuzzleSession, jump: Bool, sayingWhereItRests: Bool, quiet: Bool) -> Narration {
        let lessonHoldsToy = lesson.map { !$0.givesToyBack } ?? false
        if quiet || lessonHoldsToy { return Narration() }
        if jump { return Narration(sayingWhereItRests ? [.rested(ToySummary(toy.state))] : []) }
        var narration = Narration(from: before, to: toy, refused: hearing.refused)
        if congratulates {
            narration.lines.removeAll { if case .ended = $0 { true } else { false } }
        }
        return narration
    }
}
