import SwiftUI
#if os(iOS)
import CoreHaptics
#endif

#if os(iOS)
/// The app's settings on iPhone and iPad: a switch for sounds, and one for haptics where the device has them. It opens
/// from the main screen's menu, as About does beside it, the same idea as the Mac's app menu.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            SettingsSwitches()
        }
        .formStyle(.grouped)
        .navigationTitle(Text("settings.title", tableName: "Screens"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .close) { dismiss() }
            }
        }
    }
}
#endif

/// The switches, in a section of a form: Sounds, and Haptics where the device has haptics. Both are on at first. The
/// view that follows the move has a section of its own below them.
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
        FollowMoveSetting()
        ICloudSetting()
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
/// The Mac's Settings window, opened by Settings… in the app menu: the switches alone, with no tabs, since there is
/// one pane. About is the app menu's own item.
struct SettingsWindow: View {
    var body: some View {
        Form { SettingsSwitches() }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 420)
            .accessibilitySettings()
    }
}
#endif
