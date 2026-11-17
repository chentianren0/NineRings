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
    private let haptics = ToyHaptics()
    private var thinning = Thinning()
    private let clock = ContinuousClock()
    private let started: ContinuousClock.Instant
    /// Each listener's sword speed, and when it was set: one listener per player, so per window.
    private var slideSpeeds: [ObjectIdentifier: (speed: Double, time: ContinuousClock.Instant)] = [:]
    /// Whether the sound bench is playing the slide on its own, which the frames then leave alone.
    private var isAuditioningSlide = false
    /// The congratulation's phrase waits this long, in seconds, after the move that took the last ring off, so that
    /// the ring is heard coming to rest first.
    static let solvedDelay = 0.25

    private init() {
        started = clock.now
        Task.detached(priority: .utility) { Score.prepare() }
        playback.prepare(notePerRing: Self.notePerRing)
        if hapticsOn { haptics.prepare() }
    }

    // MARK: Settings

    var soundsOn: Bool { Self.isOn(SoundKey.sounds) }
    var hapticsOn: Bool { ToyHaptics.isSupported && Self.isOn(SoundKey.haptics) }

    /// A switch's stored value, on when nothing is stored. `bool(forKey:)` also reads a launch argument such as
    /// `-settings.sounds NO`, which arrives as text.
    private static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

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
    }

    /// The congratulation's moment: the person's own move has taken the last ring off.
    func congratulate() {
        if soundsOn { playback.play(.solved, gain: 1, delay: Self.solvedDelay) }
        if hapticsOn { haptics.solved() }
    }

    /// One listener's sword speed this frame, in millimetres a second. The slide follows the fastest that is still
    /// fresh (see `PlaybackRules`), so that two windows, one still and one playing, do not fight over it.
    func setSlideSpeed(_ speed: Double, from listener: SoundListener) {
        let now = clock.now
        slideSpeeds[ObjectIdentifier(listener)] = (speed, now)
        if isAuditioningSlide { return }
        guard soundsOn else {
            playback.setSlideSpeed(0)
            return
        }
        slideSpeeds = slideSpeeds.filter { seconds(from: $0.value.time, to: now) < 1 }
        playback.setSlideSpeed(PlaybackRules.slideSpeed(slideSpeeds.values.map { ($0.speed, seconds(from: $0.time, to: now)) }))
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

/// What one player passes on to the toy's sound: what each change made heard, the congratulation's moment, and the
/// sword's travel each frame. The rules for what is heard, jumps included, are the player's `PlayState`; this keeps
/// only what belongs to its own window, the time of its last frame, so that two windows never mix their speeds.
@MainActor
final class SoundListener {
    private let clock = ContinuousClock()
    private var lastFrame: ContinuousClock.Instant?

    /// One change of the player's toy: what it made heard, and whether the congratulation has just appeared.
    func publish(_ hearing: Hearing, congratulates: Bool) {
        ToySound.shared?.hear(hearing)
        if congratulates { ToySound.shared?.congratulate() }
    }

    /// The sword's travel since the last frame, in millimetres, as the player's toy is drawn this frame.
    func frame(travel: Double) {
        let now = clock.now
        defer { lastFrame = now }
        guard let lastFrame else { return }
        let elapsed = now - lastFrame
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        // After a pause in the frames, such as time in the background, there is no speed to speak of.
        let speed = seconds > 0 && seconds < PlaybackRules.speedLife ? travel / seconds : 0
        ToySound.shared?.setSlideSpeed(speed, from: self)
    }
}
