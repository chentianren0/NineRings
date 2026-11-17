import Session
import SwiftUI

/// The lesson's panel: where you are in the steps, the step's text, play again where the step plays something, back
/// and next, and a way to close. The toy beside it shows what the text says.
///
/// Where the panel sits is the screen's business: it works in an inspector and in a tab, and its text scrolls, so
/// that it reads at every text size.
struct LessonPanel: View {
    let player: Player
    let guide: LessonGuide
    /// Closes the lesson, where the panel offers that; nil where leaving the panel's place closes it, as a tab does.
    var close: (() -> Void)?

    var body: some View {
        if let page = player.lessonPage {
            content(page)
        } else {
            // Only for the moment the toy is covered while the lesson opens.
            Color.clear
        }
    }

    private func content(_ page: LessonRun.Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(page)
                Text(Self.text(page))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if page.canReplay {
                    Button(action: guide.replay) {
                        Label {
                            Text("Play Again", comment: "Lesson button that plays the step's move again from the start.")
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        // A new step starts at the top of its text.
        .id(page.index)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigation(page)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: page.index)
        .onChange(of: page.index) {
            // The text changed under the button that was pressed: say it to someone who cannot see it.
            AccessibilityNotification.Announcement(String(localized: Self.text(page))).post()
        }
    }

    private func header(_ page: LessonRun.Page) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lesson", comment: "Title of the lesson's panel.")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Step \(page.index + 1) of \(page.count)", comment: "Where the reader is in the lesson. The first variable is the step's number, the second how many steps there are.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let close {
                Button(action: close) {
                    Label {
                        Text("Close", comment: "Button that closes the lesson.")
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .help(Text("Close the lesson", comment: "Tooltip on the lesson's Close button."))
            }
        }
    }

    /// Back and next side by side, or one above the other where the text is too large for that.
    private func navigation(_ page: LessonRun.Page) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                backButton(page)
                Spacer(minLength: 12)
                nextButton(page)
            }
            VStack(spacing: 8) {
                nextButton(page).frame(maxWidth: .infinity)
                backButton(page).frame(maxWidth: .infinity)
            }
        }
        .controlSize(.large)
    }

    private func backButton(_ page: LessonRun.Page) -> some View {
        Button(action: guide.goBack) {
            Label {
                Text("Back", comment: "Lesson button that goes to the step before.")
            } icon: {
                Image(systemName: "chevron.backward")
            }
        }
        .buttonStyle(.bordered)
        .disabled(!page.canGoBack)
    }

    @ViewBuilder
    private func nextButton(_ page: LessonRun.Page) -> some View {
        if page.isLast, let close {
            Button(action: close) {
                Text("Done", comment: "Lesson button on the last step that closes the lesson.")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        } else {
            Button(action: guide.goForward) {
                Label {
                    Text("Next", comment: "Lesson button that goes to the next step.")
                } icon: {
                    Image(systemName: "chevron.forward")
                }
                .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!page.canGoForward)
        }
    }

    /// The step's text, from the lesson's String Catalog.
    static func text(_ page: LessonRun.Page) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(page.key), table: "Lesson")
    }
}

/// A label with its icon after its title, as on a button that goes forward.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
