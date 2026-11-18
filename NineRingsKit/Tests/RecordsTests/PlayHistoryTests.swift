import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// What the app's keeper gives every screen: the plays as values, the number this build cannot read, and clearing; with
/// the sample plays a debug launch can ask for, and where each build keeps its stores.
@MainActor
@Suite struct PlayHistoryTests {
    private let store: RecordStore

    init() throws {
        store = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
    }

    private var context: ModelContext { store.container.mainContext }

    private func play(id: UUID = UUID(), finishedAt seconds: TimeInterval, moves: Int = 341, undos: Int = 0) -> PlayRecord {
        let finishedAt = Date(timeIntervalSince1970: seconds)
        return PlayRecord(
            playID: id, startedAt: finishedAt.addingTimeInterval(-600), finishedAt: finishedAt, startRings: .allOn,
            endRings: .allOff, moves: moves, undos: undos, movesPlayedForThePerson: 0, secondsSpent: 512.5
        )
    }

    /// A record as a newer version of the app could leave it: rules this build does not know.
    private func unreadable(finishedAt seconds: TimeInterval, id: UUID = UUID()) -> FinishedPlay {
        let record = FinishedPlay(play(id: id, finishedAt: seconds), madeOn: .Mac, appVersion: "9.0")
        record.rules = PlayRecord.rules + 1
        return record
    }

    // MARK: The plays as values

    @Test func anEmptyStoreHasAnEmptyHistory() throws {
        #expect(try store.playHistory() == .empty)
        #expect(PlayHistory.empty.plays.isEmpty && PlayHistory.empty.unreadable == 0)
    }

    @Test func thePlaysAreValuesNewestFirst() throws {
        let old = play(finishedAt: 1_000)
        let middle = play(finishedAt: 5_000, undos: 2)
        let new = play(finishedAt: 9_000, moves: 400)
        for record in [middle, new, old] {
            try store.record(record, madeOn: .iPhone, appVersion: "1.4")
        }
        let history = try store.playHistory()
        #expect(history.plays == [new, middle, old])
        #expect(history.unreadable == 0)
        #expect(history.plays.map(\.isShortestWay) == [false, false, true])
    }

    /// Two copies of one play, as sync can bring together, are one play, as ``RecordStore/history()`` shows it.
    @Test func aPlayRecordedTwiceIsOnePlay() throws {
        let id = UUID()
        context.insert(FinishedPlay(play(id: id, finishedAt: 2_000), madeOn: .Mac, appVersion: "1.4"))
        context.insert(FinishedPlay(play(id: id, finishedAt: 1_000), madeOn: .iPhone, appVersion: "1.4"))
        try context.save()
        let history = try store.playHistory()
        #expect(history.plays.map(\.playID) == [id])
        #expect(history.plays.first?.finishedAt == Date(timeIntervalSince1970: 1_000), "the earlier copy shows")
    }

    // MARK: The plays this build cannot read

    @Test func playsThisBuildCannotReadAreCountedNotShown() throws {
        let readable = play(finishedAt: 3_000)
        try store.record(readable, madeOn: .iPad, appVersion: "1.4")
        context.insert(unreadable(finishedAt: 4_000))
        let badRings = FinishedPlay(play(finishedAt: 2_000), madeOn: .iPad, appVersion: "1.4")
        badRings.startRings = "12"
        context.insert(badRings)
        try context.save()
        let history = try store.playHistory()
        #expect(history.plays == [readable])
        #expect(history.unreadable == 2)
    }

    /// One play this build cannot read, kept twice, counts once: the count is of plays, as the plays are.
    @Test func anUnreadablePlayKeptTwiceCountsOnce() throws {
        let id = UUID()
        context.insert(unreadable(finishedAt: 1_000, id: id))
        context.insert(unreadable(finishedAt: 1_000, id: id))
        try context.save()
        #expect(try store.playHistory() == PlayHistory(plays: [], unreadable: 1))
    }

    // MARK: Clearing

    @Test func clearingDeletesEveryPlayAndKeepsTheToy() throws {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 10)
        try store.keep(state.snapshot, installation: "A", appVersion: "1.4")
        try store.keep(ToySnapshot(toy: PuzzleSession(), play: nil), installation: "B", appVersion: "1.4")
        try store.record(play(finishedAt: 1_000), madeOn: .Mac, appVersion: "1.4")
        try store.record(play(finishedAt: 2_000), madeOn: .Mac, appVersion: "1.4")
        let id = UUID()
        context.insert(FinishedPlay(play(id: id, finishedAt: 3_000), madeOn: .iPhone, appVersion: "1.4"))
        context.insert(FinishedPlay(play(id: id, finishedAt: 3_000), madeOn: .iPhone, appVersion: "1.4"))
        context.insert(unreadable(finishedAt: 4_000))
        try context.save()

        #expect(try store.clearHistory() == 5, "every record: both copies of a play, and the one this build cannot read")
        #expect(try store.playHistory() == .empty)
        #expect(try context.fetchCount(FetchDescriptor<FinishedPlay>()) == 0)
        #expect(!context.hasChanges, "the deletes are saved")
        #expect(try store.keptToy(installation: "A") == state.snapshot)
        #expect(try store.keptToy(installation: "B") != nil)
    }

    @Test func clearingAnEmptyHistoryDeletesNothing() throws {
        try store.keep(ToySnapshot(toy: PuzzleSession(), play: nil), installation: "A", appVersion: "1.4")
        #expect(try store.clearHistory() == 0)
        #expect(try store.keptToy(installation: "A") != nil)
    }

    @Test func playsRecordedAfterClearingShow() throws {
        try store.record(play(finishedAt: 1_000), madeOn: .Mac, appVersion: "1.4")
        try store.clearHistory()
        let later = play(finishedAt: 2_000)
        try store.record(later, madeOn: .Mac, appVersion: "1.4")
        #expect(try store.playHistory().plays == [later])
    }

    // MARK: Sample plays

    @Test func noSamplesForZeroOrLess() {
        #expect(PlayRecord.samples(0, latest: .now).isEmpty)
        #expect(PlayRecord.samples(-2, latest: .now).isEmpty)
    }

    @Test(arguments: [1, 2, 3, 4, 9, 40]) func samplePlaysDifferAndAreNewestFirst(count: Int) {
        let latest = Date(timeIntervalSince1970: 1_000_000_000)
        let samples = PlayRecord.samples(count, latest: latest)
        #expect(samples.count == count)
        #expect(samples.first?.finishedAt == latest)
        #expect(Set(samples.map(\.playID)).count == count)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0.finishedAt > $1.finishedAt }, "newest first")
        struct Numbers: Hashable { var moves, undos, played: Int; var seconds: Double }
        let numbers = Set(samples.map { Numbers(moves: $0.moves, undos: $0.undos, played: $0.movesPlayedForThePerson, seconds: $0.secondsSpent) })
        #expect(numbers.count == count, "no two samples have the same numbers")
        for sample in samples {
            #expect(sample.startRings == .allOn && sample.endRings == .allOff)
            #expect(sample.moves >= 341, "never fewer moves than the distance")
            #expect(sample.startedAt.addingTimeInterval(sample.secondsSpent) <= sample.finishedAt)
        }
    }

    @Test func amongThreeSamplesAreTheShortestWayUndosAndMovesPlayedForThePerson() {
        let samples = PlayRecord.samples(3, latest: .now)
        #expect(samples.contains { $0.isShortestWay })
        #expect(samples.contains { $0.undos > 0 && $0.movesPlayedForThePerson == 0 })
        #expect(samples.contains { $0.movesPlayedForThePerson > 0 && $0.undos == 0 })
    }

    @Test func samplePlaysRecordedAreTheHistory() throws {
        let samples = PlayRecord.samples(5, latest: Date(timeIntervalSince1970: 1_000_000_000))
        for sample in samples.reversed() {
            try store.record(sample, madeOn: .Mac, appVersion: "1.4")
        }
        #expect(try store.playHistory() == PlayHistory(plays: samples, unreadable: 0))
    }

    // MARK: Where the stores are

    /// A debug build signed for a device shares the App Store version's container: its folder is apart, so its store is
    /// never the release build's file.
    @Test func aDebugBuildsStoreIsNeverTheReleaseBuildsFile() {
        let release = RecordStore.folder.standardizedFileURL
        let debug = RecordStore.debugFolder.standardizedFileURL
        #expect(release != debug)
        #expect(!debug.path.hasPrefix(release.path + "/") && !release.path.hasPrefix(debug.path + "/"))
        let releaseFile = RecordStore.deviceConfiguration(in: .folder(RecordStore.folder)).url.standardizedFileURL
        let debugFile = RecordStore.deviceConfiguration(in: .folder(RecordStore.debugFolder)).url.standardizedFileURL
        #expect(releaseFile.deletingLastPathComponent() == release)
        #expect(debugFile.deletingLastPathComponent() == debug)
    }

    @Test func aStoreInMemoryReachesNoFile() {
        let configuration = RecordStore.deviceConfiguration(in: .memory)
        #expect(configuration.isStoredInMemoryOnly)
    }

    /// A store in a folder is a file there, made with its folder, and what it keeps comes back when it is opened again.
    @Test func aStoreInAFolderIsAFileThere() throws {
        let folder = URL.temporaryDirectory.appending(path: "PlayHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorded = play(finishedAt: 1_000)
        do {
            let store = RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder)))
            try store.record(recorded, madeOn: .Mac, appVersion: "1.4")
        }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Device.store").path))
        let reopened = RecordStore(container: try RecordStore.deviceContainer(in: .folder(folder)))
        #expect(try reopened.playHistory().plays == [recorded])
    }
}
