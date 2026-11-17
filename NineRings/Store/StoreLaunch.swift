#if DEBUG || STORE_TOOLS
import Foundation

/// The launch arguments of the store-capture mode, which sets the app up for one App Store picture: read here as plain
/// values, without the app's types, so that the store tools' tests read them with this same code.
///
/// The mode is on when the arguments hold `-store-capture`. Then:
///
/// - `-state 000111111`: the rings at rest in that state, ring 1 first, `1` for on and `0` for off.
/// - `-move 5`: ring 5's move on the slider, from `-state` if given, else from where ring 5 first comes off on the way
///   from every ring on to every ring off (as the app's own `-move`). `-start-progress 0.55` holds it that far through.
/// - `-refuse 5`: ring 5 tapped at rest where the rule refuses it, so that the reason and the ring in the way show.
/// - `-lesson-step 7`: the lesson open at step 7 of 12 (the lesson's own option). With `-start-progress 0.5` and
///   `-paused`, its move is played at once to that point of its progress and held there.
/// - `-congratulation`: the last ring just taken off, with the congratulation up, without playing the move.
/// - `-view side|top|tip|30:20`: where the camera looks from: a preset of the View menu, or a yaw and a pitch in degrees.
/// - `-window-size 1280x800`: on the Mac, the window's size in points, title bar and toolbar included.
///
/// Put any options without a value (`-store-capture`, `-paused`, `-congratulation`) after the system's own
/// (`-AppleLanguages (fr)`), because the system reads `-name value` pairs from the arguments and a lone flag would take the
/// next word as its value.
struct StoreLaunch: Equatable {
    enum View: Equatable {
        /// A camera preset by its name: `side`, `top` or `tip`.
        case preset(String)
        /// A yaw and a pitch in degrees.
        case angles(yaw: Double, pitch: Double)
    }

    struct Size: Equatable {
        var width: Int
        var height: Int
    }

    /// Why the arguments cannot set up a picture.
    enum Problem: Error, Equatable, CustomStringConvertible {
        case missingValue(option: String)
        case badValue(option: String, value: String)
        case conflict(String, String)

        var description: String {
            switch self {
            case .missingValue(let option): "\(option) needs a value"
            case .badValue(let option, let value): "\(option) cannot be \(value)"
            case .conflict(let one, let other): "\(one) and \(other) cannot be used together"
            }
        }
    }

    static let flag = "-store-capture"
    static let presets = ["side", "top", "tip"]

    var state: String?
    var move: Int?
    var progress: Double?
    var refuse: Int?
    var lessonStep: Int?
    var paused = false
    var congratulation = false
    var view: View?
    var windowSize: Size?

    /// The options, or nil when the mode is off. Throws when the mode is on and an option is wrong, so that a capture
    /// stops rather than take a wrong picture.
    static func parse(_ arguments: [String]) throws -> StoreLaunch? {
        guard arguments.contains(flag) else { return nil }
        func value(_ option: String) throws -> String? {
            guard let index = arguments.firstIndex(of: option) else { return nil }
            // A value may begin with a minus sign, as a yaw of -45 does, but not with a dash and a letter, as an option does.
            guard index + 1 < arguments.count else { throw Problem.missingValue(option: option) }
            let next = arguments[index + 1]
            if next.hasPrefix("-"), next.dropFirst().first?.isLetter == true { throw Problem.missingValue(option: option) }
            return next
        }
        func ring(_ option: String) throws -> Int? {
            guard let text = try value(option) else { return nil }
            guard let ring = Int(text), (1...9).contains(ring) else { throw Problem.badValue(option: option, value: text) }
            return ring
        }

        var launch = StoreLaunch()
        if let state = try value("-state") {
            guard state.count == 9, state.allSatisfy({ $0 == "0" || $0 == "1" }) else { throw Problem.badValue(option: "-state", value: state) }
            launch.state = state
        }
        launch.move = try ring("-move")
        launch.refuse = try ring("-refuse")
        if let text = try value("-start-progress") {
            guard let progress = Double(text), (0...1).contains(progress) else { throw Problem.badValue(option: "-start-progress", value: text) }
            launch.progress = progress
        }
        if let text = try value("-lesson-step") {
            guard let step = Int(text), step >= 1 else { throw Problem.badValue(option: "-lesson-step", value: text) }
            launch.lessonStep = step
        }
        launch.paused = arguments.contains("-paused")
        launch.congratulation = arguments.contains("-congratulation")
        if let text = try value("-view") {
            if presets.contains(text) {
                launch.view = .preset(text)
            } else {
                let degrees = text.split(separator: ":").compactMap { Double($0) }
                guard degrees.count == 2, (-90...90).contains(degrees[1]) else { throw Problem.badValue(option: "-view", value: text) }
                launch.view = .angles(yaw: degrees[0], pitch: degrees[1])
            }
        }
        if let text = try value("-window-size") {
            let numbers = text.split(separator: "x").compactMap { Int($0) }
            guard numbers.count == 2, numbers.allSatisfy({ $0 >= 200 }) else { throw Problem.badValue(option: "-window-size", value: text) }
            launch.windowSize = Size(width: numbers[0], height: numbers[1])
        }

        // One picture shows one thing.
        let exclusive: [(String, Bool)] = [
            ("-move", launch.move != nil),
            ("-refuse", launch.refuse != nil),
            ("-lesson-step", launch.lessonStep != nil),
            ("-congratulation", launch.congratulation),
        ]
        let chosen = exclusive.filter(\.1).map(\.0)
        if chosen.count > 1 { throw Problem.conflict(chosen[0], chosen[1]) }
        if launch.lessonStep != nil, launch.state != nil { throw Problem.conflict("-lesson-step", "-state") }
        if launch.congratulation, launch.state != nil { throw Problem.conflict("-congratulation", "-state") }
        if launch.progress != nil, launch.move == nil, launch.lessonStep == nil {
            throw Problem.conflict("-start-progress", "no -move or -lesson-step")
        }
        if launch.paused, launch.lessonStep == nil { throw Problem.conflict("-paused", "no -lesson-step") }
        return launch
    }
}
#endif
