import SwiftUI

// A stand-in for settings, which come in a later step, so that the structure around them can be tried now. Its
// words are not translated: it will not ship.

/// Where settings and About will be.
struct SettingsPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(verbatim: "Settings")
            } icon: {
                Image(systemName: "gear")
            }
        } description: {
            Text(verbatim: "Sound, haptics and About come here in a later step.")
        }
        .navigationTitle(Text(verbatim: "Settings"))
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
