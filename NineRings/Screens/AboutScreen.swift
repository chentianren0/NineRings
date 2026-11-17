import SwiftUI

/// About the app: its icon, its name and its version, and what it is, in three sentences. Nothing else.
struct AboutScreen: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    if let icon = AppInfo.icon {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            #if os(iOS)
                            // The bundle's image is the square artwork; the system rounds it on the Home Screen.
                            .clipShape(.rect(cornerRadius: 22, style: .continuous))
                            #endif
                            .accessibilityHidden(true)
                    }
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
        .navigationTitle(Text("settings.about", tableName: "Screens"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The app's name, version and icon, as the bundle has them.
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

    /// The icon as the system draws it for this app.
    static var icon: Image? {
        #if os(macOS)
        return Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        // The primary icon's name, as the build writes it into the bundle's information.
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let names = [primary?["CFBundleIconName"] as? String] + ((primary?["CFBundleIconFiles"] as? [String])?.reversed().map { $0 } ?? [])
        for case let name? in names {
            if let image = UIImage(named: name) {
                return Image(uiImage: image)
            }
        }
        return nil
        #endif
    }
}

#if os(macOS)
/// The app menu's About item: the system's About panel, with the about text under the name and version, so that it
/// says the same as the About tab in settings.
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
