import SwiftUI

#if os(iOS)
/// About the app on iPhone and iPad: its name and its version, and what it is, in three sentences. Nothing
/// else. It opens from the main screen's menu, beside Settings; on the Mac, About Nine Rings in the app menu shows the
/// system's About panel with the same words.
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    // No icon: loading the app's icon by name crashes on iOS 27 with an icon made in Icon Composer
                    // (UIKit asserts while building the image), and there is no other public way to get it.
                    Text(verbatim: AppInfo.name)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: AppInfo.version)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)
            Section {
                Text("about.text", tableName: "Screens")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .close) { dismiss() }
            }
        }
    }
}
#endif

/// The app's name and version, as the bundle has them.
enum AppInfo {
    /// The name the bundle shows, or else the app's name as written. The bundle's own name is the product's,
    /// "NineRings", which is not the name to show.
    static var name: String {
        let info = Bundle.main.localizedInfoDictionary ?? Bundle.main.infoDictionary ?? [:]
        return info["CFBundleDisplayName"] as? String ?? String(localized: "about.name", table: "Screens")
    }

    /// "Version 1.0 (1)": the marketing version and the build number.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return String(localized: "about.version \(version) \(build)", table: "Screens")
    }

}

#if os(macOS)
/// The app menu's About item: the system's About panel, the Mac's own form for it, with the about text under the
/// name and version.
struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                Self.showPanel()
            } label: {
                Text("menu.about", tableName: "Screens")
            }
        }
    }

    @MainActor
    static func showPanel() {
        let text = String(localized: "about.text", table: "Screens")
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: AppInfo.name, .credits: credits])
    }
}
#endif
