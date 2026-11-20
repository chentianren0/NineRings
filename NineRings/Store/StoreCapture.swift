import Motion
import Puzzle
import Session
import SwiftUI
#if DEBUG
import Combine
import RealityKit
#endif
#if os(macOS)
import AppKit
#endif

/// The store-capture mode: the app set up for one App Store picture, in a debug build, by the launch arguments that
/// `StoreLaunch` reads. The tools that make the pictures (`StoreTools/` and `scripts/store-assets.sh`) launch the app
/// this way for each moment of the series.
///
/// In the mode, the app:
/// - keeps the welcome page away, makes no sound and no haptics, keeps the picture still (the follow-the-move setting
///   at its default, off), and takes the release build's choice of each design alternative, for this process only (the launch arguments' own domain, which nothing writes to disk);
/// - hides the debug build's Design menu;
/// - opens in the state the arguments ask for, and holds it;
/// - on the Mac, sizes its window and draws it as the window in front, as it is when someone uses it;
/// - once the toy has been drawn and nothing has moved for a while, says it is ready: it prints
///   `store-capture: ready` (on the Mac with `window <number>`, the window's number for `screencapture -l`), and shows
///   an element with the accessibility identifier `store-capture-ready` for a UI test to wait for.
///
/// Wrong arguments stop the app with a message, rather than give a wrong picture.
///
/// A release build has none of this: there is no `launch`, `isActive` is false, and every hook below does nothing.
@MainActor
enum StoreCapture {
    /// The accessibility identifier of the element that appears once the picture may be taken.
    static let readyIdentifier = "store-capture-ready"

    #if DEBUG
    static let launch: StoreLaunch? = {
        do {
            return try StoreLaunch.parse(ProcessInfo.processInfo.arguments)
        } catch {
            fail("\(error)")
        }
    }()
    static var isActive: Bool { launch != nil }
    #else
    static let isActive = false
    #endif

    /// Sets this process's settings for the mode. Call first thing at launch, before any view reads a setting.
    static func prepare() {
        #if DEBUG
        guard isActive else { return }
        // The launch arguments' domain lives only in this process, and its values win over stored ones, so the copies
        // of the app that others run with the same stored settings are untouched. An argument given explicitly wins.
        var settings: [String: Any] = [
            ScreenKey.welcomeSeen: true,
            SoundKey.sounds: false,
            SoundKey.haptics: false,
            // Off is the setting's default: a copy of the app on this Mac or simulator may have it on.
            Framing.followsMoveKey: false,
            DesignKey.tallView: TallViewDesign.standard.rawValue,
            RingTuningDesign.key: RingTuningDesign.notePerRing.rawValue,
        ]
        #if os(macOS)
        // Open one fresh window, not the windows of the last run.
        settings["ApplePersistenceIgnoreState"] = true
        #endif
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for (key, value) in settings where domain[key] == nil {
            domain[key] = value
        }
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        #endif
    }

    /// The player the arguments ask for, kept in `keeper`, or nil outside the mode. The launch keeps its records in
    /// memory, so nothing the picture sets up reaches a file.
    static func player(keeper: Keeper) -> Player? {
        #if DEBUG
        guard let launch else { return nil }
        if launch.congratulation {
            // The last move, made as dragging the slider to its end makes it: the congratulation follows from the rule,
            // as it does for a move played.
            guard let last = Move(ring: 1, from: PuzzleState("100000000")!) else { fail("no last move") }
            let player = Player(move: last, keeper: keeper)
            player.progress = 1
            return player
        }
        let state = launch.state.flatMap(PuzzleState.init) ?? .allOn
        if let ring = launch.move {
            let move = launch.state == nil ? Player.moves.first { $0.ring == ring } : Move(ring: ring, from: state)
            guard let move else { fail("ring \(ring) cannot move with the rings at \(state)") }
            return Player(move: move, progress: launch.progress ?? 0, keeper: keeper)
        }
        let player = Player(session: PuzzleSession(resting: state), keeper: keeper)
        if let ring = launch.refuse {
            guard state.block(for: ring) != nil else { fail("ring \(ring) can move with the rings at \(state): nothing to refuse") }
            player.tap(ring)
        }
        return player
        #else
        return nil
        #endif
    }

    /// Where the camera first looks from, when the arguments say, for every shape of view.
    static var defaultAngles: ((Viewport) -> CameraAngles)? {
        #if DEBUG
        guard let view = launch?.view else { return nil }
        let angles: CameraAngles
        switch view {
        case .preset(let name): angles = CameraAngles(CameraPreset(rawValue: name) ?? .side)
        case .angles(let yaw, let pitch): angles = .degrees(yaw: Float(yaw), pitch: Float(pitch))
        }
        return { _ in angles }
        #else
        return nil
        #endif
    }

    #if DEBUG
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("store-capture: failed: \(message)\n".utf8))
        exit(2)
    }

    /// Writes a line at once, even when the output goes to a file, where `print` would hold it back.
    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data("store-capture: \(line)\n".utf8))
    }
    #endif
}

extension View {
    /// In the store-capture mode, holds the screen for the picture and says when it is ready. Elsewhere, nothing.
    func storeCapture(player: Player, rig: CameraRig) -> some View {
        #if DEBUG
        modifier(StoreCaptureModifier(player: player, rig: rig, launch: StoreCapture.launch))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct StoreCaptureModifier: ViewModifier {
    let player: Player
    let rig: CameraRig
    let launch: StoreLaunch?

    @State private var isReady = false

    func body(content: Content) -> some View {
        if let launch {
            content
                #if os(macOS)
                // A window launched in the background is not the one in front, and draws its prominent buttons gray.
                .environment(\.appearsActive, true)
                .environment(\.materialActiveAppearance, .active)
                #endif
                .overlay(alignment: .topLeading) {
                    if isReady {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityLabel(Text(verbatim: "Ready for the store picture"))
                            .accessibilityIdentifier(StoreCapture.readyIdentifier)
                    }
                }
                .task { await hold(launch) }
        } else {
            content
        }
    }

    /// What decides what the screen shows: the picture is taken once none of it has changed for a while.
    private struct Signature: Equatable {
        var pose: Player.PoseKey
        var camera: Int
        var isPlaying: Bool
        var isCongratulating: Bool
        var lessonStep: Int?
        var window: CGRect?
    }

    private final class FrameCounter {
        var frames = 0
    }

    private func hold(_ launch: StoreLaunch) async {
        var windowNumber: Int?
        #if os(macOS)
        windowNumber = await sizeWindow(launch.windowSize)
        #endif
        if let step = launch.lessonStep, launch.paused {
            await waitUntil("the lesson to open at step \(step)") { player.lessonPage?.index == step - 1 }
            player.holdLessonStep(step - 1, at: launch.progress ?? 0)
        }

        // Count the 3D view's frames from its scene, once the toy is in it.
        guard let scene = await SceneStore.shared.scene() else { StoreCapture.fail("the toy could not be made") }
        await waitUntil("the toy to be on the screen") { scene.root.scene != nil }
        let counter = FrameCounter()
        let subscription = scene.root.scene?.subscribe(to: SceneEvents.Update.self) { _ in counter.frames += 1 }
        defer { subscription?.cancel() }

        var readiness = StoreReadiness<Signature>()
        let start = ContinuousClock.now
        while !Task.isCancelled {
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let signature = Signature(
                pose: player.poseKey, camera: rig.revision, isPlaying: player.isPlaying,
                isCongratulating: player.isCongratulating, lessonStep: player.lessonPage?.index, window: windowFrame
            )
            if readiness.observe(signature, at: seconds, drawnFrames: counter.frames) {
                // A lesson that closed by itself after opening (as its sheet can in a changed layout) would leave a
                // picture of the toy at rest: refuse it.
                if let step = launch.lessonStep, player.lessonPage?.index != step - 1 {
                    StoreCapture.fail("the lesson is no longer open at step \(step)")
                }
                break
            }
            if seconds > Self.timeout { StoreCapture.fail("not ready after \(Int(Self.timeout)) s") }
            try? await Task.sleep(for: .milliseconds(100))
        }
        isReady = true
        StoreCapture.say(windowNumber.map { "ready window \($0)" } ?? "ready")
    }

    /// The simulator's first frame can take a minute.
    private static let timeout = 240.0

    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > .seconds(Self.timeout) { StoreCapture.fail("waited too long for \(what)") }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private var windowFrame: CGRect? {
        #if os(macOS)
        Self.window?.frame
        #else
        nil
        #endif
    }

    #if os(macOS)
    private static var window: NSWindow? {
        NSApplication.shared.windows.first { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
    }

    /// Gives the window `size` in points and returns its number. The size is the picture's, whatever the screen: the
    /// window is placed with its top at the top of the screen's free area, and may reach past the screen's edges, where
    /// `screencapture -l` still draws it.
    private func sizeWindow(_ size: StoreLaunch.Size?) async -> Int {
        await waitUntil("the window") { Self.window != nil }
        guard let window = Self.window else { StoreCapture.fail("no window") }
        if let size {
            let free = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            let frame = NSRect(
                x: (free.midX - CGFloat(size.width) / 2).rounded(), y: free.maxY - CGFloat(size.height),
                width: CGFloat(size.width), height: CGFloat(size.height)
            )
            // AppKit fits a resizable window's height to its screen, now and whenever the window is drawn again; a window
            // that cannot be resized keeps its frame. Its traffic lights look the same: gray, in a window not in front.
            window.styleMask.remove(.resizable)
            window.setFrame(frame, display: true)
            guard window.frame.size == frame.size else {
                StoreCapture.fail("the window is \(window.frame.size), not \(size.width)x\(size.height), on a screen whose free area is \(free.size)")
            }
        }
        return window.windowNumber
    }
    #endif
}
#endif
