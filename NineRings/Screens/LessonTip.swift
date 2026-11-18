import Session
import SwiftUI
import TipKit

/// The one tip in the app: on the Lesson button, for someone who has not opened the lesson, the first time a ring
/// refuses to move.
///
/// The rules it keeps:
/// - It is eligible once a ring has been refused (an event donated when the status line turns to a refusal), and shows
///   once at most.
/// - It is gone for good once the lesson is opened, by any way (the toolbar, the welcome page, the menu bar, Help),
///   whether it has shown or not, or once it is closed.
/// - What TipKit knows is kept on the device, in the app's own container; nothing is synced.
/// - On the Mac it is a popover on the Lesson button. On iPhone and iPad a popover on a toolbar button never appears
///   (seen in the simulator, even with the rules overridden), so it is inline, above the line that says why the ring
///   cannot move. Either way its button opens the lesson.
struct LessonTip: Tip {
    /// A ring the person asked to move was refused by the rule.
    static let ringRefused = Tips.Event(id: "ringRefused")
    /// The action that opens the lesson.
    static let openLessonAction = "openLesson"

    var title: Text {
        Text("tip.lesson.title", tableName: "Screens")
    }

    var message: Text? {
        Text("tip.lesson.message", tableName: "Screens")
    }

    var image: Image? {
        Image(systemName: "book")
    }

    var rules: [Rule] {
        #Rule(Self.ringRefused) { $0.donations.count >= 1 }
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }

    var actions: [Action] {
        Action(id: Self.openLessonAction) {
            Text("tip.lesson.open", tableName: "Screens")
        }
    }

    /// Whether the tip shows inline, by the status line, rather than as a popover on the Lesson button. In a debug
    /// build `-lesson-tip-style popover` or `inline` chooses, to compare them.
    static var isInline: Bool {
        #if DEBUG
        switch LaunchValue.value(after: "-lesson-tip-style") {
        case "popover": return false
        case "inline": return true
        default: break
        }
        #endif
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// Loads the tips, once, at launch. In a debug build, `-lesson-tip show` shows the tip whatever its rules, to see it,
    /// and `-lesson-tip reset` forgets everything TipKit knows first, as on a first launch. (TipKit's own
    /// `-com.apple.TipKit.ShowTips LessonTip` also shows it.)
    @MainActor
    static func configure() {
        #if DEBUG
        switch LaunchValue.value(after: "-lesson-tip") {
        case "reset": try? Tips.resetDatastore()
        case "show": Tips.showTipsForTesting([LessonTip.self])
        default: break
        }
        if StoreCapture.isActive { Tips.hideAllTipsForTesting() }
        #endif
        try? Tips.configure([.datastoreLocation(.applicationDefault)])
    }

    #if DEBUG
    private enum LaunchValue {
        static func value(after option: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
    }
    #endif
}

extension View {
    /// Puts the lesson's tip on this view, the Lesson button: it learns of refused rings from `player`, is put away for
    /// good when `lessonShown` turns true, and its button calls `openLesson`. Where the tip is inline, this only keeps
    /// its rules, and ``LessonTipView`` shows it.
    func lessonTip(player: Player, lessonShown: Bool, openLesson: @escaping () -> Void) -> some View {
        modifier(LessonTipModifier(player: player, lessonShown: lessonShown, openLesson: openLesson))
    }
}

/// The lesson's tip inline, where it is not a popover: by the status line. It takes no room until the tip shows.
struct LessonTipView: View {
    let openLesson: () -> Void

    var body: some View {
        if LessonTip.isInline {
            TipView(LessonTip()) { action in
                if action.id == LessonTip.openLessonAction { openLesson() }
            }
        }
    }
}

private struct LessonTipModifier: ViewModifier {
    let player: Player
    let lessonShown: Bool
    let openLesson: () -> Void
    private let tip = LessonTip()

    func body(content: Content) -> some View {
        content
            .popoverTip(LessonTip.isInline ? nil : tip) { action in
                if action.id == LessonTip.openLessonAction { openLesson() }
            }
            .onChange(of: isRefused) { _, refused in
                if refused { LessonTip.ringRefused.sendDonation() }
            }
            .onChange(of: lessonShown, initial: true) { _, shown in
                if shown { tip.invalidate(reason: .actionPerformed) }
            }
    }

    /// Whether the status line says a ring was refused.
    private var isRefused: Bool {
        if case .note = player.status { true } else { false }
    }
}
