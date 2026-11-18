import SwiftUI

@main
struct NineRingsApp: App {
    /// The launch's one keeper of records: made here once, so that its store is opened once however many times a
    /// window is made, and given to every scene.
    @State private var keeper: Keeper

    init() {
        #if os(macOS)
        // One window, so no window tabs, and no tab items in the View and Window menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
        #if DEBUG
        // Before any store opens: CloudKit's development schema, only when the launch asks.
        CloudSchema.createIfAsked()
        StoreCapture.prepare()
        if let request = Capture.request {
            Task { await Capture.run(request) }
        }
        #endif
        // The lesson's tip; what it knows stays on the device.
        LessonTip.configure()
        _keeper = State(initialValue: Keeper(place: LaunchOptions.recordPlace, samplePlays: LaunchOptions.samplePlays))
    }

    var body: some Scene {
        // One window, as the toy is one: a second would be a second toy, heard over the first. The commands remove New
        // Window, and the Mac's window tabs are off, so nothing opens a second one; with the window closed, the Dock
        // opens it again. (A single `Window` scene would say the same, but on the Mac it did not always present its
        // window at launch when the app started behind another app, and it came back closed after a closed session.)
        WindowGroup {
            root
        }
        .environment(keeper)
        .defaultSize(width: 1100, height: 720)
        .commands {
            PuzzleCommands()
            #if os(macOS)
            AboutCommand()
            HelpLinks()
            #endif
        }

        #if os(macOS)
        Settings {
            SettingsWindow()
        }
        .environment(keeper)

        // The history of finished plays, opened from the Puzzle menu.
        Window(Text("history.title", tableName: "Screens"), id: HistoryWindow.id) {
            HistoryWindow()
        }
        .environment(keeper)
        .defaultSize(width: 460, height: 560)
        .commandsRemoved()
        #endif
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if Capture.request == nil {
            MainScreen(keeper: keeper)
        }
        #else
        MainScreen(keeper: keeper)
        #endif
    }
}
