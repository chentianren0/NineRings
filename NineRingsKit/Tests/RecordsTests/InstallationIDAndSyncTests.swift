@testable import Records
import Testing

/// The installation's id, from the keychain and the device's store; and what the app does with its two stores as sync
/// goes on and off.
@Suite struct InstallationIDAndSyncTests {
    private func resolve(_ keychain: InstallationID.Keychain, store: String?) -> InstallationID.Resolution {
        InstallationID.resolve(keychain: keychain, store: store) { "NEW" }
    }

    // MARK: The installation's id

    @Test func theKeychainsIDIsKeptWhenTheStoreHasItToo() {
        #expect(resolve(.holds("A"), store: "A") == .init(id: "A", writesKeychain: false, givesToyFrom: nil))
    }

    @Test func aFirstLaunchMakesAnID() {
        #expect(resolve(.holdsNone, store: nil) == .init(id: "NEW", writesKeychain: true, givesToyFrom: nil))
    }

    /// A store restored from another device's backup keeps a toy under that device's id, and the keychain here has none,
    /// or another: the installation takes a new id, and the toy goes on under it.
    @Test(arguments: [InstallationID.Keychain.holdsNone, .holds("B")])
    func aStoreFromAnotherDeviceGivesItsToyToANewID(keychain: InstallationID.Keychain) {
        #expect(resolve(keychain, store: "A") == .init(id: "NEW", writesKeychain: true, givesToyFrom: "A"))
    }

    /// The keychain's id with no toy in the store, as after the app was removed and installed again: the store's count of
    /// changes is lost, so the id is not taken up again.
    @Test func anIDWhoseStoreIsGoneIsNotTakenUpAgain() {
        #expect(resolve(.holds("A"), store: nil) == .init(id: "NEW", writesKeychain: true, givesToyFrom: nil))
    }

    /// Without a keychain, the store's id stays, and nothing is written.
    @Test func withoutAKeychainTheStoresIDStays() {
        #expect(resolve(.unusable, store: "A") == .init(id: "A", writesKeychain: false, givesToyFrom: nil))
        #expect(resolve(.unusable, store: nil) == .init(id: "NEW", writesKeychain: false, givesToyFrom: nil))
    }

    // MARK: Sync going on and off

    private func steps(on: Bool, available: Bool, open: Bool, copyDue: Bool = false) -> [SyncRule.Step] {
        SyncRule.steps(switchIsOn: on, isAvailable: available, isOpen: open, copyIsDue: copyDue)
    }

    /// At a launch, by the switch, or by iCloud coming back: the iCloud store opens and the device's plays move there.
    @Test func syncGoingOnOpensTheStoreAndMovesThePlays() {
        #expect(steps(on: true, available: true, open: false) == [.openICloudStore, .moveToICloud])
        #expect(steps(on: true, available: true, open: true) == [])
        #expect(SyncRule.isOn(switchIsOn: true, isAvailable: true))
    }

    /// The switch going off copies the plays to the device first, then lets the store go.
    @Test func theSwitchGoingOffCopiesThenLetsGo() {
        #expect(steps(on: false, available: true, open: true) == [.copyToDevice, .letGoOfICloudStore])
        #expect(!SyncRule.isOn(switchIsOn: false, isAvailable: true))
    }

    /// With the switch off, the iCloud store is not opened at all.
    @Test func withTheSwitchOffTheStoreStaysClosed() {
        #expect(steps(on: false, available: true, open: false) == [])
        #expect(steps(on: false, available: false, open: false) == [])
    }

    /// iCloud going away lets the store go, copying nothing; with iCloud away nothing opens, whatever the switch says.
    @Test func iCloudGoingAwayLetsGoWithoutCopying() {
        #expect(steps(on: true, available: false, open: true) == [.letGoOfICloudStore])
        #expect(steps(on: false, available: false, open: true) == [.letGoOfICloudStore])
        #expect(steps(on: true, available: false, open: false) == [])
        #expect(!SyncRule.isOn(switchIsOn: true, isAvailable: false))
    }

    /// A copy cut short is taken up at the next launch with iCloud available, the store opened just for it.
    @Test func aCopyCutShortIsTakenUpWhenICloudIsAvailable() {
        #expect(steps(on: false, available: true, open: false, copyDue: true) == [.openICloudStore, .copyToDevice, .letGoOfICloudStore])
        #expect(steps(on: false, available: false, open: false, copyDue: true) == [], "it waits for iCloud")
    }

    /// With the switch on again before the copy was taken up, the copy is no longer needed.
    @Test func aCopyIsForgottenWhenTheSwitchIsOnAgain() {
        #expect(steps(on: true, available: true, open: false, copyDue: true) == [.openICloudStore, .moveToICloud, .forgetCopy])
        #expect(steps(on: true, available: true, open: true, copyDue: true) == [.forgetCopy])
    }

    /// Doing the steps leads to a state that needs none.
    @Test(arguments: [false, true], [false, true])
    func theStepsSettle(on: Bool, available: Bool) {
        for open in [false, true] {
            for copyDue in [false, true] {
                var isOpen = open
                var due = copyDue
                for step in steps(on: on, available: available, open: isOpen, copyDue: due) {
                    switch step {
                    case .openICloudStore: isOpen = true
                    case .moveToICloud: break
                    case .copyToDevice: due = false
                    case .letGoOfICloudStore: isOpen = false
                    case .forgetCopy: due = false
                    }
                }
                #expect(steps(on: on, available: available, open: isOpen, copyDue: due) == [])
                #expect(isOpen == (on && available), "the store is open exactly while sync is on")
                if available { #expect(!due) }
            }
        }
    }
}
