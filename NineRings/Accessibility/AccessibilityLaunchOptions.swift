import SwiftUI
#if DEBUG && os(macOS)
import AppKit
#endif

/// Debug options for checking the app's accessibility from its own process, without VoiceOver and without touching
/// the system's settings, which belong to the person using the computer. Every option is off in a release build.
///
/// - `-reduce-motion`, `-differentiate-without-color` and `-increase-contrast` force those settings for this process:
///   the app's own views follow them (see ``EnvironmentValues/reducesMotion``). On the Mac, `-increase-contrast` also
///   gives the process the system's high-contrast appearance, so that the system's own controls follow it too.
/// - `-dynamic-type accessibility3` sets the text size, by the names of `DynamicTypeSize` (`xSmall` to
///   `accessibility5`).
/// - `-appearance dark` or `-appearance light` sets the appearance, on iPhone and iPad too (on the Mac the screens'
///   launch options do it).
/// - `-log-announcements` writes each announcement to standard error, as it is posted.
/// - `-print-accessibility-tree 4,10` writes the window's accessibility tree to standard error, 4 and 10 seconds
///   after launch: each element's role, label, value, hint and actions, as VoiceOver gets them. Mac only.
/// - `-tap-rings 3,3,1` asks for those rings, one every 1.5 seconds, from 3 seconds after launch, as taps would.
enum AccessibilityLaunchOptions {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after option: String) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func numbers(after option: String) -> [Double] {
        (value(after: option) ?? "").split(separator: ",").compactMap { Double($0) }
    }

    static let reducesMotion = arguments.contains("-reduce-motion")
    static let differentiatesWithoutColor = arguments.contains("-differentiate-without-color")
    static let increasesContrast = arguments.contains("-increase-contrast")
    private static let logsAnnouncements = arguments.contains("-log-announcements")
    private static let treeTimes = numbers(after: "-print-accessibility-tree")
    private static let tappedRings = numbers(after: "-tap-rings").map(Int.init)

    private static let dynamicTypeSize: DynamicTypeSize? = {
        guard let name = value(after: "-dynamic-type") else { return nil }
        return DynamicTypeSize.allCases.first { String(describing: $0) == name }
    }()

    private static let colorScheme: ColorScheme? = {
        switch value(after: "-appearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }()

    static func logAnnouncement(_ text: String) {
        guard logsAnnouncements else { return }
        log("announce: \(text)")
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// The forced text size and appearance, and the timed checks.
    struct Overrides: ViewModifier {
        func body(content: Content) -> some View {
            content
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if let forced = dynamicTypeSize { size = forced }
                }
                #if os(iOS)
                .preferredColorScheme(colorScheme)
                #endif
                .task {
                    #if os(macOS)
                    // After the screens' own launch options have set the appearance.
                    try? await Task.sleep(for: .milliseconds(300))
                    if increasesContrast { applyHighContrast() }
                    var waited = 0.3
                    for time in treeTimes.sorted() {
                        try? await Task.sleep(for: .seconds(max(time - waited, 0)))
                        waited = max(time, waited)
                        printTree()
                    }
                    #endif
                }
        }
    }

    /// Asks for the rings of `-tap-rings`, one after another.
    struct Taps: ViewModifier {
        let player: Player

        func body(content: Content) -> some View {
            content.task {
                guard !tappedRings.isEmpty else { return }
                try? await Task.sleep(for: .seconds(3))
                for ring in tappedRings where (1...9).contains(ring) {
                    log("tap: ring \(ring)")
                    player.tap(ring)
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
    }

    #if os(macOS)
    private static func applyHighContrast() {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSApplication.shared.appearance = NSAppearance(named: isDark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
    }

    /// Writes the accessibility tree of each visible window, as the app gives it to VoiceOver.
    private static func printTree() {
        log("accessibility tree, \(Date.now.formatted(date: .omitted, time: .standard))")
        for window in NSApplication.shared.windows where window.isVisible {
            log("window \"\(window.title)\"")
            walk(window, depth: 1)
        }
        log("end of tree")
    }

    private static func walk(_ element: Any, depth: Int) {
        guard depth < 60, let node = element as? NSObject else { return }
        var parts: [String] = []
        if bool(node, "isAccessibilityElement", key: "accessibilityElement") {
            parts.append(string(node, "accessibilityRole") ?? "?")
            if let subrole = string(node, "accessibilitySubrole") { parts.append("(\(subrole))") }
            for (name, getter) in [("label", "accessibilityLabel"), ("title", "accessibilityTitle"), ("value", "accessibilityValue"), ("hint", "accessibilityHelp")] {
                if let text = string(node, getter), !text.isEmpty { parts.append("\(name)=\"\(text)\"") }
            }
            if !bool(node, "isAccessibilityEnabled", key: "accessibilityEnabled", otherwise: true) { parts.append("[disabled]") }
            if bool(node, "isAccessibilitySelected", key: "accessibilitySelected") { parts.append("[selected]") }
            if let description = string(node, "accessibilityRoleDescription"), description.contains("heading") { parts.append("[heading]") }
            if let actions = get(node, "accessibilityCustomActions") as? [NSAccessibilityCustomAction], !actions.isEmpty {
                parts.append("actions=[\(actions.map { $0.name }.joined(separator: ", "))]")
            }
            if let frame = (get(node, "accessibilityFrame") as? NSValue)?.rectValue {
                parts.append("@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
            }
        } else if let role = string(node, "accessibilityRole") {
            parts.append("· \(role)")
            if let label = string(node, "accessibilityLabel"), !label.isEmpty { parts.append("label=\"\(label)\"") }
        }
        let shown = !parts.isEmpty
        if shown { log(String(repeating: "  ", count: depth) + parts.joined(separator: " ")) }
        for child in get(node, "accessibilityChildren") as? [Any] ?? [] {
            walk(child, depth: shown ? depth + 1 : depth)
        }
    }

    /// An accessibility attribute, through its getter, when the element has one.
    private static func get(_ node: NSObject, _ getter: String, key: String? = nil) -> Any? {
        guard node.responds(to: NSSelectorFromString(getter)) else { return nil }
        return node.value(forKey: key ?? getter)
    }

    private static func string(_ node: NSObject, _ getter: String) -> String? {
        guard let value = get(node, getter) else { return nil }
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func bool(_ node: NSObject, _ getter: String, key: String, otherwise: Bool = false) -> Bool {
        (get(node, getter, key: key) as? Bool) ?? otherwise
    }
    #endif

    #else
    static let reducesMotion = false
    static let differentiatesWithoutColor = false
    static let increasesContrast = false
    #endif
}

extension View {
    /// Applies `-tap-rings`, in a debug build.
    func accessibilityLaunchTaps(_ player: Player) -> some View {
        #if DEBUG
        modifier(AccessibilityLaunchOptions.Taps(player: player))
        #else
        self
        #endif
    }
}
