import Foundation
#if os(macOS)
import AppKit
#endif

/// Debug options for the screens around the toy, read from the launch arguments, so that each screen can be opened
/// and seen without touching the app. Stored settings can be overridden for one process the usual way, with the key
/// and a value: `-welcome.seen NO` shows the welcome page again, `-welcome.seen YES` keeps it away, and
/// `-settings.sounds NO` turns sounds off.
enum ScreenLaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after option: String) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-play-last-move` opens the toy one move before every ring is off and plays that move, so that the
    /// congratulation comes up.
    static var playsLastMove: Bool {
        #if DEBUG
        arguments.contains("-play-last-move")
        #else
        false
        #endif
    }

    /// `-show-haptics` shows the Haptics switch on a device without haptics, such as the simulator, to see it.
    static var showsHaptics: Bool {
        #if DEBUG
        arguments.contains("-show-haptics")
        #else
        false
        #endif
    }

    /// `-about-panel` shows About on launch: the About panel on the Mac (see `applyToApp()`), the About sheet on iPhone
    /// and iPad.
    static var opensAbout: Bool {
        #if DEBUG
        arguments.contains("-about-panel")
        #else
        false
        #endif
    }

    /// `-open-settings` opens settings on launch: the Settings window on the Mac, the settings sheet on iPhone and iPad.
    static var opensSettings: Bool {
        #if DEBUG
        arguments.contains("-open-settings")
        #else
        false
        #endif
    }

    #if DEBUG && os(macOS)
    /// For screenshots on the Mac: `-appearance light` or `-appearance dark` sets this process's appearance, whatever
    /// the system's; `-about-panel` shows the app menu's About panel; `-show-app-menu` opens the app menu's items
    /// over the window, since a menu in the menu bar opens only for the app in front. Call once, at launch.
    @MainActor
    static func applyToApp() {
        switch value(after: "-appearance") {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if arguments.contains("-about-panel") { AboutCommand.showPanel() }
        if arguments.contains("-show-app-menu") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard let menu = NSApplication.shared.mainMenu?.items.first?.submenu,
                      let view = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView
                else { return }
                menu.popUp(positioning: nil, at: NSPoint(x: 16, y: view.bounds.height - 16), in: view)
            }
        }
    }
    #endif
}
