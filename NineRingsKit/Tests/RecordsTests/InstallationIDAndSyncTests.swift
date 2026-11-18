import Foundation
@testable import Records
import Testing

/// The installation's id, from the keychain, the copy left out of backups and the device's store; and what the app does
/// with its two stores as sync goes on and off.
@Suite struct InstallationIDAndSyncTests {
    typealias Copy = InstallationID.Copy

    private func resolve(keychain: Copy, apart: Copy, store: String?) -> InstallationID.Resolution {
        InstallationID.resolve(keychain: keychain, leftOutOfBackups: apart, store: store) { "NEW" }
    }

    /// A new id, written to every place that can be used, and given the store's toy when it keeps one.
    private func newID(from store: String?, keychain: Bool = true, apart: Bool = true) -> InstallationID.Resolution {
        .init(id: "NEW", writesKeychain: keychain, writesCopyLeftOutOfBackups: apart, givesToyFrom: store)
    }

    private let kept = InstallationID.Resolution(id: "A", writesKeychain: false, writesCopyLeftOutOfBackups: false, givesToyFrom: nil)

    // MARK: The installation's id

    @Test func theIDStandsWhenEveryPlaceHoldsTheStoresID() {
        #expect(resolve(keychain: .holds("A"), apart: .holds("A"), store: "A") == kept)
    }

    @Test func aFirstLaunchMakesAnID() {
        #expect(resolve(keychain: .holdsNone, apart: .holdsNone, store: nil) == newID(from: nil))
    }

    /// A store restored from another device's backup keeps a toy under that device's id, and the keychain here has none,
    /// or another: the installation takes a new id, and the toy goes on under it.
    @Test(arguments: [Copy.holdsNone, .holds("B")])
    func aStoreFromAnotherDeviceGivesItsToyToANewID(keychain: Copy) {
        #expect(resolve(keychain: keychain, apart: .holdsNone, store: "A") == newID(from: "A"))
        #expect(resolve(keychain: keychain, apart: .holds("B"), store: "A") == newID(from: "A"))
    }

    /// A store restored onto the same device: the keychain item comes back with it, but the copy left out of backups does
    /// not, and the store's count of changes went back to the backup's. The installation takes a new id, and the toy goes
    /// on under it, so that no change is named twice.
    @Test func aStoreRestoredOntoTheSameDeviceGivesItsToyToANewID() {
        #expect(resolve(keychain: .holds("A"), apart: .holdsNone, store: "A") == newID(from: "A"))
    }

    /// The keychain's id with no toy in the store, as after the app was removed and installed again: the store's count of
    /// changes is lost, so the id is not taken up again.
    @Test func anIDWhoseStoreIsGoneIsNotTakenUpAgain() {
        #expect(resolve(keychain: .holds("A"), apart: .holds("A"), store: nil) == newID(from: nil))
    }

    /// A place that cannot be used is left out, and nothing is written there.
    @Test func aPlaceThatCannotBeUsedIsLeftOut() {
        #expect(resolve(keychain: .unusable, apart: .holds("A"), store: "A") == kept)
        #expect(resolve(keychain: .holds("A"), apart: .unusable, store: "A") == kept)
        #expect(resolve(keychain: .unusable, apart: .unusable, store: "A") == kept)
        #expect(resolve(keychain: .unusable, apart: .holdsNone, store: "A") == newID(from: "A", keychain: false))
        #expect(resolve(keychain: .holdsNone, apart: .unusable, store: "A") == newID(from: "A", apart: false))
        #expect(resolve(keychain: .unusable, apart: .unusable, store: nil) == newID(from: nil, keychain: false, apart: false))
    }

    // MARK: The copy left out of backups

    @Test func theCopyLeftOutOfBackupsIsReadAsWritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NineRings test \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = InstallationID.CopyLeftOutOfBackups(folder: folder)
        #expect(copy.read() == .holdsNone, "none before it is written, as after a restore")
        #expect(copy.write("A"))
        #expect(copy.read() == .holds("A"))
        #expect(copy.write("B"))
        #expect(copy.read() == .holds("B"))
        let values = try RecordStore.cloudFolder(in: folder).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true, "its folder is left out of backups")
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
