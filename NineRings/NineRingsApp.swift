import SwiftUI

@main
struct NineRingsApp: App {
    init() {
        #if os(macOS)
        // One window, so no window tabs, and no tab items in the View and Window menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
        #if DEBUG
        if let request = Capture.request {
            Task { await Capture.run(request) }
        }
        #endif
    }

    var body: some Scene {
        // One window, as the toy is one: a second would be a second toy, heard over the first. The commands remove New
        // Window, and the Mac's window tabs are off, so nothing opens a second one; with the window closed, the Dock
        // opens it again. (A single `Window` scene would say the same, but on the Mac it did not always present its
        // window at launch when the app started behind another app, and it came back closed after a closed session.)
        WindowGroup {
            root
        }
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
        #endif
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if Capture.request == nil {
            MainScreen()
        }
        #else
        MainScreen()
        #endif
    }
}
