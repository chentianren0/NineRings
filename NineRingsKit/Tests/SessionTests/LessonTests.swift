import Foundation
import Motion
import Puzzle
import Session
import Testing

@Suite struct LessonTests {
    private let steps = Lesson.steps

    /// The moves the lesson plays, in order, each once: a held move counts when it is finished.
    private var movesPlayed: [Move] {
        steps.flatMap { step -> [Move] in
            switch step.show {
            case .rest, .hold: []
            case .play(let moves): moves
            case .finish(let move, _): [move]
            }
        }
    }

    @Test func beginsWithEveryRingOn() {
        #expect(steps.first?.start == .allOn)
    }

    @Test func eachStepStartsWhereTheLastEnded() {
        for (before, after) in zip(steps, steps.dropFirst()) {
            #expect(after.start == before.end, "\(after.key) starts where \(before.key) ended")
        }
        for step in steps {
            guard case .play(let moves) = step.show else { continue }
            #expect(!moves.isEmpty, "\(step.key) plays something")
            for (first, second) in zip(moves, moves.dropFirst()) {
                #expect(second.from == first.to, "in \(step.key), each move starts where the last ended")
            }
        }
    }

    @Test func aFinishFollowsTheHoldOfTheSameMoveAtTheSameStage() {
        for (index, step) in steps.enumerated() {
            if case .finish(let move, let stage) = step.show {
                #expect(index > 0 && steps[index - 1].show == .hold(move, afterStage: stage), "\(step.key) finishes the move held just before")
            }
            if case .hold(let move, let stage) = step.show {
                #expect(index + 1 < steps.count && steps[index + 1].show == .finish(move, afterStage: stage), "\(step.key) is finished by the next step")
            }
        }
    }

    /// Every move is legal, since a `Move` exists only when the rule allows it; and they are the first moves of the
    /// shortest way from every ring on to every ring off.
    @Test func theMovesAreTheFirstMovesOfTheShortestWay() {
        let played = movesPlayed
        let shortest = PuzzleState.allOn.moves(to: .allOff)
        #expect(played.map(\.ring) == Array(shortest.prefix(played.count)))
        #expect(played.map(\.ring) == [1, 3, 1, 2, 1, 5])
        #expect(shortest.count == 341, "the lesson says all nine rings take 341 moves")
    }

    @Test func eachHeldStageExistsForItsMove() throws {
        for step in steps {
            switch step.show {
            case .hold(let move, let key), .finish(let move, let key):
                let motion = MoveMotion(move)
                let progress = try #require(step.heldProgress, "\(step.key) holds at a stage the move has")
                let stage = try #require(motion.stages.first { $0.key == key })
                #expect(motion.stage(at: progress).key == key, "at the hold the move is still in its stage")
                #expect(progress > stage.start && progress < stage.end)
                #expect(stage.end - progress < 1e-9, "the hold is at the stage's end")
            case .rest, .play:
                #expect(step.heldProgress == nil)
            }
        }
    }

    @Test func keysAreDistinct() {
        #expect(Set(steps.map(\.key)).count == steps.count)
    }

    /// The app's `Lesson` String Catalog has an English text and a translator's comment for every step, and nothing
    /// that no step uses.
    @Test func everyKeyHasItsTextInTheCatalog() throws {
        let catalog = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "NineRings/Lesson.xcstrings")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        #expect(Set(strings.keys) == Set(steps.map(\.key)))
        for step in steps {
            let entry = try #require(strings[step.key], "\(step.key) is in the catalog")
            #expect(!((entry["comment"] as? String) ?? "").isEmpty, "\(step.key) has a translator's comment")
            let english = try #require((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
            let texts: [Any?]
            if let devices = (english["variations"] as? [String: Any])?["device"] as? [String: [String: Any]] {
                #expect(devices["other"] != nil, "\(step.key) has a text for every device")
                texts = devices.values.map { $0["stringUnit"] }
            } else {
                texts = [english["stringUnit"]]
            }
            for unit in texts {
                let value = ((unit as? [String: Any])?["value"] as? String) ?? ""
                #expect(!value.isEmpty, "\(step.key) has its English text")
            }
        }
    }
}
