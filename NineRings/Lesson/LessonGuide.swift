import Foundation
import Session

/// Takes the lesson through its steps on the screen: the player's toy, the camera, and the cover over the toy while
/// it moves to another pose at once.
///
/// The steps and the toy follow ``LessonRun``, through the player. This adds what the screen does around it: the camera
/// is the person's as the toy is, so opening remembers it, and closing, or the step that gives the toy back, flies back
/// to it, while going from that step to another remembers it again; each other step flies the camera to the step's
/// view; and whenever a change would move the toy at once, it happens under the cover, as Reset does.
struct LessonGuide {
    let player: Player
    let rig: CameraRig
    /// Hides the toy, makes the change, and shows the toy again. Where the toy is not on screen, it just makes it.
    var cover: (@escaping () -> Void) -> Void = { $0() }
    /// Whether the lesson is wanted open now, as the panel is. A change made under the cover comes a moment later, so
    /// it checks this again then: opened and closed within the cover, the lesson stays as the panel last asked.
    var isWanted: () -> Bool = { true }

    /// Opens the lesson at its first step, with every ring on: at a launch option's step, the first time, in a debug
    /// build.
    func open() {
        guard !player.isInLesson else { return }
        let index = LessonLaunchOptions.takeStep() ?? 0
        rig.remember()
        cover {
            guard isWanted(), !player.isInLesson else { return }
            player.openLesson(at: index)
            showStepView()
        }
    }

    /// Closes the lesson: the toy and the camera go back to how they were.
    func close() {
        guard player.isInLesson else { return }
        let change = {
            guard !isWanted(), player.isInLesson else { return }
            player.closeLesson()
            rig.flyBack()
        }
        if player.lessonClosingJumps { cover(change) } else { change() }
    }

    func goForward() {
        guard let page = player.lessonPage, page.canGoForward else { return }
        go(to: page.index + 1)
    }

    func goBack() {
        guard let page = player.lessonPage, page.canGoBack else { return }
        go(to: page.index - 1)
    }

    func replay() {
        guard let page = player.lessonPage, page.canReplay else { return }
        go(to: page.index)
    }

    private func go(to index: Int) {
        let leavesOwnToy = player.lessonPage?.givesToyBack == true && Lesson.steps[index].show != .givenBack
        let change = {
            if leavesOwnToy { rig.remember() }
            player.goToLessonStep(index)
            showStepView()
        }
        if player.lessonJumps(to: index) { cover(change) } else { change() }
    }

    /// Flies the camera to where the step is seen from: from above, or the standard view, which is the side view on a
    /// wide screen; or, where the step gives the toy back, to where the person had it.
    private func showStepView() {
        guard let page = player.lessonPage else { return }
        if page.givesToyBack {
            rig.flyBack()
            return
        }
        switch page.view {
        case .top: rig.show(.top, framing: Framing.rings)
        case .side: rig.showDefault()
        }
    }
}

/// Launch options for the lesson, for checking its steps by hand and taking pictures of them.
enum LessonLaunchOptions {
    #if DEBUG
    /// `-lesson-step 6` opens the lesson at launch, at step 6 of 12.
    static let step: Int? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-lesson-step"), index + 1 < arguments.count, let step = Int(arguments[index + 1]) else { return nil }
        return step - 1
    }()
    private static var isTaken = false
    #else
    static let step: Int? = nil
    #endif

    /// Whether the lesson opens at launch.
    static var opensAtLaunch: Bool { step != nil }

    /// The step to open the lesson at, counted from 0, once: later openings begin at the first step.
    static func takeStep() -> Int? {
        #if DEBUG
        guard !isTaken else { return nil }
        isTaken = true
        return step
        #else
        return nil
        #endif
    }
}
