import SwiftUI

/// The setting for the count of moves left in the control panel, in a section of its own with a line on what it shows.
/// On at first.
struct MovesLeftSetting: View {
    @AppStorage(MovesLeft.isShownKey) private var showsMovesLeft = true

    var body: some View {
        Section {
            Toggle(isOn: $showsMovesLeft) {
                Text("settings.movesLeft", tableName: "Screens")
            }
        } footer: {
            Text("settings.movesLeft.detail", tableName: "Screens")
        }
    }
}
