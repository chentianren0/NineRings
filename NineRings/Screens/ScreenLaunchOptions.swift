import Foundation
#if os(macOS)
import AppKit
#endif

/// Debug options for the screens around the toy, read from the launch arguments, so that each screen can be opened
/// and seen without touching the app. Stored settings can be overridden for one process the usual way, with the key
/// and a value: `-welcome.seen NO` shows the welcome page again, `-welcome.seen YES` keeps it away, and
/// `-settings.sounds NO` turns sounds off.
enum ScreenLaunchOptions {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after option: String) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #endif

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

    /// `-open-history YES` opens the history on launch: its window on the Mac, its sheet on iPhone and iPad.
    /// `-open-history clear` opens it asking to clear it: the confirmation shows once Clear History is on the screen,
    /// which is at once with a few plays, and after scrolling down with many.
    static var opensHistory: Bool {
        #if DEBUG
        value(after: "-open-history") != nil
        #else
        false
        #endif
    }

    /// Whether `-open-history clear` asks for the confirmation to clear the history at launch.
    static var confirmsClearing: Bool {
        #if DEBUG
        value(after: "-open-history") == "clear"
        #else
        false
        #endif
    }

    /// `-clearing-reaches-other-devices YES` words the confirmation to clear the history for every device, as it reads
    /// when clearing reaches the person's other devices, whatever the keeper says.
    static var clearingReachesOtherDevices: Bool {
        #if DEBUG
        value(after: "-clearing-reaches-other-devices") == "YES"
        #else
        false
        #endif
    }

    /// `-unreadable-plays 2` shows the history as if two more plays were kept that this build cannot read, until it is
    /// cleared. Such plays come only from a newer version of the app.
    static var unreadablePlays: Int {
        #if DEBUG
        max(0, value(after: "-unreadable-plays").flatMap { Int($0) } ?? 0)
        #else
        0
        #endif
    }

    #if DEBUG && os(macOS)
    /// For screenshots and trying the menus on the Mac, from this process alone:
    /// - `-appearance light` or `-appearance dark` sets this process's appearance, whatever the system's.
    /// - `-about-panel` shows the app menu's About panel.
    /// - `-window-size 360x420` sets the window's content to that size, or as near as its limits allow.
    /// - `-perform-menu "Puzzle>Move Ring>Ring 1"` chooses that menu bar item, as a click on it would; repeat it for
    ///   several, one every `-perform-interval` seconds (1 by default), the first after `-perform-after` seconds (2 by
    ///   default). Each is logged.
    /// - `-show-menu Puzzle` then opens that menu bar menu over the window, since a menu in the menu bar opens only for
    ///   the app in front; `-show-menu app` opens the app menu, and `-show-menu "Puzzle>Move Ring"` a submenu.
    /// Call once, at launch.
    @MainActor
    static func applyToApp() {
        switch value(after: "-appearance") {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if arguments.contains("-about-panel") { AboutCommand.showPanel() }
        let performs = values(after: "-perform-menu")
        let interval = value(after: "-perform-interval").flatMap(Double.init) ?? 1
        let size = value(after: "-window-size")?.split(separator: "x").compactMap { Double($0) }
        let shownMenu = value(after: "-show-menu")
        guard !performs.isEmpty || size != nil || shownMenu != nil else { return }
        let start = value(after: "-perform-after").flatMap(Double.init) ?? 2
        Task {
            try? await Task.sleep(for: .seconds(start))
            // The toy's window: the largest one showing, larger than Settings or the About panel.
            let window = NSApplication.shared.windows
                .filter { $0.isVisible && $0.level == .normal }
                .max { $0.frame.width < $1.frame.width }
            if let size, size.count == 2, let window {
                window.setContentSize(NSSize(width: size[0], height: size[1]))
                log("window content size: \(window.contentLayoutRect.size), minimum: \(window.contentMinSize)")
            }
            for path in performs {
                // As opening the menu or pressing a key does, the menus are brought up to date first.
                NSApplication.shared.mainMenu?.update()
                try? await Task.sleep(for: .seconds(0.3))
                performMenuItem(path)
                try? await Task.sleep(for: .seconds(interval))
            }
            if let shownMenu, let view = window?.contentView {
                let items = NSApplication.shared.mainMenu?.items ?? []
                let titles = shownMenu.split(separator: ">").map(String.init)
                var menu = (titles[0] == "app" ? items.first : items.first { $0.title == titles[0] })?.submenu
                for title in titles.dropFirst() {
                    menu?.update()
                    menu = menu?.items.first { $0.title == title }?.submenu
                }
                guard let menu else {
                    log("no menu \(shownMenu); the menu bar has: \(items.map(\.title))")
                    return
                }
                menu.update()
                menu.popUp(positioning: nil, at: NSPoint(x: 16, y: view.bounds.height - 16), in: view)
            }
        }
    }

    /// Writes a line to standard error, which is not buffered, so that it is there even when the process is quit.
    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// Every value given after `option`, in order.
    private static func values(after option: String) -> [String] {
        arguments.indices.compactMap { index in
            arguments[index] == option && index + 1 < arguments.count ? arguments[index + 1] : nil
        }
    }

    /// Chooses the menu bar item at `path`, titles joined by ">".
    @MainActor
    private static func performMenuItem(_ path: String) {
        var menu = NSApplication.shared.mainMenu
        let titles = path.split(separator: ">").map(String.init)
        for (depth, title) in titles.enumerated() {
            guard let current = menu else { break }
            current.update()
            guard let index = current.items.firstIndex(where: { $0.title == title }) else {
                log("perform \(path): no item \(title)")
                return
            }
            let item = current.items[index]
            if depth == titles.count - 1 {
                // A process that is not in front cannot read whether an item is enabled: the menus' screenshots show
                // that. The item is chosen as it is, and what it does shows on the screen.
                log("perform \(path)")
                current.performActionForItem(at: index)
                return
            }
            menu = item.submenu
        }
    }
    #endif
}
