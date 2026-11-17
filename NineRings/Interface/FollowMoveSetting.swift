import SwiftUI

/// The setting for the view that follows the move, in a section of its own with a line on what it does. Off at
/// first: the picture stays still while moves play.
///
/// With Reduce Motion on, the view stays still whatever the switch says: the switch is dimmed, and its line says so.
struct FollowMoveSetting: View {
    @AppStorage(Framing.followsMoveKey) private var followsMove = false
    @Environment(\.reducesMotion) private var reducesMotion

    var body: some View {
        Section {
            Toggle(isOn: $followsMove) {
                Text("Follow the Move", comment: "A switch in settings. When on, the view of the toy widens while a ring moves, so that the sword stays in sight as it is drawn back.")
            }
            .disabled(reducesMotion)
        } footer: {
            if reducesMotion {
                Text("followMove.reduceMotion", tableName: "Accessibility")
            } else {
                Text("While a ring moves, the view widens to keep the sword in sight.", comment: "The line under the Follow the Move switch in settings, saying what it does.")
            }
        }
    }
}
