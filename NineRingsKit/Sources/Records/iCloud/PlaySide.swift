import Foundation

/// Where a finished play stands with iCloud (docs/icloud.md, sections 5 and 7).
public enum PlaySyncState: Int, Sendable, CaseIterable {
    /// It has never left this device.
    case unsent = 0
    /// It was handed to iCloud, or was once known there, and iCloud has not confirmed it since.
    case sent = 1
    /// iCloud has it.
    case inICloud = 2
    /// The person cleared it here, and iCloud has not yet confirmed the deletion.
    case cleared = 3

    /// Whether its record is to be saved: iCloud has not confirmed it.
    var isToBeSaved: Bool { self == .unsent || self == .sent }
}

/// What happens to one finished play's entry when something happens to its record: the rules of docs/icloud.md
/// section 7, as a plain function of the entry's state.
enum PlayRules {
    /// Something that happens to a play's record.
    enum Event: Equatable {
        /// The engine asks for the record to send it (rule 2).
        case handedOver
        /// iCloud accepted the record and returned it (rule 3).
        case accepted(CloudRecord)
        /// iCloud refused the record because one of that name exists (rule 4), with iCloud's record when the refusal
        /// carries it.
        case refused(serverRecord: CloudRecord?)
        /// The record arrived through a fetch (rule 5).
        case arrived(CloudRecord)
        /// A deletion of the record arrived through a fetch (rule 6).
        case deletionArrived
        /// iCloud confirmed this device's deletion of the record, or reported the record already gone (rule 7).
        case deletionAnswered
        /// The person cleared the history (rule 7).
        case clearing
        /// The device joins (section 8, joining step 2).
        case joining
    }

    /// What becomes of the entry.
    enum Change: Equatable {
        /// It stays as it is.
        case none
        /// Its state becomes this; its content stays.
        case state(PlaySyncState)
        /// It takes the record's content, with this state; an entry that is not here is added.
        case content(CloudRecord, PlaySyncState)
        /// It goes.
        case remove
    }

    /// What becomes of an entry, and what the engine is asked.
    struct Step: Equatable {
        var change: Change
        /// Queue the record's deletion.
        var queuesDeletion = false
        /// Withdraw a queued deletion of the record, which the store no longer marks.
        var withdrawsDeletion = false
        /// Ask the engine to fetch.
        var fetches = false
    }

    /// What `event` does to an entry in `state`, nil when the store holds no entry of that id.
    static func step(_ event: Event, from state: PlaySyncState?) -> Step {
        switch event {
        case .handedOver:
            // The entry becomes sent before the record is handed over; an entry iCloud has, a cleared one, or none at all
            // gives no record, and its save is withdrawn.
            guard let state, state.isToBeSaved else { return Step(change: .none) }
            return Step(change: .state(.sent))

        case .accepted(let record):
            switch state {
            case .unsent?, .sent?: return Step(change: .state(.inICloud))
            case .inICloud?, .cleared?: return Step(change: .none)
            case nil:
                // The entry was removed here when a deletion arrived while its save was out. The save may have brought
                // the record back into iCloud, where the other devices would show it and this one would not: the entry
                // comes back as cleared, and its deletion is queued. A record that is not there is answered as gone.
                return Step(change: .content(record, .cleared), queuesDeletion: true)
            }

        case .refused(let serverRecord):
            guard let serverRecord else {
                // A refusal without iCloud's record: the record exists there, and its content comes with a fetch.
                switch state {
                case .unsent?, .sent?: return Step(change: .state(.inICloud), fetches: true)
                case .inICloud?, .cleared?: return Step(change: .none)
                case nil: return Step(change: .none, fetches: true)
                }
            }
            switch state {
            case .cleared?: return Step(change: .none)
            // The record in iCloud stands: its content replaces the entry here, which becomes in iCloud. A record iCloud
            // has while this device holds no entry arrives as a fetched one would.
            case .unsent?, .sent?, .inICloud?, nil: return Step(change: .content(serverRecord, .inICloud))
            }

        case .arrived(let record):
            if state == .cleared { return Step(change: .none) }
            return Step(change: .content(record, .inICloud))

        case .deletionArrived:
            switch state {
            case .unsent?, nil: return Step(change: .none)
            case .sent?, .inICloud?: return Step(change: .remove)
            case .cleared?: return Step(change: .remove, withdrawsDeletion: true)
            }

        case .deletionAnswered:
            return Step(change: state == .cleared ? .remove : .none)

        case .clearing:
            switch state {
            case .unsent?: return Step(change: .remove)
            case .sent?, .inICloud?: return Step(change: .state(.cleared), queuesDeletion: true)
            case .cleared?, nil: return Step(change: .none)
            }

        case .joining:
            return Step(change: state == .inICloud ? .state(.sent) : .none)
        }
    }
}
