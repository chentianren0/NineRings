import SwiftUI

// Alternatives kept open for the owner's review. In a debug build, the Design menu (the ladybug in the toolbar)
// switches between them while the app runs, and the choice is kept between launches; a launch argument such as
// `-design.tallView side` sets one too. A release build always has the standard choice.
//
// The menu's words are not translated: they exist only while the design is being reviewed.

/// Where the toy is first seen from when its space is taller than wide, such as on an upright phone.
enum TallViewDesign: String, CaseIterable, Identifiable {
    /// From above, between the side and the tip, so that the long toy is foreshortened and seen larger, with ring 1
    /// still on the left, as on the buttons.
    case threeQuarter
    /// From the side, as in a wide space.
    case side
    /// From above, nearly along the toy from the tip end, so that it runs up the screen.
    case along

    /// The choice a release build has.
    static let standard = TallViewDesign.threeQuarter

    var id: Self { self }

    var title: String {
        switch self {
        case .threeQuarter: "Three-quarter, from above"
        case .side: "Side"
        case .along: "Along the toy, from above"
        }
    }

    var angles: CameraAngles {
        switch self {
        case .threeQuarter: .degrees(yaw: -45, pitch: 30)
        case .side: CameraAngles(.side)
        case .along: .degrees(yaw: -70, pitch: 35)
        }
    }
}

/// The keys the choices are kept under.
enum DesignKey {
    static let tallView = "design.tallView"
}

#if DEBUG
/// The debug build's menu of the alternatives.
struct DesignMenu: View {
    @AppStorage(DesignKey.tallView) private var tallView = TallViewDesign.standard

    var body: some View {
        Menu {
            Picker(selection: $tallView) {
                ForEach(TallViewDesign.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Tall window: first view")
            }
        } label: {
            Label {
                Text(verbatim: "Design")
            } icon: {
                Image(systemName: "ladybug")
            }
        }
        .pickerStyle(.inline)
    }
}
#endif
