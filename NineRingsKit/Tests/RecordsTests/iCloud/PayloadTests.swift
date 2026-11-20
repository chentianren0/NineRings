import Foundation
import Puzzle
@testable import Records
import Session
import Testing

/// The payloads of the two record types and their format (docs/icloud.md, sections 5 and 14): written in format 1, read
/// leniently, and never interpreted in a format this version does not know.
@Suite struct PayloadTests {
    /// A toy three moves into a play, with time spent.
    private func toy() -> ToySnapshot {
        var state = PlayState()
        for ring in [1, 3, 1] {
            state.tap(ring)
            while state.toy.isPlaying { state.advance(by: 10) }
        }
        state.spend(42)
        return state.snapshot
    }

    private let play = PlayRecord(
        playID: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
        finishedAt: Date(timeIntervalSinceReferenceDate: 800_000_600.5), startRings: .allOn, endRings: .allOff, moves: 345,
        undos: 2, movesPlayedForThePerson: 6, secondsSpent: 512.25
    )

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The toy

    @Test func theToysPayloadComesBackAsItWasWritten() throws {
        let stamps = [UUID(), UUID(), UUID()]
        let payload = ToyPayload(toy: toy(), changedAt: Date(timeIntervalSinceReferenceDate: 800_000_123.25), changedOn: "iPad", appVersion: "2.0", stamps: stamps)
        let read = try #require(ToyPayload(format: ToyPayload.format, payload: try payload.encoded()))
        #expect(read == payload)
        #expect(read.stamp == stamps.last)
        #expect(Array(read.earlierStamps) == Array(stamps.dropLast()))
    }

    @Test func theToysPayloadHoldsWhatSectionFiveLists() throws {
        let payload = ToyPayload(toy: toy(), changedAt: .now, changedOn: "Mac", appVersion: "2.0", stamps: [UUID()])
        let keys = Set(try json(try payload.encoded()).keys)
        #expect(keys == ["toy", "changedAt", "changedOn", "appVersion", "stamps"])
    }

    /// The same payload is the same bytes, so that nothing differs that did not change.
    @Test func thePayloadIsTheSameBytesEachTime() throws {
        let payload = ToyPayload(toy: toy(), changedAt: .now, changedOn: "Mac", appVersion: "2.0", stamps: [UUID(), UUID()])
        #expect(try payload.encoded() == payload.encoded())
    }

    /// A value this version does not know is ignored, and a value it knows but does not find takes a default: adding a
    /// value needs no new format.
    @Test func theToysPayloadIsReadLeniently() throws {
        let payload = ToyPayload(toy: toy(), changedAt: .now, changedOn: "Vision", appVersion: "9.1", stamps: [UUID()])
        var object = try json(try payload.encoded())
        object["aValueOfALaterVersion"] = ["anything": 1]
        object.removeValue(forKey: "changedOn")
        object.removeValue(forKey: "appVersion")
        let read = try #require(ToyPayload(format: 1, payload: try JSONSerialization.data(withJSONObject: object)))
        #expect(read.toy == payload.toy)
        #expect(read.changedOn == "" && read.appVersion == "")
        #expect(read.stamps == payload.stamps)
    }

    /// A kind of device this build does not know is kept as it is.
    @Test func aKindOfDeviceThisBuildDoesNotKnowIsKept() throws {
        let payload = ToyPayload(toy: toy(), changedAt: .now, changedOn: "Vision", appVersion: "9.1", stamps: [UUID()])
        #expect(ToyPayload(format: 1, payload: try payload.encoded())?.changedOn == "Vision")
    }

    @Test(arguments: [2, 0, -1, 99])
    func aToyInAnotherFormatIsNeverRead(format: Int) throws {
        let payload = ToyPayload(toy: toy(), changedAt: .now, changedOn: "Mac", appVersion: "2.0", stamps: [UUID()])
        #expect(ToyPayload(format: format, payload: try payload.encoded()) == nil)
    }

    @Test func aToyThatIsNotJSONOrHasNoToyIsNotRead() throws {
        #expect(ToyPayload(format: 1, payload: Data("not JSON".utf8)) == nil)
        #expect(ToyPayload(format: 1, payload: Data(#"{"stamps":[]}"#.utf8)) == nil)
    }

    /// A toy record reads as readable, in a format higher than this version knows, or broken: in a format it knows, or in
    /// none, and still unreadable (docs/icloud.md, sections 6 and 14).
    @Test func theThreeReadingsOfAToy() throws {
        let payload = try ToyPayload(toy: toy(), changedAt: .now, changedOn: "Mac", appVersion: "2.0", stamps: [UUID()]).encoded()
        #expect(ToyPayload.reading(format: 1, payload: payload) == .readable(ToyPayload(format: 1, payload: payload)!))
        #expect(ToyPayload.reading(format: 2, payload: payload) == .higherFormat)
        #expect(ToyPayload.reading(format: 1, payload: Data("{".utf8)) == .broken)
        #expect(ToyPayload.reading(format: 0, payload: payload) == .broken)
        #expect(ToyPayload.reading(format: nil, payload: payload) == .broken)
        #expect(ToyPayload.reading(format: 1, payload: nil) == .broken)
    }

    /// A toy whose moves break the puzzle's rule brings nothing back, so it is not read.
    @Test func aToyWhoseMovesBreakTheRuleIsNotRead() throws {
        let payload = ToyPayload(toy: toy(), changedAt: .now, changedOn: "Mac", appVersion: "2.0", stamps: [UUID()])
        var object = try json(try payload.encoded())
        var snapshot = try #require(object["toy"] as? [String: Any])
        snapshot["moves"] = [5]
        object["toy"] = snapshot
        #expect(ToyPayload(format: 1, payload: try JSONSerialization.data(withJSONObject: object)) == nil)
    }

    // MARK: A finished play

    @Test func aFinishedPlaysPayloadComesBackAsItWasWritten() throws {
        let payload = FinishedPlayPayload(play: play, madeOn: "iPad", appVersion: "2.0")
        let read = try #require(FinishedPlayPayload(format: 1, payload: try payload.encoded(), recordName: play.playID.uuidString))
        #expect(read == payload)
        #expect(payload.recordName == play.playID.uuidString)
    }

    /// The values of section 2, and the start and end arrangements and the app's version, which the store keeps for every
    /// play and the Shortest Way mark needs.
    @Test func aFinishedPlaysPayloadHoldsItsValues() throws {
        let keys = Set(try json(try FinishedPlayPayload(play: play, madeOn: "Mac", appVersion: "2.0").encoded()).keys)
        #expect(keys == [
            "id", "startedAt", "finishedAt", "moves", "undos", "movesPlayedForThePerson", "secondsSpent", "madeOn", "startRings",
            "endRings", "appVersion",
        ])
    }

    @Test func aFinishedPlaysPayloadIsReadLeniently() throws {
        var object = try json(try FinishedPlayPayload(play: play, madeOn: "Mac", appVersion: "2.0").encoded())
        object["hintsUsed"] = 3
        object.removeValue(forKey: "startRings")
        object.removeValue(forKey: "endRings")
        object.removeValue(forKey: "madeOn")
        let read = try #require(FinishedPlayPayload(
            format: 1, payload: try JSONSerialization.data(withJSONObject: object), recordName: play.playID.uuidString
        ))
        #expect(read.play == play, "a play begins at every ring on and is finished at every ring off")
        #expect(read.madeOn == "")
    }

    @Test func aFinishedPlayInAnotherFormatOrUnderAnotherNameIsNotRead() throws {
        let data = try FinishedPlayPayload(play: play, madeOn: "Mac", appVersion: "2.0").encoded()
        #expect(FinishedPlayPayload(format: 2, payload: data, recordName: play.playID.uuidString) == nil)
        #expect(FinishedPlayPayload(format: 1, payload: data, recordName: UUID().uuidString) == nil)
        #expect(FinishedPlayPayload(format: 1, payload: data, recordName: "toy") == nil)
        #expect(FinishedPlayPayload(format: 1, payload: Data("{}".utf8), recordName: play.playID.uuidString) == nil)
    }

    // MARK: Sizes

    /// The sizes are far below CloudKit's limit of 1 MB a record [12]: the measured sizes, for the design text.
    @Test func thePayloadsAreSmall() throws {
        let untouched = try ToyPayload(
            toy: PlayState().snapshot, changedAt: .now, changedOn: "iPhone", appVersion: "1.5", stamps: (0..<20).map { _ in UUID() }
        ).encoded()
        let finished = try FinishedPlayPayload(play: play, madeOn: "iPhone", appVersion: "1.5").encoded()
        #expect(untouched.count < 1_500)
        #expect(finished.count < 400)
    }
}
