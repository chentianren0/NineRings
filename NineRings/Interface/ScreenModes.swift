import Observation
import SwiftUI

/// What the screen is doing: the person playing, the lesson, or the person setting the rings.
enum ScreenMode: Equatable {
    case playing
    case lesson
    case settingRings
}

/// The one place where the screen changes mode, and where the toy is reset, as the toolbar, the menu bar, the lesson's
/// panel and the welcome page ask.
///
/// Every change of mode is one animated change: the player's change and the screen's are made together, in one
/// transaction with `ScreenMotion.modeChange`, so that the lesson's panel arrives with its text, the bars and the
/// controls move with it, and the toy, where it jumps to another arrangement, fades only the parts that change place
/// (see `ToyScene.crossFade`). Nothing waits for anything else.
///
/// Everything on screen follows from `mode`. Whether the lesson shows is the screen's own state, since the system's
/// inspector reads and writes it; the lesson in the player follows it (see `PuzzleScreen`).
@MainActor
@Observable
final class ScreenModes {
    let player: Player
    let rig: CameraRig
    /// Whether the lesson's panel shows.
    var showsLesson: Bool
    /// Whether Reduce Motion is on, as the screen last read it.
    @ObservationIgnored var reducesMotion = false

    init(player: Player, rig: CameraRig, showsLesson: Bool = false) {
        self.player = player
        self.rig = rig
        self.showsLesson = showsLesson
    }

    var mode: ScreenMode {
        if player.isSettingRings { return .settingRings }
        return showsLesson ? .lesson : .playing
    }

    /// The lesson's steps on the screen: the player's toy and the camera.
    var lesson: LessonGuide { LessonGuide(player: player, rig: rig) }

    // MARK: The lesson

    var canOpenLesson: Bool { !showsLesson && !player.isSettingRings }

    /// Opens the lesson at its first step, at once, with its text.
    func openLesson() {
        guard canOpenLesson else { return }
        change {
            showsLesson = true
            lesson.open()
        }
    }

    /// Closes the lesson: the toy and the camera go back to how they were.
    func closeLesson() {
        guard showsLesson else { return }
        change {
            showsLesson = false
            lesson.close()
        }
    }

    /// Brings the lesson in the player into line with the panel, where the system alone opened or closed the panel, as
    /// a swipe down closes the sheet. Where the change came through here, the lesson already follows and nothing changes.
    func followLessonPanel() {
        guard showsLesson != player.isInLesson else { return }
        change {
            if showsLesson { lesson.open() } else { lesson.close() }
        }
    }

    func toggleLesson() {
        if showsLesson { closeLesson() } else { openLesson() }
    }

    // MARK: Setting the rings

    func startSettingRings() {
        guard !player.isSettingRings, !showsLesson else { return }
        change { player.startSettingRings() }
    }

    /// Done: the rings as set become the toy.
    func finishSettingRings() {
        guard player.isSettingRings else { return }
        change { player.finishSettingRings() }
    }

    /// Cancel: the toy as it was before.
    func cancelSettingRings() {
        guard player.isSettingRings else { return }
        change { player.cancelSettingRings() }
    }

    // MARK: The toy

    /// Every ring back on, at once; the parts that change place fade across.
    func reset() {
        change { player.reset() }
    }

    /// Makes `body`'s changes one animated change of the screen.
    private func change(_ body: () -> Void) {
        withAnimation(ScreenMotion.modeChange(reducesMotion: reducesMotion), body)
    }
}
