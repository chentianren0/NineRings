import Foundation
import Puzzle
@testable import Records
import Session
import Testing

/// One launch's toy and plays: in memory, written to a folder while one is open, held while it opens, and read when it
/// opens. Each test has a temporary folder of its own; a second `RecordFolder` on it stands for another device.
@Suite final class LaunchRecordsTests {
    private let url: URL
    private var records = LaunchRecords()

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "LaunchRecordsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// The folder as another device, or this one, sees it.
    private var folder: RecordFolder { RecordFolder(url: url) }

    private func play(finishedAt seconds: Double) -> PlayRecord {
        let finishedAt = Date(timeIntervalSinceReferenceDate: seconds)
        return PlayRecord(
            playID: UUID(), startedAt: finishedAt.addingTimeInterval(-600), finishedAt: finishedAt, startRings: .allOn,
            endRings: .allOff, moves: 341, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 512.5
        )
    }

    /// The same play, whenever a toy is made.
    private static let playID = UUID()

    /// A toy `moves` moves in from every ring on, with a play in progress and `seconds` spent on it: the same toy for
    /// the same numbers.
    private func toy(moves: Int, seconds: Double = 0) -> ToySnapshot {
        var session = PuzzleSession()
        for ring in PuzzleState.allOn.moves(to: .allOff).prefix(moves) {
            session.tap(ring)
            while session.isPlaying { session.advance(by: 0.1) }
        }
        var play = Play(id: Self.playID, startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), startRings: .allOn)
        play.moves = moves
        play.secondsSpent = seconds
        return ToySnapshot(toy: session, play: play)
    }

    // MARK: In memory

    @Test func withNoFolderEverythingIsKeptInMemory() throws {
        let first = play(finishedAt: 1000)
        let second = play(finishedAt: 2000)
        #expect(try !records.keep(toy(moves: 1)))
        #expect(try !records.record(first))
        #expect(try !records.record(second))
        #expect(try !records.record(first), "a play is recorded once")
        #expect(records.keptToy == toy(moves: 1))
        #expect(records.history.plays == [second, first])
        #expect(try !records.clearHistory())
        #expect(records.history == .empty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).isEmpty)
    }

    // MARK: A folder open

    @Test func whileAFolderIsOpenEachChangeIsWrittenThere() throws {
        let opening = records.open(folder)
        #expect(opening.toy == nil && !opening.wrote && opening.errors.isEmpty)
        #expect(try records.keep(toy(moves: 1)))
        #expect(try !records.keep(toy(moves: 1)), "the file holds this toy already")
        #expect(folder.keptToy() == toy(moves: 1))
        let finished = play(finishedAt: 1000)
        #expect(try records.record(finished))
        #expect(try !records.record(finished))
        #expect(try folder.history().plays == [finished])
        #expect(records.history.plays == [finished])
        #expect(try records.clearHistory())
        #expect(try folder.history() == .empty)
        #expect(records.history == .empty)
    }

    /// The toy the window starts with is kept in memory only: the folder's toy and history are what the launch shows.
    @Test func theFirstOpeningGivesTheFoldersToyAndHistory() throws {
        let saved = toy(moves: 5, seconds: 100)
        let finished = play(finishedAt: 1000)
        try folder.keep(saved)
        try folder.record(finished)
        #expect(try !records.keep(toy(moves: 0)))
        #expect(folder.keptToy() == saved, "nothing was written before the folder was open")

        let opening = records.open(folder)
        #expect(opening.toy == saved)
        #expect(!opening.wrote && opening.errors.isEmpty)
        #expect(records.keptToy == saved)
        #expect(records.history.plays == [finished])
        #expect(folder.keptToy() == saved)
    }

    /// With no toy in the folder, the toy in play stays, and the next keep writes it there.
    @Test func aFolderWithNoToyKeepsTheToyInPlayAtTheNextKeep() throws {
        try records.keep(toy(moves: 2))
        #expect(records.open(folder).toy == nil)
        #expect(folder.keptToy() == nil)
        #expect(try records.keep(toy(moves: 2)))
        #expect(folder.keptToy() == toy(moves: 2))
    }

    // MARK: Opening again

    @Test func nothingIsWrittenWhileTheFolderOpensAgain() throws {
        let finished = play(finishedAt: 1000)
        _ = records.open(folder)
        try records.keep(toy(moves: 1))
        try records.record(finished)
        records.closeFolder()
        let toyFile = try Data(contentsOf: folder.toyFile)
        let historyFile = try Data(contentsOf: folder.historyFile)

        #expect(try !records.keep(toy(moves: 2)))
        #expect(try !records.record(play(finishedAt: 2000)))
        #expect(try !records.clearHistory())
        #expect(try Data(contentsOf: folder.toyFile) == toyFile)
        #expect(try Data(contentsOf: folder.historyFile) == historyFile)
        #expect(records.keptToy == toy(moves: 2))
        #expect(records.history == .empty, "the play, then the clearing")
    }

    /// A clearing and the plays recorded while the folder opened are written once it is open, in their order.
    @Test func theClearingAndThePlaysThatWaitedAreWrittenAtTheNextOpening() throws {
        let before = play(finishedAt: 1000)
        let cleared = play(finishedAt: 2000)
        let after = play(finishedAt: 3000)
        _ = records.open(folder)
        try records.record(before)
        records.closeFolder()
        try records.record(cleared)
        try records.clearHistory()
        try records.record(after)

        let opening = records.open(folder)
        #expect(opening.wrote && opening.errors.isEmpty)
        #expect(try folder.history().plays == [after])
        #expect(records.history.plays == [after])
        records.closeFolder()
        #expect(!records.open(folder).wrote, "nothing waits any more")
    }

    /// The folder's history is the one shown, with the plays that waited recorded among it.
    @Test func theHistoryReadIsTheFoldersWithThePlaysThatWaited() throws {
        let mine = play(finishedAt: 1000)
        let waited = play(finishedAt: 3000)
        let theirs = play(finishedAt: 2000)
        _ = records.open(folder)
        try records.record(mine)
        records.closeFolder()
        try records.record(waited)
        try folder.clearHistory()
        try folder.record(theirs)

        #expect(records.open(folder).wrote)
        #expect(records.history.plays == [waited, theirs])
        #expect(try folder.history().plays == [waited, theirs])
    }

    /// The toy this launch left in the folder comes back as it was: the toy in play, moved on since, stays, and the
    /// next keep writes it.
    @Test func theToyInPlayStaysWhenTheFolderHoldsTheToyThisLaunchLeft() throws {
        _ = records.open(folder)
        try records.keep(toy(moves: 1))
        records.closeFolder()
        try records.keep(toy(moves: 3))

        let opening = records.open(folder)
        #expect(opening.toy == nil)
        #expect(records.keptToy == toy(moves: 3))
        #expect(folder.keptToy() == toy(moves: 1))
        #expect(try records.keep(toy(moves: 3)))
        #expect(folder.keptToy() == toy(moves: 3))
    }

    /// A toy another device kept since is for the player to take, whatever the toy in play.
    @Test func aToyAnotherDeviceKeptIsForThePlayerToTake() throws {
        _ = records.open(folder)
        try records.keep(toy(moves: 1))
        records.closeFolder()
        try records.keep(toy(moves: 2))
        try folder.keep(toy(moves: 4))

        let opening = records.open(folder)
        #expect(opening.toy == toy(moves: 4))
        #expect(records.keptToy == toy(moves: 4))
        records.closeFolder()
        #expect(records.open(folder).toy == nil, "read once, it is this launch's")
    }

    /// The same toy kept elsewhere with more time spent on it is not another toy.
    @Test func theSameToyWithAnotherTimeIsNotTakenAgain() throws {
        _ = records.open(folder)
        try records.keep(toy(moves: 1, seconds: 10))
        records.closeFolder()
        try folder.keep(toy(moves: 1, seconds: 70))
        #expect(records.open(folder).toy == nil)
    }

    // MARK: Files that cannot be read

    /// The history shown is the plays that did not reach the folder, until clearing replaces the file.
    @Test func aHistoryThatCannotBeReadShowsThePlaysThatWait() throws {
        try Data("not a history".utf8).write(to: folder.historyFile)
        let opening = records.open(folder)
        #expect(!opening.errors.isEmpty)
        #expect(records.history == .empty)

        let finished = play(finishedAt: 1000)
        #expect(throws: (any Error).self) { try self.records.record(finished) }
        #expect(records.history.plays == [finished])
        records.closeFolder()
        #expect(!records.open(folder).errors.isEmpty)
        #expect(records.history.plays == [finished], "it still waits")
        #expect(try Data(contentsOf: folder.historyFile) == Data("not a history".utf8))

        #expect(try records.clearHistory())
        #expect(try folder.history() == .empty)
        let next = play(finishedAt: 2000)
        #expect(try records.record(next))
        #expect(try folder.history().plays == [next])
    }
}
