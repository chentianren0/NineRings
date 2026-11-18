import SwiftUI

/// The switch for iCloud, in a section of its own after Follow the Move: on at first, as Apple's guidelines say people
/// expect an app to use iCloud by itself. The line under it says what it does; with the switch on and iCloud not
/// available, the line says that instead, quietly, with no alert.
struct ICloudSetting: View {
    /// The settings key, beside the code that uses it.
    static let key = "syncsWithICloud"

    @AppStorage(ICloudSetting.key) private var syncs = true
    @Environment(Keeper.self) private var keeper

    var body: some View {
        Section {
            Toggle(isOn: $syncs) {
                Text("settings.iCloud", tableName: "Screens", comment: "A switch in settings. When on, the finished plays and the toy as it was left go to the person's other devices through iCloud.")
            }
        } footer: {
            if syncs && keeper.iCloudIsUnavailable {
                Text("settings.iCloud.unavailable", tableName: "Screens", comment: "The line under the iCloud switch in settings when it is on but iCloud is not available, as when no account is signed in or iCloud is off for the app.")
            } else {
                Text("settings.iCloud.footer", tableName: "Screens", comment: "The line under the iCloud switch in settings, saying what it does.")
            }
        }
        .onChange(of: syncs) {
            keeper.syncSwitchChanged()
        }
    }
}
