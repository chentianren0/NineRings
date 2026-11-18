import Puzzle
import Session
import SwiftUI

/// What the window in front gives the menu bar to act on: its toy, its camera, and its modes, which change as the
/// screen changes them. With no such window in front, such as when Settings is, the commands are disabled.
struct PuzzleActions {
    let player: Player
    let rig: CameraRig
    let modes: ScreenModes
}

extension FocusedValues {
    @Entry var puzzle: PuzzleActions?
}

extension View {
    /// Gives the menu bar this window's toy to act on while the window is in front.
    func puzzleCommands(_ actions: PuzzleActions) -> some View {
        focusedSceneValue(\.puzzle, actions)
            #if DEBUG
            .onAppear {
                if MenusWithoutFocus.isOn { MenusWithoutFocus.shared.actions = actions }
            }
            #endif
    }
}

#if DEBUG
/// `-menus-without-focus`, in a debug build: the menu bar acts on the window even while this process is not the app
/// in front, so that the menus can be opened and chosen from a script while another app has the keyboard. Without it,
/// as in a release build, the menu bar acts only on the window in front.
@MainActor
@Observable
final class MenusWithoutFocus {
    static let shared = MenusWithoutFocus()
    static let isOn = ProcessInfo.processInfo.arguments.contains("-menus-without-focus")
    var actions: PuzzleActions?
}
#endif

/// The app's commands, in the menu bar on the Mac and on iPad, and as key commands wherever there is a keyboard.
///
/// The standard menus keep their places: Undo is in Edit, the places to see the toy from are in View, and Help leads
/// to the lesson, which is this app's help. The toy's own commands are in Puzzle, and the lesson's in Lesson, between
/// View and Window. A command that cannot act is disabled, never hidden; when, is ``ToyCommands``.
///
/// Keys without a modifier act on the toy, as a media app's do: Space plays and pauses, 1 to 9 move a ring, and the
/// left and right arrows step through the stages of the move. The lesson goes back and forward with Command-[ and
/// Command-], the Mac's Back and Forward.
///
/// A ring that cannot move is disabled in Move Ring, but its number key still asks it, through the ring buttons'
/// own shortcuts, which the window answers before the menu bar: so a refused ring still says why it cannot move.
struct PuzzleCommands: Commands {
    @FocusedValue(\.puzzle) private var focused

    /// The window the commands act on: the one in front.
    private var puzzle: PuzzleActions? {
        #if DEBUG
        focused ?? MenusWithoutFocus.shared.actions
        #else
        focused
        #endif
    }

    private var state: ToyCommands? {
        guard let player = puzzle?.player else { return nil }
        return ToyCommands(
            markers: player.markers,
            canUndo: player.canUndo,
            canPlay: player.canPlay,
            isPlaying: player.isPlaying,
            canSolve: player.canSolve,
            canScrub: player.hasMove,
            progress: player.progress,
            stages: player.stages,
            lessonHoldsToy: player.lessonHoldsToy,
            lessonIsOpen: puzzle?.modes.showsLesson ?? false,
            isSettingRings: player.isSettingRings
        )
    }

    var body: some Commands {
        // One window: the toy is one, and a second window would be a second toy, heard over the first.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .undoRedo) {
            Button {
                puzzle?.player.undo()
            } label: {
                Text("menu.undo", tableName: "Commands")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(state?.canUndoMove ?? false))
        }

        CommandGroup(before: .toolbar) {
            viewItems
            Divider()
        }

        CommandMenu(Text("menu.puzzle", tableName: "Commands")) {
            puzzleItems
        }

        CommandMenu(Text("menu.lesson", tableName: "Commands")) {
            lessonItems
        }

        CommandGroup(replacing: .help) {
            Button {
                puzzle?.modes.openLesson()
            } label: {
                Text("menu.help", tableName: "Commands")
            }
            .keyboardShortcut("?", modifiers: .command)
            .disabled(!(state?.canShowLesson ?? false))
        }
    }

    // MARK: View

    @ViewBuilder
    private var viewItems: some View {
        Button {
            puzzle?.rig.showDefault()
        } label: {
            Text("Standard View", comment: "View menu item: back to the view the toy is first seen from.")
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(puzzle == nil)
        ForEach(CameraPreset.allCases) { preset in
            Button {
                puzzle?.rig.show(preset, framing: Framing.rings)
            } label: {
                Text(preset.viewMenuTitle)
            }
            .keyboardShortcut(preset.viewShortcut, modifiers: .command)
            .disabled(puzzle == nil)
        }
    }

    // MARK: Puzzle

    @ViewBuilder
    private var puzzleItems: some View {
        let state = state
        Button {
            puzzle?.player.togglePlay()
        } label: {
            state?.isPlaying == true ? Text("menu.pause", tableName: "Commands") : Text("menu.play", tableName: "Commands")
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!(state?.canPlayOrPause ?? false))

        Button {
            if let target = state?.previousStage { puzzle?.player.progress = target }
        } label: {
            Text("menu.previousStage", tableName: "Commands")
        }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(state?.previousStage == nil)

        Button {
            if let target = state?.nextStage { puzzle?.player.progress = target }
        } label: {
            Text("menu.nextStage", tableName: "Commands")
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(state?.nextStage == nil)

        Menu {
            Picker(selection: speed) {
                ForEach(PlaybackSpeed.allCases) { speed in
                    Text("menu.speed \(speed.factor.formatted(.number))", tableName: "Commands").tag(speed)
                }
            } label: {
                Text("menu.speed", tableName: "Commands")
            }
            .pickerStyle(.inline)
        } label: {
            Text("menu.speed", tableName: "Commands")
        }
        .disabled(puzzle == nil)

        Divider()

        Menu {
            ForEach(PuzzleState.rings, id: \.self) { ring in
                Button {
                    puzzle?.player.tap(ring)
                } label: {
                    Text("menu.ring \(ring)", tableName: "Commands")
                }
                .keyboardShortcut(KeyEquivalent(Character(String(ring))), modifiers: [])
                .disabled(!(state?.canMove(ring) ?? false))
            }
        } label: {
            Text("menu.moveRing", tableName: "Commands")
        }
        .disabled(puzzle == nil)

        Divider()

        Button {
            puzzle?.player.solve()
        } label: {
            Text("menu.solve", tableName: "Commands")
        }
        .disabled(!(state?.canSolvePuzzle ?? false))

        Button {
            puzzle?.modes.reset()
        } label: {
            Text("menu.reset", tableName: "Commands")
        }
        .disabled(!(state?.canReset ?? false))

        Divider()

        // One item starts and finishes setting the rings, as Show and Hide Lesson share one; Cancel is the Escape key,
        // on the toolbar's Cancel button.
        Button {
            guard let puzzle else { return }
            if puzzle.player.isSettingRings {
                puzzle.modes.finishSettingRings()
            } else {
                puzzle.modes.startSettingRings()
            }
        } label: {
            state?.isSettingRings == true
                ? Text("menu.doneSettingRings", tableName: "Commands")
                : Text("menu.setRings", tableName: "Commands")
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(!(state?.canSetRings ?? false))
    }

    private var speed: Binding<PlaybackSpeed> {
        Binding {
            puzzle?.player.speed ?? .normal
        } set: { speed in
            puzzle?.player.speed = speed
        }
    }

    // MARK: Lesson

    @ViewBuilder
    private var lessonItems: some View {
        let shows = puzzle?.modes.showsLesson ?? false
        let page = puzzle?.player.lessonPage
        Button {
            puzzle?.modes.toggleLesson()
        } label: {
            shows ? Text("menu.hideLesson", tableName: "Commands") : Text("menu.showLesson", tableName: "Commands")
        }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(!(state?.canShowLesson ?? false))

        Divider()

        Button {
            puzzle?.modes.lesson.goBack()
        } label: {
            Text("menu.previousStep", tableName: "Commands")
        }
        .keyboardShortcut("[", modifiers: .command)
        .disabled(!(page?.canGoBack ?? false))

        Button {
            puzzle?.modes.lesson.goForward()
        } label: {
            Text("menu.nextStep", tableName: "Commands")
        }
        .keyboardShortcut("]", modifiers: .command)
        .disabled(!(page?.canGoForward ?? false))

        Button {
            puzzle?.modes.lesson.replay()
        } label: {
            Text("menu.playStepAgain", tableName: "Commands")
        }
        .disabled(!(page?.canReplay ?? false))
    }
}
