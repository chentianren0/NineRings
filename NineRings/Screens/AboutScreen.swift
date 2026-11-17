import SwiftUI

#if os(iOS)
/// About the app on iPhone and iPad: its icon, its name and its version, what it is in three sentences, and links to
/// support and the privacy policy. It opens from the main screen's menu, beside Settings. On the Mac, About Nine Rings
/// in the app menu shows the system's About panel with the same words, and the links are in the Help menu.
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    // A copy of the app icon, rendered from it by scripts/render-about-icon.sh. An iOS app cannot load
                    // its own icon: UIImage(named: "AppIcon") works in a local build but crashes the app from TestFlight
                    // and the App Store, where the icon is processed again for each device.
                    Image("AboutIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text(verbatim: AppInfo.name)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: AppInfo.version)
                        .font(.subheadline)
                        .supportingTextStyle()
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
            // Where to ask for help, and the privacy policy: on the Mac, the Help menu holds them.
            Section {
                Link(destination: AppLinks.support) {
                    Text("about.support", tableName: "Screens")
                }
                Link(destination: AppLinks.privacyPolicy) {
                    Text("about.privacy", tableName: "Screens")
                }
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
    /// The name the bundle shows, in the app's language where the bundle has one, or else the app's name as written.
    /// The bundle's own name is the product's, "NineRings", which is not the name to show.
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? String(localized: "about.name", table: "Screens")
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
            .font: NSFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: NSColor.labelColor,
        ])
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: AppInfo.name, .credits: credits])
    }
}
#endif
