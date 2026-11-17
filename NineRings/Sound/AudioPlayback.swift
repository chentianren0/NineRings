import AVFAudio
import Foundation
import Session
import Synchronization
import Toy
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Plays the toy's sounds: every voice rendered once into a buffer, and the sword's slide rendered as it plays.
///
/// All of its work happens on one serial queue of its own, never on the main thread, so that sound never delays a
/// frame: the main thread only asks. Playing a sound only schedules its buffer on a free player. The engine starts on
/// the first sound, stops when the app leaves the foreground or has been quiet a while, and is built again after an
/// interruption or a change of route (headphones, a new output) has stopped it.
///
/// On iOS the audio session is ambient: the silent switch silences the app, and the user's own music keeps playing.
nonisolated final class AudioPlayback: @unchecked Sendable {
    /// How loud everything is: a toy on a desk, not an alert.
    static let masterVolume: Float = 0.55
    /// How many sounds can ring at once; one more waits for none, and is dropped.
    static let playerCount = 10
    /// How long, in seconds, the engine keeps running with nothing to play.
    static let idleTime = 10.0

    private let queue = DispatchQueue(label: "NineRings.sound", qos: .userInitiated)
    private let format = AVAudioFormat(standardFormatWithSampleRate: Voices.sampleRate, channels: 1)!

    // Touched only on `queue`.
    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var busyUntil: [UInt64] = []
    private var buffers: [Voicing: AVAudioPCMBuffer] = [:]
    private var idleTimer: DispatchSourceTimer?
    private var engineObserver: NSObjectProtocol?

    // Read from any thread.
    private let slide = SlideState()
    private let isAwake = Atomic<Bool>(false)
    private let lastActivity = Atomic<UInt64>(0)
    private var observers: [NSObjectProtocol] = []

    init() {
        observe()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Asking

    /// Renders every buffer one kind of tuning needs, ahead of the first sound.
    func prepare(notePerRing: Bool) {
        queue.async { [self] in
            for voicing in Voicing.all(notePerRing: notePerRing) { _ = buffer(voicing) }
        }
    }

    /// Plays `voicing` at `gain`, after `delay` seconds.
    func play(_ voicing: Voicing, gain: Float, delay: Double = 0) {
        touch()
        queue.async { [self] in
            guard let engine = running(), let buffer = buffer(voicing) else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            guard let index = busyUntil.firstIndex(where: { $0 <= now }) else { return }
            let player = players[index]
            let length = Double(buffer.frameLength) / Voices.sampleRate
            busyUntil[index] = now + UInt64((delay + length) * 1e9)
            player.volume = gain
            let when = delay > 0 ? AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay)) : nil
            player.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
            if !player.isPlaying && engine.isRunning { try? player.playAudio() }
        }
    }

    /// The sword's speed now, in millimetres a second, which the slide follows.
    func setSlideSpeed(_ speed: Double) {
        slide.speed.store(speed.bitPattern, ordering: .relaxed)
        guard speed > 0 else { return }
        touch()
        if !isAwake.load(ordering: .relaxed) {
            queue.async { [self] in _ = running() }
        }
    }

    /// Stops the engine, as when the app leaves the foreground.
    func stop() {
        slide.speed.store(0, ordering: .relaxed)
        queue.async { [self] in halt() }
    }

    // MARK: - Inside, on the queue

    private func touch() {
        lastActivity.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
    }

    /// The engine, running: built if it has to be, started if it is not.
    private func running() -> AVAudioEngine? {
        if engine == nil { build() }
        guard let engine else { return nil }
        if !engine.isRunning {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            do {
                try engine.start()
            } catch {
                return nil
            }
            for player in players { try? player.playAudio() }
        }
        isAwake.store(true, ordering: .relaxed)
        startIdleTimer()
        return engine
    }

    /// Players, the slide and a limiter that keeps many sounds at once from clipping, into the main mixer.
    private func build() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        #endif
        let engine = AVAudioEngine()
        let mix = AVAudioMixerNode()
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0
        ))
        engine.attach(mix)
        engine.attach(limiter)
        let players = (0..<Self.playerCount).map { _ in AVAudioPlayerNode() }
        let source = slide.makeNode(format: format)
        do {
            for player in players {
                engine.attach(player)
                try engine.connectNode(player, to: mix, format: format)
            }
            engine.attach(source)
            try engine.connectNode(source, to: mix, format: format)
            try engine.connectNode(mix, to: limiter, format: nil)
            try engine.connectNode(limiter, to: engine.mainMixerNode, format: nil)
        } catch {
            return
        }
        self.players = players
        busyUntil = Array(repeating: 0, count: players.count)
        engine.mainMixerNode.outputVolume = Self.masterVolume
        self.engine = engine
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            // The engine has stopped itself; build it again for the next sound, off this callback.
            guard let self else { return }
            queue.async { self.tearDown() }
        }
    }

    private func halt() {
        idleTimer?.cancel()
        idleTimer = nil
        guard let engine, engine.isRunning else { return }
        players.forEach { $0.stop() }
        engine.stop()
        isAwake.store(false, ordering: .relaxed)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    private func tearDown() {
        halt()
        engineObserver.map(NotificationCenter.default.removeObserver)
        engineObserver = nil
        engine = nil
        players = []
        busyUntil = []
        isAwake.store(false, ordering: .relaxed)
    }

    private func buffer(_ voicing: Voicing) -> AVAudioPCMBuffer? {
        if let buffer = buffers[voicing] { return buffer }
        let samples = voicing.render()
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = unsafe buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            unsafe channel.update(from: base, count: samples.count)
        }
        buffers[voicing] = buffer
        return buffer
    }

    /// Stops the engine once nothing has sounded for `idleTime` and the sword is still.
    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let quiet = Double(DispatchTime.now().uptimeNanoseconds - lastActivity.load(ordering: .relaxed)) / 1e9
            if quiet > Self.idleTime && slide.speed.load(ordering: .relaxed) == 0 { halt() }
        }
        timer.resume()
        idleTimer = timer
    }

    private func observe() {
        let center = NotificationCenter.default
        #if os(iOS)
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.stop()
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] _ in
            // Began: the system has stopped the engine. Ended: nothing to resume; the next sound starts it again.
            self?.isAwake.store(false, ordering: .relaxed)
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            queue.async { self.tearDown() }
        })
        #elseif os(macOS)
        observers.append(center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: nil) { [weak self] _ in
            self?.stop()
        })
        #endif
    }
}

/// The sword's slide, rendered as it plays: the speed the main thread sets, and the noise the audio thread renders
/// from it (see `SlideNoise`).
nonisolated final class SlideState: @unchecked Sendable {
    /// The sword's speed in millimetres a second, as the bits of a Double.
    let speed = Atomic<UInt64>(0)
    /// Touched only by the audio thread, inside the render block.
    private var noise = SlideNoise()

    func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        unsafe AVAudioSourceNode(format: format) { [self] isSilence, _, frameCount, bufferList in
            let speed = Double(bitPattern: self.speed.load(ordering: .relaxed))
            let buffers = unsafe UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = unsafe buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            var silent = true
            for index in 0..<Int(frameCount) {
                let sample = noise.next(speed: speed)
                unsafe data[index] = sample
                if sample != 0 { silent = false }
            }
            unsafe isSilence.pointee = ObjCBool(silent)
            return noErr
        }
    }
}
