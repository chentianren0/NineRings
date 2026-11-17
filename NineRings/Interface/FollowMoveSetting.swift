import SwiftUI

/// The setting for the view that follows the move, in a section of its own with a line on what it does. Off at
/// first: the picture stays still while moves play.
struct FollowMoveSetting: View {
    @AppStorage(Framing.followsMoveKey) private var followsMove = false

    var body: some View {
        Section {
            Toggle(isOn: $followsMove) {
                Text("Follow the Move", comment: "A switch in settings. When on, the view of the toy widens while a ring moves, so that the sword stays in sight as it is drawn back.")
            }
        } footer: {
            Text("While a ring moves, the view widens to keep the sword in sight.", comment: "The line under the Follow the Move switch in settings, saying what it does.")
        }
    }
}
