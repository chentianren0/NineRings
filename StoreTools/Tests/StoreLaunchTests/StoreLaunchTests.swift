import Foundation
import Motion
import Puzzle
import Session
import StoreComposer
@testable import StoreLaunch
import Testing

/// The app's reading of the store-capture arguments (its own file, NineRings/Store/StoreLaunch.swift).
@Suite struct StoreLaunchTests {
    func parse(_ arguments: String) throws -> StoreLaunch? {
        try StoreLaunch.parse(["NineRings"] + arguments.split(separator: " ").map(String.init))
    }

    @Test func offWithoutTheFlag() throws {
        #expect(try parse("-move 5 -start-progress 0.5") == nil)
    }

    @Test func readsEachOption() throws {
        let launch = try #require(try parse("-state 000111111 -move 5 -start-progress 0.55 -view top -window-size 1280x800 -store-capture"))
        #expect(launch.state == "000111111")
        #expect(launch.move == 5)
        #expect(launch.progress == 0.55)
        #expect(launch.view == .preset("top"))
        #expect(launch.windowSize == StoreLaunch.Size(width: 1280, height: 800))
        #expect(!launch.paused && !launch.congratulation)
    }

    @Test func readsAnglesWithANegativeYaw() throws {
        let launch = try #require(try parse("-store-capture -view -45:30"))
        #expect(launch.view == .angles(yaw: -45, pitch: 30))
    }

    @Test func readsTheLessonHeldPartWay() throws {
        let launch = try #require(try parse("-lesson-step 7 -start-progress 0.5 -paused -store-capture"))
        #expect(launch.lessonStep == 7 && launch.progress == 0.5 && launch.paused)
    }

    @Test(arguments: [
        ("-store-capture -state 00011111", StoreLaunch.Problem.badValue(option: "-state", value: "00011111")),
        ("-store-capture -state 0001111x1", .badValue(option: "-state", value: "0001111x1")),
        ("-store-capture -move 10", .badValue(option: "-move", value: "10")),
        ("-store-capture -refuse 0", .badValue(option: "-refuse", value: "0")),
        ("-store-capture -move 3 -start-progress 1.5", .badValue(option: "-start-progress", value: "1.5")),
        ("-store-capture -view front", .badValue(option: "-view", value: "front")),
        ("-store-capture -view 10:95", .badValue(option: "-view", value: "10:95")),
        ("-store-capture -window-size 1280", .badValue(option: "-window-size", value: "1280")),
        ("-store-capture -move -paused", .missingValue(option: "-move")),
        ("-store-capture -refuse", .missingValue(option: "-refuse")),
        ("-store-capture -move 5 -refuse 5", .conflict("-move", "-refuse")),
        ("-store-capture -lesson-step 7 -congratulation", .conflict("-lesson-step", "-congratulation")),
        ("-store-capture -lesson-step 7 -state 111111111", .conflict("-lesson-step", "-state")),
        ("-store-capture -start-progress 0.5", .conflict("-start-progress", "no -move or -lesson-step")),
        ("-store-capture -move 5 -paused", .conflict("-paused", "no -lesson-step")),
    ])
    func refusesWrongArguments(_ arguments: String, problem: StoreLaunch.Problem) {
        #expect(throws: problem) { try parse(arguments) }
    }
}

/// The app's rule for when the picture may be taken (NineRings/Store/StoreReadiness.swift).
@Suite struct StoreReadinessTests {
    @Test func waitsForTheToyToBeDrawn() {
        var readiness = StoreReadiness<Int>(settle: 1, minimumFrames: 30)
        var ready = false
        ready = readiness.observe(1, at: 0, drawnFrames: 0)
        #expect(!ready)
        ready = readiness.observe(1, at: 5, drawnFrames: 29)
        #expect(!ready)
        // Drawn enough only now: the settling time counts from here.
        ready = readiness.observe(1, at: 5.5, drawnFrames: 30)
        #expect(!ready)
        ready = readiness.observe(1, at: 6.6, drawnFrames: 60)
        #expect(ready)
    }

    @Test func startsAgainAtEveryChange() {
        var readiness = StoreReadiness<Int>(settle: 1, minimumFrames: 1)
        var ready = false
        readiness.observe(1, at: 0, drawnFrames: 10)
        ready = readiness.observe(2, at: 0.5, drawnFrames: 10)
        #expect(!ready)
        ready = readiness.observe(2, at: 1.25, drawnFrames: 10)
        #expect(!ready)
        ready = readiness.observe(2, at: 1.5, drawnFrames: 10)
        #expect(ready)
    }

    @Test func staysReady() {
        var readiness = StoreReadiness<Int>(settle: 1, minimumFrames: 1)
        var ready = false
        readiness.observe(1, at: 0, drawnFrames: 10)
        ready = readiness.observe(1, at: 1, drawnFrames: 10)
        #expect(ready)
        ready = readiness.observe(2, at: 1.1, drawnFrames: 10)
        #expect(ready)
    }
}

/// Shots.json against the app and the rules: every moment launches, and shows what its name says.
@Suite struct SeriesTests {
    static let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try! Manifest(contentsOf: folder.appending(path: "Shots.json"))
    let captions = try! CaptionCatalog(contentsOf: folder.appending(path: "Captions.xcstrings"))

    func launch(_ moment: Manifest.Moment) throws -> StoreLaunch {
        try #require(try StoreLaunch.parse(["NineRings"] + moment.arguments + [StoreLaunch.flag]))
    }

    @Test func sixMomentsInOrder() {
        #expect(manifest.moments.map(\.id) == ["01", "02", "03", "04", "05", "06"])
    }

    @Test func everyMomentLaunches() throws {
        for moment in manifest.moments {
            _ = try launch(moment)
        }
    }

    @Test func movesAndRefusalsAreAsTheRulesHaveThem() throws {
        for moment in manifest.moments {
            let launch = try launch(moment)
            let state = launch.state.flatMap { PuzzleState($0) } ?? .allOn
            if let ring = launch.move, launch.state != nil {
                #expect(Move(ring: ring, from: state) != nil, "moment \(moment.id): ring \(ring) cannot move at \(state)")
            }
            if let ring = launch.move, launch.state == nil {
                #expect(MoveMotion.written.contains { $0.ring == ring }, "moment \(moment.id)")
            }
            if let ring = launch.refuse {
                #expect(state.block(for: ring) != nil, "moment \(moment.id): ring \(ring) is free to move at \(state)")
            }
            if let step = launch.lessonStep {
                #expect(Lesson.steps.indices.contains(step - 1), "moment \(moment.id): no lesson step \(step)")
            }
        }
    }

    @Test func theRefusedRingIsBlockedByRingThree() throws {
        let moment = try #require(manifest.moments.first { $0.id == "03" })
        let launch = try launch(moment)
        let ring = try #require(launch.refuse)
        let block = try #require(PuzzleState.allOn.block(for: ring))
        #expect(block.blockingRing == 3)
    }

    @Test func theLastMoveTakesTheLastRingOff() throws {
        let before = try #require(PuzzleState("100000000"))
        let last = try #require(Move(ring: 1, from: before))
        #expect(last.to == .allOff)
    }

    @Test func everyCaptionIsInTheCatalog() {
        for moment in manifest.moments {
            for device in manifest.devices {
                let key = moment.captionKey(on: device.id)
                #expect(captions.text(key, language: "en") != nil, "no caption \(key)")
            }
        }
    }

    @Test func atLeastOneMomentIsDark() {
        // Apple suggests at least one dark picture for an app that has a dark appearance.
        #expect(manifest.moments.contains { $0.appearance == .dark })
    }

    @Test func everyDeviceIsAStoreSize() {
        for device in manifest.devices {
            #expect(device.class.accepts(device.size), "\(device.id) is \(device.size)")
        }
        #expect(DeviceClass.header.accepts(manifest.header.size))
        let safe = manifest.header.safeArea
        #expect(DeviceClass.header.safeArea == CGRect(x: safe[0], y: safe[1], width: safe[2], height: safe[3]))
    }

    @Test func theMacWindowGivesAStoreSizeAtTwiceItsPoints() throws {
        let mac = try manifest.device("mac")
        let window = try #require(mac.window)
        #expect(DeviceClass.mac.accepts(window * 2))
    }
}
