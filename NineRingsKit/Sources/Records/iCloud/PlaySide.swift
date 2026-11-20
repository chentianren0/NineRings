import Foundation

/// Where a finished play stands with iCloud (docs/icloud.md, sections 5 and 7).
public enum PlaySyncState: Int, Sendable, CaseIterable {
    /// It has never left this device.
    case unsent = 0
    /// It was handed to iCloud, or was once known there, and iCloud has not confirmed it since.
    case sent = 1
    /// iCloud has it.
    case inICloud = 2
    /// The history was cleared, on this device or on another, and iCloud has not yet confirmed this device's deletion
    /// of the record.
    case cleared = 3

    /// Whether its record is to be saved: it is unsent or sent.
    var isToBeSaved: Bool { self == .unsent || self == .sent }
}

/// What happens to one finished play's entry when something happens to its record: the rules of docs/icloud.md
/// section 7, as a plain function of the entry's state. The caller has already set aside what belongs to another zone
/// than the one the device uses.
enum PlayRules {
    /// Something that happens to a play's record.
    enum Event: Equatable {
        /// The engine asks for the record to send it (rule 2).
        case handedOver
        /// iCloud accepted the record and returned it (rule 3).
        case accepted(CloudRecord)
        /// iCloud refused the record because one of that name exists (rule 4), with iCloud's record when the refusal
        /// carries it.
        case refusedAsExisting(serverRecord: CloudRecord?)
        /// iCloud refused the record because it does not know it (rule 4).
        case refusedAsUnknown
        /// The record arrived through a fetch (rule 5).
        case arrived(CloudRecord)
        /// A deletion of the record arrived through a fetch (rule 6).
        case deletionArrived
        /// iCloud confirmed this device's deletion of the record, or reported the record already gone (rule 7).
        case deletionAnswered
        /// The person cleared the history (rule 7).
        case clearing
        /// A start from nothing begins (section 8).
        case startFromNothing
    }

    /// What becomes of the entry.
    enum Change: Equatable {
        /// It stays as it is.
        case none
        /// Its state becomes this; its content and system fields stay.
        case state(PlaySyncState)
        /// It takes the record's system fields, with this state; its content stays.
        case systemFields(CloudRecord, PlaySyncState)
        /// It takes the record's content and system fields, with this state. An entry that is not here is added.
        case content(CloudRecord, PlaySyncState)
        /// An entry that is not here comes back as cleared, with the record's content when there is one, so that its
        /// deletion goes out.
        case comesBackCleared(CloudRecord?)
        /// It goes.
        case remove
    }

    /// What becomes of an entry, and what the engine is asked.
    struct Step: Equatable {
        var change: Change
        /// Withdraw a save still queued for the record.
        var withdrawsSave = false
        /// Withdraw a deletion still queued for the record, which the store no longer marks.
        var withdrawsDeletion = false
        /// Ask the engine to fetch.
        var fetches = false
    }

    /// What `event` does to an entry in `state`; nil when the store holds no entry of that id.
    static func step(_ event: Event, from state: PlaySyncState?) -> Step {
        switch event {
        case .handedOver:
            // The entry becomes sent before the record is handed over. An entry that is gone, cleared, or in iCloud is
            // not wanted: nothing is handed over, and the save is withdrawn.
            guard let state, state.isToBeSaved else { return Step(change: .none, withdrawsSave: true) }
            return Step(change: .state(.sent))

        case .accepted(let record):
            switch state {
            case .unsent?, .sent?, .inICloud?: return Step(change: .systemFields(record, .inICloud))
            // A cleared entry stays cleared, and its deletion stays marked.
            case .cleared?: return Step(change: .systemFields(record, .cleared))
            // In the zone the device uses, an entry can be gone for no other reason than a clearing, here or on another
            // device: it comes back as cleared, so that its deletion goes out and the clearing stands.
            case nil: return Step(change: .comesBackCleared(record))
            }

        case .refusedAsExisting(let serverRecord):
            guard let serverRecord else {
                // Without iCloud's record: the entry is in iCloud with what it has, and a fetch brings the record.
                switch state {
                case .unsent?, .sent?: return Step(change: .state(.inICloud), fetches: true)
                case .inICloud?, .cleared?: return Step(change: .none, fetches: true)
                case nil: return Step(change: .comesBackCleared(nil), fetches: true)
                }
            }
            switch state {
            // The record in iCloud stands: its content and system fields replace the entry here.
            case .unsent?, .sent?, .inICloud?: return Step(change: .content(serverRecord, .inICloud))
            case .cleared?: return Step(change: .systemFields(serverRecord, .cleared))
            case nil: return Step(change: .comesBackCleared(serverRecord))
            }

        case .refusedAsUnknown:
            // Its record was deleted in iCloud since this device knew it: the entry is removed, as when its deletion
            // arrives.
            return step(.deletionArrived, from: state)

        case .arrived(let record):
            if state == .cleared { return Step(change: .systemFields(record, .cleared)) }
            return Step(change: .content(record, .inICloud))

        case .deletionArrived:
            switch state {
            // iCloud never had an unsent play.
            case .unsent?, nil: return Step(change: .none)
            case .sent?, .inICloud?: return Step(change: .remove, withdrawsSave: true)
            case .cleared?: return Step(change: .remove, withdrawsDeletion: true)
            }

        case .deletionAnswered:
            return Step(change: state == .cleared ? .remove : .none)

        case .clearing:
            switch state {
            case .unsent?: return Step(change: .remove, withdrawsSave: true)
            case .sent?, .inICloud?: return Step(change: .state(.cleared), withdrawsSave: true)
            case .cleared?, nil: return Step(change: .none)
            }

        case .startFromNothing:
            return Step(change: state == .inICloud ? .state(.sent) : .none)
        }
    }
}
