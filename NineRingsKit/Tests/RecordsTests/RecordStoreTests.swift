import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// The kept toy and the records of finished plays, in stores kept in memory.
@MainActor
@Suite struct RecordStoreTests {
    private let store: RecordStore

    init() throws {
        store = RecordStore(container: try RecordStore.deviceContainer(inMemory: true))
    }

    private var context: ModelContext { store.container.mainContext }

    private func record(id: UUID = UUID(), finishedAt: Date, moves: Int = 341) -> PlayRecord {
        PlayRecord(
            playID: id, startedAt: finishedAt.addingTimeInterval(-600), finishedAt: finishedAt, startRings: .allOn,
            endRings: .allOff, moves: moves, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 512.5
        )
    }

    // MARK: The kept toy

    @Test func theToyKeptComesBack() throws {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 10)
        state.spend(3)
        #expect(try store.keep(state.snapshot, installation: "A", appVersion: "1.4"))
        let kept = try #require(try store.keptToy(installation: "A"))
        #expect(kept == state.snapshot)
        #expect(try store.keptToy(installation: "B") == nil)
    }

    @Test func eachInstallationKeepsOneToyChangedInPlace() throws {
        let first = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        var session = PuzzleSession()
        try store.keep(ToySnapshot(toy: session, play: nil), installation: "A", appVersion: "1.4", at: first)
        session.tap(2)
        session.advance(by: 10)
        try store.keep(ToySnapshot(toy: session, play: nil), installation: "A", appVersion: "1.5", at: later)
        try store.keep(ToySnapshot(toy: PuzzleSession(), play: nil), installation: "B", appVersion: "1.5", at: later)
        let saved = try context.fetch(FetchDescriptor<SavedToy>(sortBy: [SortDescriptor(\.installation)]))
        #expect(saved.map(\.installation) == ["A", "B"])
        #expect(saved[0].changedAt == later && saved[0].appVersion == "1.5" && saved[0].format == 1)
        #expect(try store.keptToy(installation: "A")?.toy?.state == PuzzleState.allOn.moving(2))
    }

    @Test func theSameToyIsNotWrittenAgain() throws {
        let snapshot = ToySnapshot(toy: PuzzleSession(), play: nil)
        let first = Date(timeIntervalSince1970: 1_000)
        #expect(try store.keep(snapshot, installation: "A", appVersion: "1.4", at: first))
        #expect(try !store.keep(snapshot, installation: "A", appVersion: "1.4", at: .now))
        #expect(try context.fetch(FetchDescriptor<SavedToy>()).first?.changedAt == first, "the toy has not changed since")
    }

    /// Only the toy changing moves `changedAt`: time spent looking at it is kept, but does not make it newer.
    @Test func timeSpentIsKeptWithoutChangingTheToy() throws {
        let first = Date(timeIntervalSince1970: 1_000)
        var state = PlayState()
        state.tap(1)
        state.advance(by: 10)
        try store.keep(state.snapshot, installation: "A", appVersion: "1.4", at: first)
        state.spend(5)
        #expect(try store.keep(state.snapshot, installation: "A", appVersion: "1.4", at: first.addingTimeInterval(60)))
        #expect(try store.keptToy(installation: "A")?.play?.secondsSpent == 5)
        #expect(try context.fetch(FetchDescriptor<SavedToy>()).first?.changedAt == first)

        let moved = first.addingTimeInterval(120)
        state.tap(3)
        state.advance(by: 10)
        try store.keep(state.snapshot, installation: "A", appVersion: "1.4", at: moved)
        #expect(try context.fetch(FetchDescriptor<SavedToy>()).first?.changedAt == moved)
    }

    @Test func aToyInAnotherFormatIsSkipped() throws {
        let saved = SavedToy(installation: "A")
        saved.format = 2
        saved.snapshot = try ToySnapshot(toy: PuzzleSession(), play: nil).encoded()
        context.insert(saved)
        #expect(try store.keptToy(installation: "A") == nil)
    }

    // MARK: Finished plays

    @Test func aFinishedPlayIsRecordedOnceWithItsNumbers() throws {
        let play = record(finishedAt: Date(timeIntervalSince1970: 5_000))
        try store.record(play, madeOn: .iPad, appVersion: "1.4")
        try store.record(play, madeOn: .iPad, appVersion: "1.4")
        let history = try store.history()
        #expect(history.count == 1)
        let recorded = try #require(history.first)
        #expect(recorded.playID == play.playID)
        #expect(recorded.startRings == "111111111" && recorded.endRings == "000000000")
        #expect(recorded.moves == 341 && recorded.undos == 0 && recorded.movesPlayedForThePerson == 0)
        #expect(recorded.secondsSpent == 512.5)
        #expect(recorded.madeOn == "iPad" && recorded.appVersion == "1.4" && recorded.rules == 1)
        #expect(recorded.record == play)
        #expect(recorded.isShortestWay)
    }

    @Test func theHistoryIsNewestFirst() throws {
        let old = record(finishedAt: Date(timeIntervalSince1970: 1_000))
        let new = record(finishedAt: Date(timeIntervalSince1970: 9_000), moves: 400)
        try store.record(old, madeOn: .Mac, appVersion: "1.4")
        try store.record(new, madeOn: .iPhone, appVersion: "1.4")
        #expect(try store.history().map(\.playID) == [new.playID, old.playID])
        #expect(try store.history().map(\.isShortestWay) == [false, true])
    }

    /// Two devices may each record the same play, as sync brings them together: it shows once, the earlier, and
    /// nothing is deleted.
    @Test func aPlayRecordedTwiceShowsOnceAsTheEarlier() throws {
        let id = UUID()
        let earlier = FinishedPlay(record(id: id, finishedAt: Date(timeIntervalSince1970: 1_000)), madeOn: .iPhone, appVersion: "1.4")
        let later = FinishedPlay(record(id: id, finishedAt: Date(timeIntervalSince1970: 2_000)), madeOn: .Mac, appVersion: "1.4")
        context.insert(later)
        context.insert(earlier)
        try context.save()
        let history = try store.history()
        #expect(history.count == 1)
        #expect(history.first?.madeOn == "iPhone")
        #expect(try context.fetchCount(FetchDescriptor<FinishedPlay>()) == 2)
    }

    /// Two copies alike in every field: one shows, and both stay, so that no device's clean-up can delete both.
    @Test func twoCopiesAlikeShowOnceAndBothStay() throws {
        let play = record(finishedAt: Date(timeIntervalSince1970: 1_000))
        context.insert(FinishedPlay(play, madeOn: .iPhone, appVersion: "1.4"))
        context.insert(FinishedPlay(play, madeOn: .iPhone, appVersion: "1.4"))
        try context.save()
        #expect(try store.history().map(\.playID) == [play.playID])
        #expect(try context.fetchCount(FetchDescriptor<FinishedPlay>()) == 2)
        #expect(!context.hasChanges)
    }

    @Test func aRecordWithRulesThisBuildDoesNotKnowIsNotRead() throws {
        let play = FinishedPlay(record(finishedAt: .now), madeOn: .Mac, appVersion: "9.0")
        play.rules = PlayRecord.rules + 1
        #expect(play.record == nil)
        #expect(!play.isShortestWay)
    }

    // MARK: The schema

    /// The record types and fields, as CloudKit will have them: a change here is a change to a schema that can only
    /// grow.
    @Test func theModelsAreAsTheSchemaFixesThem() {
        let fixed: [String: [String: Any.Type]] = [
            "FinishedPlay": [
                "playID": UUID.self, "finishedAt": Date.self, "startedAt": Date.self, "startRings": String.self,
                "endRings": String.self, "moves": Int.self, "undos": Int.self, "movesPlayedForThePerson": Int.self,
                "secondsSpent": Double.self, "madeOn": String.self, "appVersion": String.self, "rules": Int.self,
            ],
            "SavedToy": [
                "installation": String.self, "changedAt": Date.self, "format": Int.self, "snapshot": Data.self,
                "appVersion": String.self,
            ],
        ]
        #expect(Set(RecordStore.schema.entities.map(\.name)) == Set(fixed.keys))
        for entity in RecordStore.schema.entities {
            let fields = fixed[entity.name] ?? [:]
            #expect(Set(entity.attributes.map(\.name)) == Set(fields.keys), "\(entity.name)")
            for attribute in entity.attributes {
                let isFixedType = attribute.valueType == fields[attribute.name]
                #expect(isFixedType, "\(entity.name).\(attribute.name) is \(attribute.valueType)")
            }
        }
        // CloudKit's rules: no relationships, no unique values, and a default for every field.
        for entity in RecordStore.schema.entities {
            #expect(entity.relationships.isEmpty, "\(entity.name)")
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name)")
                #expect(attribute.defaultValue != nil, "\(entity.name).\(attribute.name) has no default")
            }
        }
    }

    /// The device's store is named apart, and set never to sync. `CloudKitDatabase` is not Equatable, so it is told by
    /// how SwiftData describes it, which tells `.none` from `.automatic`.
    @Test(arguments: [true, false]) func theDevicesStoreNeverSyncs(inMemory: Bool) {
        let configuration = RecordStore.deviceConfiguration(inMemory: inMemory)
        #expect(configuration.name == "Device")
        let described = String(reflecting: configuration.cloudKitDatabase)
        #expect(described == String(reflecting: ModelConfiguration.CloudKitDatabase.none))
        #expect(described != String(reflecting: ModelConfiguration.CloudKitDatabase.automatic))
    }
}
