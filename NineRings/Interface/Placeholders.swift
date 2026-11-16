import SwiftUI

// Stand-ins for the lesson and settings, which come in later steps, so that the structure around them can be tried
// now. Their words are not translated: they will not ship.

/// Where the lesson on how the puzzle works will be.
struct LessonPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text(verbatim: "Lesson")
            } icon: {
                Image(systemName: "book")
            }
        } description: {
            Text(verbatim: "How the puzzle works comes here in a later step.")
        }
        .navigationTitle(Text(verbatim: "Lesson"))
    }
}

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
