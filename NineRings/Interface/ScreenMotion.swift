import Foundation
import SwiftUI

/// The app's durations and curves for what changes on the screen, kept in one place so that changes that belong
/// together move alike.
///
/// A change of mode (playing, the lesson, setting the rings) is one animated change: everything it moves or fades
/// follows `modeChange`. Where the toy jumps to another arrangement in it, the parts that change place fade across in
/// `crossFade`, as long as the mode change, so that the two end together. The toy's framing eases into its new space
/// over the same time. With Reduce Motion the change is a short fade: views that would travel fade in place instead,
/// and the framing cuts.
enum ScreenMotion {
    /// How long a change of mode takes.
    static let modeDuration = 0.35 * slowdown
    /// How long a change of mode takes with Reduce Motion: a fade, quicker, since nothing travels.
    static let reducedModeDuration = 0.25 * slowdown

    /// The one animation of a change of mode: a smooth curve with no bounce, as the system's own sheets and columns move.
    static func modeChange(reducesMotion: Bool) -> Animation {
        reducesMotion ? .easeInOut(duration: reducedModeDuration) : .smooth(duration: modeDuration)
    }

    /// How long the toy's parts that jump to another place take to fade across.
    static func crossFade(reducesMotion: Bool) -> Double {
        reducesMotion ? reducedModeDuration : modeDuration
    }

    /// How long the toy's framing takes to ease into a new space; nothing with Reduce Motion, where it cuts.
    static func framing(reducesMotion: Bool) -> Double {
        reducesMotion ? 0 : modeDuration
    }

    /// A small view that changes beside the controls, such as the reason a ring cannot move, or a ring button.
    static let small = Animation.snappy(duration: 0.25 * slowdown)

    /// A card that comes over the toy, such as the congratulation.
    static let card = Animation.smooth(duration: 0.4 * slowdown)

    /// The lesson's text changing from one step to the next.
    static let lessonStep = Animation.easeInOut(duration: 0.2 * slowdown)

    /// How long the camera takes to fly to another view: to a preset, to a lesson step's view, or back.
    static let flight = 0.6 * slowdown

    /// `-motion.slowdown 8`, in a debug build, makes the app's own changes of the screen eight times slower, so that
    /// pictures taken in a row can catch them part way. The system's own movements keep their pace.
    private static let slowdown: Double = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-motion.slowdown"), index + 1 < arguments.count,
           let factor = Double(arguments[index + 1]), factor > 0 {
            return factor
        }
        #endif
        return 1
    }()
}
