import Accessibility
import Session

/// Says things aloud to someone using VoiceOver, when something changes that they did not move to: the narration of
/// the toy (see ``Narration``), the lesson's step, the congratulation.
///
/// Each announcement interrupts the one before, so that what is said is what is happening now.
enum Announcer {
    static func say(_ narration: Narration) {
        guard !narration.isEmpty else { return }
        say(Spoken.narration(narration))
    }

    static func say(_ text: String) {
        #if DEBUG
        AccessibilityLaunchOptions.logAnnouncement(text)
        #endif
        AccessibilityNotification.Announcement(text).post()
    }
}
