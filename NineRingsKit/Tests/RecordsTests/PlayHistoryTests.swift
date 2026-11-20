import Foundation
import Puzzle
@testable import Records
import Session
import Testing

/// The finished plays as values, and the sample plays a debug launch can ask for.
@Suite struct PlayHistoryTests {
    @Test func theEmptyHistoryHasNoPlays() {
        #expect(PlayHistory.empty.plays.isEmpty && PlayHistory.empty.unreadable == 0)
        #expect(PlayHistory() == .empty)
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
}
