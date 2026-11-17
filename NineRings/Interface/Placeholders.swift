import SwiftUI

// A stand-in for the lesson, which comes in a later step, so that the structure around it can be tried now. Its
// words are not translated: it will not ship.

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
