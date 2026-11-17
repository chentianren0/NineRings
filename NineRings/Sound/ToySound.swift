import Foundation
import Motion
import Puzzle
import Session
import Toy

/// The toy heard and felt: what the player passes on as the session changes, turned into sound and touch.
///
/// The rule for when something sounds is the package's (`Hearing`): an event of a move's score sounds when the
/// progress crosses it, whichever way and at whatever speed. Here it is thinned in real time, so that a fast speed
/// or a quick drag never rattles (`Thinning`), and then played and felt as the settings allow. The sword's slide
/// follows the sword's speed, read every frame.
@MainActor
final class ToySound {
    /// The one the app's player uses; none while the debug build captures frames, which is silent.
    static let shared: ToySound? = {
        #if DEBUG
        if Capture.request != nil { return nil }
        #endif
        return ToySound()
    }()

    let playback = AudioPlayback()
    private let haptics = Haptics()
    private var thinning = Thinning()
    private let clock = ContinuousClock()
    private let started: ContinuousClock.Instant
    /// The session at the last frame, and when that was, for the sword's speed.
    private var lastFrame: (session: PuzzleSession, time: ContinuousClock.Instant)?
    /// Whether the sound bench is playing the slide on its own, which the frames then leave alone.
    private var isAuditioningSlide = false
    /// A ring's move that ended with every ring off waits this long, in seconds, before the phrase, so that the ring
    /// is heard coming to rest first.
    static let solvedDelay = 0.25

    private init() {
        started = clock.now
        Task.detached(priority: .utility) { Score.prepare() }
        playback.prepare(notePerRing: Self.notePerRing)
    }

    // MARK: Settings

    var soundsOn: Bool { UserDefaults.standard.object(forKey: SoundKey.sounds) as? Bool ?? true }
    var hapticsOn: Bool { Haptics.isSupported && (UserDefaults.standard.object(forKey: SoundKey.haptics) as? Bool ?? true) }

    /// Whether each ring has its own note, or all sound alike. A release build has a note per ring.
    static var notePerRing: Bool {
        #if DEBUG
        RingTuningDesign(rawValue: UserDefaults.standard.string(forKey: RingTuningDesign.key) ?? "") != .oneNote
        #else
        true
        #endif
    }

    // MARK: From the player

    /// What happened between two moments of the session.
    func hear(_ hearing: Hearing) {
        let sounds = soundsOn, feels = hapticsOn
        guard sounds || feels else { return }
        let now = seconds(since: started)
        let notePerRing = Self.notePerRing
        for heard in hearing.events where thinning.admits(heard.event, at: now) {
            if sounds {
                playback.play(Voicing(heard, notePerRing: notePerRing), gain: Float(heard.event.strength))
            }
            if feels { haptics.play(heard.event) }
        }
        if hearing.refused != nil {
            if sounds { playback.play(.refusal, gain: 1) }
            if feels { haptics.refused() }
        }
        if hearing.isSolved {
            if sounds { playback.play(.solved, gain: 1, delay: Self.solvedDelay) }
            if feels { haptics.solved() }
        }
    }

    /// The session as it is drawn this frame: the sword's speed since the last frame, for its slide.
    func frame(_ session: PuzzleSession) {
        let now = clock.now
        defer { lastFrame = (session, now) }
        if isAuditioningSlide { return }
        guard let lastFrame, soundsOn else {
            playback.setSlideSpeed(0)
            return
        }
        let elapsed = seconds(from: lastFrame.time, to: now)
        // After a pause in the frames, such as time in the background, there is no speed to speak of.
        guard elapsed > 0 && elapsed < 0.25 else {
            playback.setSlideSpeed(0)
            return
        }
        playback.setSlideSpeed(Hearing(from: lastFrame.session, to: session).swordTravel / elapsed)
    }

    // MARK: The bench

    /// Plays one voicing as it is, whatever the settings: for listening in the debug build's sound bench.
    func audition(_ voicing: Voicing, delay: Double = 0, gain: Float = 0.7) {
        playback.play(voicing, gain: gain, delay: delay)
    }

    /// Plays the sword's slide alone as it sounds in a move of `ring` coming off at full speed.
    func auditionSlide(ring: Int) {
        let place = ring == 1 ? PuzzleState.allOn : PuzzleState(bits: UInt16(0x1FF) & ~UInt16((1 << max(ring - 2, 0)) - 1))
        guard let move = Move(ring: ring, from: place) else { return }
        let score = Score(move), timing = MoveMotion(move).timing
        isAuditioningSlide = true
        Task { @MainActor in
            defer { isAuditioningSlide = false }
            let begin = clock.now
            var last = 0.0, lastTime = 0.0
            while true {
                try? await Task.sleep(for: .milliseconds(16))
                let time = seconds(since: begin)
                guard time < timing.duration else { break }
                let travel = score.swordTravel(at: timing.progress(atTime: time))
                playback.setSlideSpeed((travel - last) / max(time - lastTime, 0.001))
                last = travel
                lastTime = time
            }
            playback.setSlideSpeed(0)
        }
    }

    // MARK: Time

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        seconds(from: start, to: clock.now)
    }

    private func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let elapsed = end - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}

/// What the player passes on to the toy's sound, in one place: every change it publishes, the ring just tapped, and
/// each frame. It keeps the session as last heard, so that each change is heard from where the last one left off.
@MainActor
final class SoundListener {
    private var heard: PuzzleSession?
    private var tapped: Int?

    /// A ring was asked to move: asking twice for a ring the rule refuses is heard twice.
    func tap(_ ring: Int) {
        tapped = ring
    }

    /// The session as the player publishes it.
    func publish(_ session: PuzzleSession) {
        if let heard { ToySound.shared?.hear(Hearing(from: heard, to: session, tapped: tapped)) }
        heard = session
        tapped = nil
    }

    /// The session as it is drawn this frame.
    func frame(_ session: PuzzleSession) {
        ToySound.shared?.frame(session)
    }
}
