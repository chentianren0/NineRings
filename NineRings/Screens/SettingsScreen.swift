import SwiftUI
#if os(iOS)
import CoreHaptics
#endif

/// The app's settings on iPhone and iPad: a switch for sounds, one for haptics where the device has them, and the way
/// into About. Whoever shows it puts it in a navigation stack; as a sheet it has a close button.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        Form {
            SettingsSwitches()
            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    Text("settings.about", tableName: "Screens")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("settings.title", tableName: "Screens"))
        #if os(iOS)
        .toolbar {
            if isPresented {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        #endif
    }
}

/// The switches, in a section of a form: Sounds, and Haptics where the device has haptics. Both are on at first.
struct SettingsSwitches: View {
    @AppStorage(ScreenKey.sounds) private var sounds = true
    @AppStorage(ScreenKey.haptics) private var haptics = true

    var body: some View {
        Section {
            Toggle(isOn: $sounds) {
                Text("settings.sounds", tableName: "Screens")
            }
            if Haptics.isAvailable {
                Toggle(isOn: $haptics) {
                    Text("settings.haptics", tableName: "Screens")
                }
            }
        }
    }
}

/// Whether this device can make haptics: iPhone can, iPad cannot. The Mac gets none from this app.
enum Haptics {
    static let isAvailable: Bool = {
        #if DEBUG
        if ScreenLaunchOptions.showsHaptics { return true }
        #endif
        #if os(iOS)
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
        return false
        #endif
    }()
}

#if os(macOS)
/// The Mac's Settings window: a General tab with the switches, and an About tab.
struct SettingsWindow: View {
    enum Tab: String { case general, about }

    @State private var tab = ScreenLaunchOptions.settingsTab ?? .general

    var body: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab(value: Tab.general) {
                Form { SettingsSwitches() }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Label { Text("settings.general", tableName: "Screens") } icon: { Image(systemName: "gearshape") }
            }
            SwiftUI.Tab(value: Tab.about) {
                AboutScreen()
            } label: {
                Label { Text("settings.about", tableName: "Screens") } icon: { Image(systemName: "info.circle") }
            }
        }
        .frame(width: 460)
    }
}
#endif
