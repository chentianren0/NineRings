import Foundation
@testable import Records
import Testing

/// The history between devices, docs/icloud.md section 7, each rule for each state of an entry, on the rules alone.
@Suite struct PlayRulesTests {
    private let record = CloudRecord(
        type: CloudRecord.finishedPlayType, zone: "NineRings-1-00000000-0000-4000-8000-000000000001",
        name: UUID().uuidString, changeTag: "3", systemFields: Data("fields".utf8), format: 1, payload: Data("{}".utf8)
    )

    private func step(_ event: PlayRules.Event, _ state: PlaySyncState?) -> PlayRules.Step {
        PlayRules.step(event, from: state)
    }

    /// Rule 2: an entry that is unsent or sent becomes sent as it is handed over. One that is gone, cleared, or in iCloud
    /// is not wanted: nothing is handed over, and the save is withdrawn.
    @Test func handingOverMakesAnUnconfirmedEntrySent() {
        #expect(step(.handedOver, .unsent).change == .state(.sent))
        #expect(step(.handedOver, .sent).change == .state(.sent))
        for state in [PlaySyncState.inICloud, .cleared] as [PlaySyncState?] + [nil] {
            #expect(step(.handedOver, state) == PlayRules.Step(change: .none, withdrawsSave: true))
        }
    }

    /// Rule 3: the returned record's system fields are kept, and the play is in iCloud. A cleared entry stays cleared. An
    /// entry no longer here comes back as cleared, so that its deletion goes out.
    @Test func anAcceptedRecord() {
        for state in [PlaySyncState.unsent, .sent, .inICloud] {
            #expect(step(.accepted(record), state).change == .systemFields(record, .inICloud))
        }
        #expect(step(.accepted(record), .cleared).change == .systemFields(record, .cleared))
        #expect(step(.accepted(record), nil).change == .comesBackCleared(record))
    }

    /// Rule 4, a record of that name exists: the record in iCloud stands, its content and system fields replace the entry.
    /// A cleared entry stays cleared, and an entry no longer here comes back as cleared.
    @Test func aRefusalBecauseTheRecordExists() {
        for state in [PlaySyncState.unsent, .sent, .inICloud] {
            #expect(step(.refusedAsExisting(serverRecord: record), state).change == .content(record, .inICloud))
        }
        #expect(step(.refusedAsExisting(serverRecord: record), .cleared).change == .systemFields(record, .cleared))
        #expect(step(.refusedAsExisting(serverRecord: record), nil).change == .comesBackCleared(record))
    }

    /// Without the record, the entry becomes in iCloud with what it has, and the engine is asked to fetch.
    @Test func aRefusalWithoutTheRecordFetches() {
        #expect(step(.refusedAsExisting(serverRecord: nil), .unsent) == PlayRules.Step(change: .state(.inICloud), fetches: true))
        #expect(step(.refusedAsExisting(serverRecord: nil), .sent) == PlayRules.Step(change: .state(.inICloud), fetches: true))
        #expect(step(.refusedAsExisting(serverRecord: nil), .cleared) == PlayRules.Step(change: .none, fetches: true))
        #expect(step(.refusedAsExisting(serverRecord: nil), nil) == PlayRules.Step(change: .comesBackCleared(nil), fetches: true))
    }

    /// Rule 4, iCloud does not know the record: the entry is removed, as when its deletion arrives.
    @Test func aRefusalBecauseTheRecordIsNotKnown() {
        for state in PlaySyncState.allCases as [PlaySyncState?] + [nil] {
            #expect(step(.refusedAsUnknown, state) == step(.deletionArrived, state))
        }
        #expect(step(.refusedAsUnknown, .sent).change == .remove)
    }

    /// Rule 5: an arriving play is added, or replaces the entry, as in iCloud. A cleared entry stays cleared.
    @Test func anArrivingPlay() {
        for state in [PlaySyncState.unsent, .sent, .inICloud] as [PlaySyncState?] + [nil] {
            #expect(step(.arrived(record), state).change == .content(record, .inICloud))
        }
        #expect(step(.arrived(record), .cleared).change == .systemFields(record, .cleared))
    }

    /// Rule 6: an arriving deletion removes the entry. An unsent entry stays, because iCloud never had it; a cleared one's
    /// own deletion is withdrawn.
    @Test func anArrivingDeletion() {
        #expect(step(.deletionArrived, .unsent).change == .none)
        #expect(step(.deletionArrived, nil).change == .none)
        #expect(step(.deletionArrived, .sent) == PlayRules.Step(change: .remove, withdrawsSave: true))
        #expect(step(.deletionArrived, .inICloud) == PlayRules.Step(change: .remove, withdrawsSave: true))
        #expect(step(.deletionArrived, .cleared) == PlayRules.Step(change: .remove, withdrawsDeletion: true))
    }

    /// Rule 7: clearing removes unsent entries at once and clears the rest; a save still queued is withdrawn either way.
    @Test func clearing() {
        #expect(step(.clearing, .unsent) == PlayRules.Step(change: .remove, withdrawsSave: true))
        #expect(step(.clearing, .sent) == PlayRules.Step(change: .state(.cleared), withdrawsSave: true))
        #expect(step(.clearing, .inICloud) == PlayRules.Step(change: .state(.cleared), withdrawsSave: true))
        #expect(step(.clearing, .cleared).change == .none)
    }

    /// When iCloud confirms a deletion, or reports the record already gone, a cleared entry is removed for good.
    @Test func anAnsweredDeletion() {
        #expect(step(.deletionAnswered, .cleared).change == .remove)
        for state in [PlaySyncState.unsent, .sent, .inICloud] { #expect(step(.deletionAnswered, state).change == .none) }
    }

    /// When a start from nothing begins, every play in iCloud goes back to sent, and cleared entries stay cleared
    /// (section 8).
    @Test func aStartFromNothing() {
        #expect(step(.startFromNothing, .inICloud).change == .state(.sent))
        for state in [PlaySyncState.unsent, .sent, .cleared] { #expect(step(.startFromNothing, state).change == .none) }
    }
}
