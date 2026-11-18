import Foundation
import Session

/// Takes the lesson through its steps on the screen: the player's toy and the camera.
///
/// The steps and the toy follow ``LessonRun``, through the player. This adds what the screen does around it: the camera
/// is the person's as the toy is, so opening remembers it, and closing, or the step that gives the toy back, flies back
/// to it, while going from that step to another remembers it again; each other step flies the camera to the step's
/// view. Every change happens at once: where it sets the toy somewhere else, the 3D view fades the parts that change
/// place (see `ToyScene.crossFade`).
struct LessonGuide {
    let player: Player
    let rig: CameraRig

    /// Opens the lesson at its first step, with every ring on: at a launch option's step, the first time, in a debug
    /// build.
    func open() {
        guard !player.isInLesson else { return }
        rig.remember()
        player.openLesson(at: LessonLaunchOptions.takeStep() ?? 0)
        showStepView()
    }

    /// Closes the lesson: the toy and the camera go back to how they were.
    func close() {
        guard player.isInLesson else { return }
        player.closeLesson()
        rig.flyBack()
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
        if player.lessonPage?.givesToyBack == true, Lesson.steps[index].show != .givenBack { rig.remember() }
        player.goToLessonStep(index)
        showStepView()
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
        case .top: rig.show(.top, framing: Framing.ringsAndSword)
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
