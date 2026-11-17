import SwiftUI

@main
struct NineRingsApp: App {
    init() {
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

        #if os(macOS)
        Settings {
            SettingsPlaceholder()
                .frame(width: 420, height: 280)
        }
        #endif
    }
}
