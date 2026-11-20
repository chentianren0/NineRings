import Foundation
import Puzzle
@testable import Records
import Session
import Testing

/// The toy and the finished plays as two files, each test in a temporary folder of its own.
@Suite final class RecordFolderTests {
    private let folder: RecordFolder

    init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "RecordFolderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = RecordFolder(url: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder.url)
    }

    private func record(id: UUID = UUID(), finishedAt: Date, moves: Int = 341) -> PlayRecord {
        PlayRecord(
            playID: id, startedAt: finishedAt.addingTimeInterval(-600), finishedAt: finishedAt, startRings: .allOn,
            endRings: .allOff, moves: moves, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 512.5
        )
    }

    /// A toy part way through a move, with a play in progress and time spent on it.
    private var toyInPlay: ToySnapshot {
        var state = PlayState()
        state.tap(1)
        state.advance(by: 10)
        state.tap(3)
        state.advance(by: 0.05)
        state.spend(3.25)
        return state.snapshot
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: The toy

    @Test func noFileKeepsNoToy() {
        #expect(folder.keptToy() == nil)
    }

    @Test func theToyKeptComesBack() throws {
        let snapshot = toyInPlay
        #expect(snapshot.play != nil)
        #expect(try folder.keep(snapshot))
        #expect(folder.keptToy() == snapshot)
        #expect(RecordFolder(url: folder.url).keptToy() == snapshot, "read again from the file")
    }

    @Test func theSameToyIsNotWrittenAgain() throws {
        let snapshot = toyInPlay
        #expect(try folder.keep(snapshot))
        let written = try Data(contentsOf: folder.toyFile)
        #expect(try !folder.keep(snapshot))
        #expect(try Data(contentsOf: folder.toyFile) == written)

        let other = ToySnapshot(toy: PuzzleSession(), play: nil)
        #expect(try folder.keep(other))
        #expect(folder.keptToy() == other)
    }

    /// The file holds the format and the snapshot, written as ``ToySnapshot/encoded()`` writes it, and nothing else.
    @Test func theToyFileHoldsItsFormatAndTheSnapshot() throws {
        let snapshot = toyInPlay
        try folder.keep(snapshot)
        let expected = Data(#"{"format":1,"toy":"#.utf8) + (try snapshot.encoded()) + Data("}".utf8)
        #expect(try Data(contentsOf: folder.toyFile) == expected)
    }

    @Test func aToyInAnotherFormatIsSkippedAndReplaced() throws {
        let snapshot = ToySnapshot(toy: PuzzleSession(), play: nil)
        let newer = Data(#"{"format":2,"toy":"#.utf8) + (try snapshot.encoded()) + Data("}".utf8)
        try newer.write(to: folder.toyFile)
        #expect(folder.keptToy() == nil)
        #expect(try folder.keep(snapshot))
        #expect(folder.keptToy() == snapshot)
    }

    @Test func aToyFileThatCannotBeReadKeepsNoToy() throws {
        try Data("not a toy".utf8).write(to: folder.toyFile)
        #expect(folder.keptToy() == nil)
        try Data(#"{"format":1,"toy":{"moves":[]}}"#.utf8).write(to: folder.toyFile)
        #expect(folder.keptToy() == nil)
    }

    // MARK: The history

    @Test func noFileIsAnEmptyHistory() throws {
        #expect(try folder.history() == .empty)
    }

    @Test func aFinishedPlayIsRecordedOnceWithItsNumbers() throws {
        let finishedAt = Date(timeIntervalSinceReferenceDate: 785_000_000.123456)
        let play = record(finishedAt: finishedAt)
        #expect(try folder.record(play))
        let written = try Data(contentsOf: folder.historyFile)
        #expect(try !folder.record(play))
        #expect(try Data(contentsOf: folder.historyFile) == written)
        #expect(try folder.history() == PlayHistory(plays: [play]))
        #expect(try RecordFolder(url: folder.url).history().plays.first?.finishedAt == finishedAt, "dates come back exactly")
    }

    /// Each play holds its numbers, its rules, and its rings as nine characters, and nothing else.
    @Test func theHistoryFileHoldsThePlaysAndTheirRules() throws {
        let play = record(finishedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        try folder.record(play)
        let file = try json(folder.historyFile)
        #expect(Array(file.keys) == ["plays"])
        let plays = try #require(file["plays"] as? [[String: Any]])
        let written = try #require(plays.first)
        #expect(plays.count == 1)
        #expect(Set(written.keys) == [
            "rules", "playID", "startedAt", "finishedAt", "startRings", "endRings", "moves", "undos",
            "movesPlayedForThePerson", "secondsSpent",
        ])
        #expect(written["rules"] as? Int == 1)
        #expect(written["startRings"] as? String == "111111111" && written["endRings"] as? String == "000000000")
        #expect(written["playID"] as? String == play.playID.uuidString)
        #expect(written["finishedAt"] as? Double == 1_000)
    }

    /// The plays are newest first whatever order they were recorded in, and the same plays give the same bytes.
    @Test func theHistoryIsNewestFirstAndTheSamePlaysGiveTheSameBytes() throws {
        let old = record(finishedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let new = record(finishedAt: Date(timeIntervalSinceReferenceDate: 9_000), moves: 400)
        try folder.record(old)
        try folder.record(new)
        #expect(try folder.history().plays == [new, old])

        let otherURL = folder.url.appending(path: "Other")
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)
        let other = RecordFolder(url: otherURL)
        try other.record(new)
        try other.record(old)
        #expect(try Data(contentsOf: other.historyFile) == Data(contentsOf: folder.historyFile))
    }

    /// A file written otherwise is still read as one play for each id, newest first.
    @Test func readingKeepsOnePlayForEachIdNewestFirst() throws {
        let id = UUID()
        let first = record(id: id, finishedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let copy = record(id: id, finishedAt: Date(timeIntervalSinceReferenceDate: 5_000), moves: 500)
        let newest = record(finishedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        let plays = try JSONEncoder().encode([first, copy, newest])
        try (Data(#"{"plays":"#.utf8) + plays + Data("}".utf8)).write(to: folder.historyFile)
        #expect(try folder.history() == PlayHistory(plays: [newest, first]))
    }

    /// A play written with rules this build does not know is counted, and stays in the file as it was when a play is
    /// recorded.
    @Test func aPlayThisBuildCannotReadIsCountedAndKept() throws {
        let known = record(finishedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let knownJSON = try String(decoding: JSONEncoder().encode(known), as: UTF8.self)
        let newer = #"{"rules":2,"playID":"5E1A0B4C-0000-4000-8000-000000000001","laps":[1.5,2],"note":null,"won":true}"#
        try Data(#"{"plays":[\#(newer),\#(knownJSON)]}"#.utf8).write(to: folder.historyFile)
        #expect(try folder.history() == PlayHistory(plays: [known], unreadable: 1))

        let new = record(finishedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        #expect(try folder.record(new))
        #expect(try folder.history() == PlayHistory(plays: [new, known], unreadable: 1))
        let plays = try #require(try json(folder.historyFile)["plays"] as? [NSDictionary])
        let kept = try #require(try JSONSerialization.jsonObject(with: Data(newer.utf8)) as? NSDictionary)
        #expect(plays.count == 3)
        #expect(plays.contains(kept))
    }

    @Test func clearingDeletesEveryPlayTheUnreadableToo() throws {
        let newer = #"{"rules":2,"playID":"5E1A0B4C-0000-4000-8000-000000000001"}"#
        try Data(#"{"plays":[\#(newer)]}"#.utf8).write(to: folder.historyFile)
        try folder.record(record(finishedAt: .now))
        #expect(try folder.history().plays.count == 1 && folder.history().unreadable == 1)
        try folder.clearHistory()
        #expect(try folder.history() == .empty)
        #expect(try Data(contentsOf: folder.historyFile) == Data(#"{"plays":[]}"#.utf8))
    }

    /// A file that is not a history is left as it is: nothing is recorded over it, and only clearing replaces it.
    @Test func aHistoryFileThatCannotBeReadIsLeftAsItIs() throws {
        let broken = Data(#"{"plays":[{"rules":1"#.utf8)
        try broken.write(to: folder.historyFile)
        #expect(throws: (any Error).self) { try self.folder.history() }
        #expect(throws: (any Error).self) { try self.folder.record(self.record(finishedAt: .now)) }
        #expect(try Data(contentsOf: folder.historyFile) == broken)
        try folder.clearHistory()
        #expect(try folder.history() == .empty)
    }

    /// The files are written whole, each in place of the one before: nothing else is left in the folder.
    @Test func theFolderHoldsTheTwoFilesOnly() throws {
        for index in 0..<3 {
            try folder.keep(ToySnapshot(toy: PuzzleSession(), play: nil))
            try folder.record(record(finishedAt: Date(timeIntervalSinceReferenceDate: Double(index))))
            try folder.keep(toyInPlay)
        }
        try folder.clearHistory()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false))
        #expect(names.sorted() == ["History.json", "Toy.json"])
    }
}
