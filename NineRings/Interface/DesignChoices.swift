import SwiftUI

// Alternatives the owner compares while the design is open. In a debug build, the Design menu (the ladybug in
// the toolbar) switches between them while the app runs, and the choice is kept between launches; a launch
// argument such as `-design.navigation tabBar` sets one too. A release build always has the first case of each.
//
// The menu's words are not translated: they exist only while the design is being decided.

/// Whether the app has a tab bar.
enum NavigationDesign: String, CaseIterable, Identifiable {
    /// One screen; the lesson and settings open from its toolbar.
    case none
    /// Tabs for the puzzle, the lesson and settings.
    case tabBar

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "No tab bar"
        case .tabBar: "Tab bar"
        }
    }
}

/// Where the controls go when the window is wide.
enum WideDesign: String, CaseIterable, Identifiable {
    /// A panel floating at the bottom, over the toy, as on a phone.
    case floating
    /// A column at the trailing side, beside the toy.
    case column

    var id: Self { self }

    var title: String {
        switch self {
        case .floating: "Controls at the bottom"
        case .column: "Controls in a side column"
        }
    }
}

/// Where the toy is first seen from when its space is taller than wide, such as on an upright phone.
enum TallViewDesign: String, CaseIterable, Identifiable {
    /// From the side, as in a wide space, framed on the rings.
    case side
    /// From above, between the side and the tip.
    case threeQuarter
    /// From above, nearly along the toy from the tip end, so that it runs up the screen.
    case along

    var id: Self { self }

    var title: String {
        switch self {
        case .side: "Side"
        case .threeQuarter: "Three-quarter, from above"
        case .along: "Along the toy, from above"
        }
    }

    var angles: CameraAngles {
        switch self {
        case .side: CameraAngles(.side)
        case .threeQuarter: .degrees(yaw: -45, pitch: 30)
        case .along: .degrees(yaw: -70, pitch: 35)
        }
    }
}

/// The keys the choices are kept under.
enum DesignKey {
    static let navigation = "design.navigation"
    static let wide = "design.wide"
    static let tallView = "design.tallView"
}

#if DEBUG
/// The debug build's menu of the alternatives.
struct DesignMenu: View {
    @AppStorage(DesignKey.navigation) private var navigation = NavigationDesign.none
    @AppStorage(DesignKey.wide) private var wide = WideDesign.floating
    @AppStorage(DesignKey.tallView) private var tallView = TallViewDesign.side

    var body: some View {
        Menu {
            Picker(selection: $navigation) {
                ForEach(NavigationDesign.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Navigation")
            }
            Picker(selection: $wide) {
                ForEach(WideDesign.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Wide window")
            }
            Picker(selection: $tallView) {
                ForEach(TallViewDesign.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Tall window: first view")
            }
            SoundBenchMenu()
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
