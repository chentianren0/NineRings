#if MEASURE && os(macOS)
import AppKit
import Darwin
import Foundation
import os
import Synchronization

/// A measuring build's scripts: what the app does by itself, with nobody at the keyboard, while Instruments or a
/// shell measures it. Only a Mac build made with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=MEASURE` has them:
///
///     xcodebuild -project NineRings.xcodeproj -scheme NineRings -configuration Release -destination 'platform=macOS' \
///         -derivedDataPath <folder> SWIFT_ACTIVE_COMPILATION_CONDITIONS=MEASURE build
///     open -g -n --stdout <file> -a <that build's NineRings.app> --args -ApplePersistenceIgnoreState YES \
///         -welcome.seen YES -measure <script>
///
/// Open that copy by its path, never by the app's name, which can open another copy of the app. To trace it, attach
/// Instruments to its process rather than letting Instruments launch it, for the same reason.
///
/// What a script prints goes to the file `open --stdout` names. Each phase of a script is an interval in the Points of
/// Interest track, so a trace can be cut by phase, and prints one line: frames a second, the time between frames
/// (median, 95th percentile, longest), hitches, processor time as a share of one core, and the memory footprint.
///
/// - `launch`: writes the time from the process's start to each launch mark and to the toy's first frame, then quits.
/// - `idle`: rests 20 s seen, 20 s hidden, 10 s seen, 20 s in the Dock, 10 s seen, then quits.
/// - `play1x`, `play4x`: rests 5 s, then Solve plays at that speed for 30 s, then quits.
/// - `solve`: rests 5 s, then Solve plays at 1× for 60 s, then quits.
/// - `solvelong`: Solve plays at 4× to the end, rests 10 s, then quits.
/// - `drag`: rests 5 s, then turns the view as a drag would, by a few points a frame, 4 × 5 s, then quits.
@MainActor
enum MeasureScript {
    private static var started = false

    static var name: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-measure"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Starts the script once the toy is drawn.
    static func start(player: Player, rig: CameraRig) {
        guard !started, let name else { return }
        started = true
        Task {
            // Let the first frames through, and bring the window up without taking the keys from whoever is typing.
            try? await Task.sleep(for: .seconds(1))
            window?.orderFrontRegardless()
            log("window \(window.map { "\($0.frame.size) occlusion visible: \($0.occlusionState.contains(.visible))" } ?? "none")")
            await run(name, player: player, rig: rig)
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil)
        }
    }

    private static func run(_ name: String, player: Player, rig: CameraRig) async {
        switch name {
        case "launch":
            MeasureLog.writeLaunch()
        case "idle":
            await phase("seen", seconds: 20)
            NSApp.hide(nil)
            await phase("hidden", seconds: 20)
            NSApp.unhideWithoutActivation()
            window?.orderFrontRegardless()
            await phase("seen again", seconds: 10)
            window?.miniaturize(nil)
            await phase("in the Dock", seconds: 20)
            window?.deminiaturize(nil)
            window?.orderFrontRegardless()
            await phase("seen last", seconds: 10)
        case "play1x", "play4x", "solve":
            await phase("rest", seconds: 5)
            player.speed = name == "play4x" ? .quadruple : .normal
            player.solve()
            await phase(name == "solve" ? "solve 1x" : "solve \(player.speed.factor)x", seconds: name == "solve" ? 60 : 30)
        case "solvelong":
            player.speed = .quadruple
            player.solve()
            let begin = ContinuousClock.now
            while player.canSolve || player.isPlaying, ContinuousClock.now - begin < .seconds(600) {
                try? await Task.sleep(for: .seconds(1))
            }
            log("solve ended after \(ContinuousClock.now - begin)")
            await phase("rest after solve", seconds: 10)
        case "drag":
            await phase("rest", seconds: 5)
            for direction in [1.0, -1.0, 1.0, -1.0] {
                await phase("drag", seconds: 5) {
                    rig.orbit(by: CGSize(width: 4 * direction, height: 0.6 * direction))
                }
            }
        default:
            log("unknown script \(name)")
        }
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.toolbar != nil }
            ?? NSApp.windows.first { $0.toolbar != nil }
    }

    /// Waits `seconds` as one interval, calling `step` about every 1/60 s if given.
    private static func phase(_ name: String, seconds: Double, step: (() -> Void)? = nil) async {
        let poster = Signposts.poster
        let state = poster.beginInterval("Measure", id: poster.makeSignpostID(), "\(name)")
        let visible = window?.occlusionState.contains(.visible) ?? false
        let before = MeasureLog.Counters.now()
        defer {
            let after = MeasureLog.Counters.now()
            log("phase \(name.replacingOccurrences(of: " ", with: "_")) visible=\(visible) " + after.report(since: before))
        }
        let end = ContinuousClock.now + .seconds(seconds)
        if let step {
            while ContinuousClock.now < end {
                step()
                try? await Task.sleep(for: .milliseconds(16))
            }
        } else {
            try? await Task.sleep(until: end)
        }
        poster.endInterval("Measure", state)
    }

    static func log(_ text: String) {
        MeasureLog.logger.log("\(text, privacy: .public)")
        print(text)
        unsafe fflush(stdout)
    }
}

/// The launch marks of a measuring build, in milliseconds since the process started.
nonisolated enum MeasureLog {
    static let logger = Logger(subsystem: "NineRings", category: "Measure")
    private static let marks = Mutex<[String]>([])

    /// When the process started, from the kernel, on the same clock as `Date`.
    private static let processStart: Date = {
        var info = unsafe kinfo_proc()
        var size = unsafe MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        _ = unsafe sysctl(&name, 4, &info, &size, nil, 0)
        let time = unsafe info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1e6)
    }()

    private static func sinceStart() -> Double {
        Date().timeIntervalSince(processStart) * 1000
    }

    /// The frames the toy has been drawn in: how many, and the time between each and the one before, in seconds.
    private static let frames = Mutex<[Double]>([])

    static func frame(delta: Double) {
        frames.withLock { $0.append(delta) }
    }

    /// What a phase is measured by: the frames so far, and the processor time the process has used.
    struct Counters {
        let frameCount: Int
        let cpu: Double
        let wall: ContinuousClock.Instant

        static func now() -> Counters {
            var usage = rusage()
            unsafe getrusage(RUSAGE_SELF, &usage)
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
            return Counters(frameCount: frames.withLock { $0.count }, cpu: cpu, wall: .now)
        }

        /// Frames a second, the spread of the time between frames, frames that took more than twice the usual time
        /// (hitches), the longest, and processor time as a share of one core.
        func report(since start: Counters) -> String {
            let elapsed = wall - start.wall
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let deltas = frames.withLock { Array($0[start.frameCount..<frameCount]) }.sorted()
            func ms(_ value: Double) -> String { (value * 1000).formatted(.number.grouping(.never).precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX"))) }
            func percentile(_ p: Double) -> Double { deltas.isEmpty ? 0 : deltas[min(Int(Double(deltas.count) * p), deltas.count - 1)] }
            let median = percentile(0.5)
            let hitches = deltas.filter { $0 > 2 * median && $0 > 0.02 }.count
            let fps = (Double(deltas.count) / seconds).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
            let cpuShare = ((cpu - start.cpu) / seconds * 100).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
            var info = rusage_info_current()
            let footprint = withUnsafeMutablePointer(to: &info) { pointer in
                unsafe pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { unsafe proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0) }
            } == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : -1
            let memory = footprint.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
            return "footprintMB=\(memory) seconds=\(Int(seconds.rounded())) frames=\(deltas.count) fps=\(fps) p50=\(ms(median)) p95=\(ms(percentile(0.95))) max=\(ms(deltas.last ?? 0)) hitches=\(hitches) cpu%=\(cpuShare)"
        }
    }

    static func record(_ name: StaticString, from start: ContinuousClock.Instant?) {
        let end = sinceStart()
        let label = "\(name)".replacingOccurrences(of: " ", with: "_")
        let line: String
        if let start {
            let elapsed = ContinuousClock.now - start
            let duration = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            line = "\(label) \(tenths(end - duration)) \(tenths(duration))"
        } else {
            line = "\(label) \(tenths(end))"
        }
        marks.withLock { $0.append(line) }
    }

    private static func tenths(_ milliseconds: Double) -> String {
        milliseconds.formatted(.number.grouping(.never).precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
    }

    /// Prints one line per launch, each mark as `name start [duration]`; `open --stdout <file>` collects them.
    static func writeLaunch() {
        let lines = marks.withLock { $0 }
        let start = processStart.timeIntervalSince1970.formatted(.number.grouping(.never).precision(.fractionLength(3)).locale(Locale(identifier: "en_US_POSIX")))
        print("launch " + lines.joined(separator: " | ") + " | processStartEpoch \(start)")
        unsafe fflush(stdout)
    }
}
#endif
