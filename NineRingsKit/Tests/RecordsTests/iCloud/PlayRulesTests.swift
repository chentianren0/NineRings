import Foundation
@testable import Records
import Testing

/// The history between devices, docs/icloud.md section 7, rule by rule, for an entry in each state: unsent, sent, in
/// iCloud, cleared, or none at all.
@Suite struct PlayRulesTests {
    private let record = CloudRecord(
        type: CloudRecord.finishedPlayType, name: UUID().uuidString, changeTag: "3", systemFields: nil, format: 1, payload: Data()
    )

    private func step(_ event: PlayRules.Event, _ state: PlaySyncState?) -> PlayRules.Step {
        PlayRules.step(event, from: state)
    }

    /// Rule 2: when the engine asks for the record, an entry that iCloud has not confirmed becomes sent; any other gives
    /// no record.
    @Test func handingOverMakesAnUnconfirmedEntrySent() {
        #expect(step(.handedOver, .unsent).change == .state(.sent))
        #expect(step(.handedOver, .sent).change == .state(.sent))
        #expect(step(.handedOver, .inICloud).change == .none)
        #expect(step(.handedOver, .cleared).change == .none)
        #expect(step(.handedOver, nil).change == .none)
    }

    /// Rule 3: iCloud accepts the record, and the play becomes in iCloud. A cleared entry stays cleared, its deletion on
    /// its way.
    @Test func anAcceptedRecordIsInICloud() {
        #expect(step(.accepted(record), .unsent).change == .state(.inICloud))
        #expect(step(.accepted(record), .sent).change == .state(.inICloud))
        #expect(step(.accepted(record), .inICloud).change == .none)
        #expect(step(.accepted(record), .cleared).change == .none)
    }

    /// An entry removed here when a deletion arrived while its save was out: the save may have brought the record back,
    /// so the entry comes back as cleared and its deletion is queued.
    @Test func anAcceptedRecordNoLongerHereComesBackCleared() {
        #expect(step(.accepted(record), nil) == PlayRules.Step(change: .content(record, .cleared), queuesDeletion: true))
    }

    /// Rule 4: iCloud refuses the record because one of that name exists. The record in iCloud stands, and its content
    /// replaces the entry here, which becomes in iCloud.
    @Test func aRefusedRecordTakesICloudsContent() {
        for state: PlaySyncState? in [.unsent, .sent, .inICloud, nil] {
            #expect(step(.refused(serverRecord: record), state).change == .content(record, .inICloud))
        }
        #expect(step(.refused(serverRecord: record), .cleared).change == .none)
    }

    /// A refusal without iCloud's record: the entry becomes in iCloud with its own content, and the engine fetches.
    @Test func aRefusalWithoutTheRecordFetches() {
        #expect(step(.refused(serverRecord: nil), .unsent) == PlayRules.Step(change: .state(.inICloud), fetches: true))
        #expect(step(.refused(serverRecord: nil), .sent) == PlayRules.Step(change: .state(.inICloud), fetches: true))
        #expect(step(.refused(serverRecord: nil), .cleared).change == .none)
        #expect(step(.refused(serverRecord: nil), nil) == PlayRules.Step(change: .none, fetches: true))
    }

    /// Rule 5: a finished play arrives. It is added, or replaces the entry of the same id, as in iCloud. An entry that is
    /// cleared stays cleared.
    @Test func anArrivingPlayIsInICloud() {
        for state: PlaySyncState? in [nil, .unsent, .sent, .inICloud] {
            #expect(step(.arrived(record), state).change == .content(record, .inICloud))
        }
        #expect(step(.arrived(record), .cleared).change == .none)
    }

    /// Rule 6: a deletion arrives and the entry is removed. An unsent entry stays, because iCloud never had it; a cleared
    /// entry goes, and its queued deletion is withdrawn.
    @Test func anArrivingDeletionRemovesTheEntry() {
        #expect(step(.deletionArrived, .unsent).change == .none)
        #expect(step(.deletionArrived, .sent).change == .remove)
        #expect(step(.deletionArrived, .inICloud).change == .remove)
        #expect(step(.deletionArrived, .cleared) == PlayRules.Step(change: .remove, withdrawsDeletion: true))
        #expect(step(.deletionArrived, nil).change == .none)
    }

    /// Rule 7: the person clears the history. Unsent entries are removed at once; every other entry becomes cleared, and
    /// its deletion is queued, a sent one too, since iCloud may have it.
    @Test func clearingRemovesUnsentAndClearsTheRest() {
        #expect(step(.clearing, .unsent).change == .remove)
        #expect(step(.clearing, .sent) == PlayRules.Step(change: .state(.cleared), queuesDeletion: true))
        #expect(step(.clearing, .inICloud) == PlayRules.Step(change: .state(.cleared), queuesDeletion: true))
        #expect(step(.clearing, .cleared).change == .none)
    }

    /// Rule 7: when iCloud confirms a deletion, or reports the record already gone, the entry is removed for good.
    @Test func anAnsweredDeletionRemovesTheClearedEntry() {
        #expect(step(.deletionAnswered, .cleared).change == .remove)
        for state: PlaySyncState? in [.unsent, .sent, .inICloud, nil] {
            #expect(step(.deletionAnswered, state).change == .none)
        }
    }

    /// Joining step 2: every play in iCloud goes back to sent; a cleared entry stays cleared.
    @Test func joiningSetsPlaysInICloudBackToSent() {
        #expect(step(.joining, .inICloud).change == .state(.sent))
        for state: PlaySyncState? in [.unsent, .sent, .cleared, nil] {
            #expect(step(.joining, state).change == .none)
        }
    }
}
