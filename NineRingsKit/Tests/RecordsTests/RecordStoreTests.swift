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

    /// Two devices may each record the same play, as sync brings them together: the earlier stays.
    @Test func aPlayRecordedTwiceKeepsTheEarlier() throws {
        let id = UUID()
        let earlier = FinishedPlay(record(id: id, finishedAt: Date(timeIntervalSince1970: 1_000)), madeOn: .iPhone, appVersion: "1.4")
        let later = FinishedPlay(record(id: id, finishedAt: Date(timeIntervalSince1970: 2_000)), madeOn: .Mac, appVersion: "1.4")
        context.insert(later)
        context.insert(earlier)
        try context.save()
        let history = try store.history()
        #expect(history.count == 1)
        #expect(history.first?.madeOn == "iPhone")
        #expect(try context.fetchCount(FetchDescriptor<FinishedPlay>()) == 1)
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
        let entities = Dictionary(uniqueKeysWithValues: RecordStore.schema.entities.map { ($0.name, Set($0.attributes.map(\.name))) })
        #expect(entities["FinishedPlay"] == [
            "playID", "finishedAt", "startedAt", "startRings", "endRings", "moves", "undos", "movesPlayedForThePerson",
            "secondsSpent", "madeOn", "appVersion", "rules",
        ])
        #expect(entities["SavedToy"] == ["installation", "changedAt", "format", "snapshot", "appVersion"])
        for entity in RecordStore.schema.entities {
            #expect(entity.relationships.isEmpty, "\(entity.name)")
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name)")
            }
        }
    }

    @Test func theDevicesStoreIsNamedApart() {
        let configuration = RecordStore.deviceConfiguration(inMemory: true)
        #expect(configuration.name == "Device")
        #expect(configuration.cloudKitContainerIdentifier == nil)
    }
}
