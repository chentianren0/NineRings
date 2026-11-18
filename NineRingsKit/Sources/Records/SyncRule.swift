/// What the app does with its two stores as sync goes on and off.
///
/// Sync is on when the switch is on and iCloud is available to the app: an account signed in, and iCloud not switched
/// off for the app. The rules:
/// - **Going on**, at a launch, by the switch, or by iCloud coming back: the iCloud store is opened and the device's
///   finished plays are moved there. A move cut short is taken up at the next opening, since the device's store then
///   still holds what was not moved.
/// - **The switch going off**: the iCloud store's plays are first copied to the device's store, then the store is let go,
///   so that nothing more is sent. The copy is due from before it starts until it has finished: one cut short is taken up
///   at the next launch with iCloud available, which opens the iCloud store just long enough to finish it. With the
///   switch on again first, the copy is no longer needed: the iCloud store holds the plays.
/// - **iCloud going away**: the iCloud store is let go, and nothing is copied. Its plays are not shown until iCloud is
///   back, and none is deleted.
/// - With sync off the iCloud store is not opened, except to finish a copy that is due.
public enum SyncRule {
    /// One thing to do.
    public enum Step: Sendable, Equatable {
        case openICloudStore
        /// Move the device's finished plays to the iCloud store.
        case moveToICloud
        /// Copy the iCloud store's finished plays to the device's store. The copy is due from before this step until it
        /// has finished.
        case copyToDevice
        case letGoOfICloudStore
        /// The copy is no longer due.
        case forgetCopy
    }

    /// What to do, in order, when the switch is `switchIsOn`, iCloud `isAvailable`, the iCloud store `isOpen`, and a copy
    /// to the device's store `copyIsDue`. Nothing, when all is as it should be.
    public static func steps(switchIsOn: Bool, isAvailable: Bool, isOpen: Bool, copyIsDue: Bool) -> [Step] {
        guard isAvailable else { return isOpen ? [.letGoOfICloudStore] : [] }
        if switchIsOn {
            return (isOpen ? [] : [.openICloudStore, .moveToICloud]) + (copyIsDue ? [.forgetCopy] : [])
        }
        if isOpen { return [.copyToDevice, .letGoOfICloudStore] }
        return copyIsDue ? [.openICloudStore, .copyToDevice, .letGoOfICloudStore] : []
    }

    /// Whether sync is on: the finished plays are written to the iCloud store and read from it.
    public static func isOn(switchIsOn: Bool, isAvailable: Bool) -> Bool {
        switchIsOn && isAvailable
    }
}
