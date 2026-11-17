import SwiftUI

/// The app's two addresses on the web, in one place: its privacy policy, and where to ask for help or report a
/// problem. Both open in the browser. On the Mac they are in the Help menu; on iPhone and iPad, in About.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://github.com/chentianren0/new_nine_rings_nov/blob/main/docs/privacy.md")!
    static let support = URL(string: "https://github.com/chentianren0/new_nine_rings_nov/issues")!
}

#if os(macOS)
/// The Help menu's links, after the app's help: support, then the privacy policy.
struct HelpLinks: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Link(destination: AppLinks.support) {
                Text("menu.support", tableName: "Commands")
            }
            Link(destination: AppLinks.privacyPolicy) {
                Text("menu.privacy", tableName: "Commands")
            }
        }
    }
}
#endif
