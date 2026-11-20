@testable import Records
import SwiftData

extension RecordStore {
    /// A store over `container` for a suite to hold: its main context saves only when a test saves it.
    ///
    /// Swift Testing releases a suite's instance on a thread of its own, not on the main actor. A container released
    /// there can meet its main context's autosave timer on the main thread, which then traps inside SwiftData: the timer
    /// fires about 15 seconds after an unsaved change, so a suite that runs that long meets it now and then. A store
    /// made inside a test is released on the main actor and needs nothing.
    static func heldBySuite(_ container: ModelContainer) -> RecordStore {
        container.mainContext.autosaveEnabled = false
        return RecordStore(container: container)
    }
}
