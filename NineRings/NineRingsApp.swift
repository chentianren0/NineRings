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
        WindowGroup {
            #if DEBUG
            if Capture.request == nil {
                MainScreen()
            }
            #else
            MainScreen()
            #endif
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            PuzzleCommands()
            #if os(macOS)
            AboutCommand()
            #endif
        }

        #if os(macOS)
        Settings {
            SettingsWindow()
        }
        #endif
    }
}
