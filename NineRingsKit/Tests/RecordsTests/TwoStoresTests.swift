import Foundation
import Puzzle
@testable import Records
import Session
import SwiftData
import Testing

/// The finished plays moved and copied between the device's store and the iCloud store, both in memory and never
/// syncing: the iCloud store is its stand-in.
@MainActor
@Suite struct TwoStoresTests {
    private let device: RecordStore
    private let cloud: RecordStore

    init() throws {
        device = RecordStore(container: try RecordStore.deviceContainer(in: .memory))
        cloud = RecordStore(container: try RecordStore.cloudContainer(in: .memory, environment: .development))
    }

    private func play(_ seconds: Double, id: UUID = UUID(), moves: Int = 341) -> PlayRecord {
        let finishedAt = Date(timeIntervalSince1970: seconds)
        return PlayRecord(
            playID: id, startedAt: finishedAt.addingTimeInterval(-600), finishedAt: finishedAt, startRings: .allOn,
            endRings: .allOff, moves: moves, undos: 0, movesPlayedForThePerson: 0, secondsSpent: 512.5
        )
    }

    private func plays(in store: RecordStore) throws -> [FinishedPlay] {
        try store.container.mainContext.fetch(FetchDescriptor<FinishedPlay>(sortBy: [SortDescriptor(\.finishedAt)]))
    }

    private func ids(in store: RecordStore) throws -> [UUID] {
        try plays(in: store).map(\.playID)
    }

    // MARK: Moving, as sync goes on

    @Test func movingWritesEveryPlayThereAndLeavesNoneHere() throws {
        let recorded = (1...5).map { play(Double($0) * 1_000) }
        for record in recorded { try device.record(record, madeOn: .iPad, appVersion: "1.4") }
        let written = try device.moveFinishedPlays(to: cloud, batchSize: 2)
        #expect(written == 5)
        #expect(try ids(in: cloud) == recorded.map(\.playID))
        #expect(try ids(in: device).isEmpty)
        #expect(try cloud.history().compactMap(\.record) == recorded.reversed())
    }

    /// A play the iCloud store already holds, as another device recorded it or a move cut short left it, is not written
    /// again, and the copy there stays as it was.
    @Test func movingSkipsAPlayAlreadyThere() throws {
        let both = play(1_000)
        let deviceOnly = play(2_000)
        try cloud.record(both, madeOn: .iPhone, appVersion: "1.4")
        try device.record(both, madeOn: .Mac, appVersion: "1.4")
        try device.record(deviceOnly, madeOn: .Mac, appVersion: "1.4")
        #expect(try device.moveFinishedPlays(to: cloud) == 1)
        #expect(try ids(in: cloud) == [both.playID, deviceOnly.playID])
        #expect(try plays(in: cloud).first?.madeOn == "iPhone")
        #expect(try ids(in: device).isEmpty)
    }

    /// A move cut short after the iCloud store saved a batch, before the device's store removed it: moving again
    /// leaves every play there once and none here.
    @Test func aMoveCutShortIsTakenUpAgain() throws {
        let recorded = (1...5).map { play(Double($0) * 1_000) }
        for record in recorded { try device.record(record, madeOn: .iPhone, appVersion: "1.4") }
        // The first batch of two reached the iCloud store; then the app was quit.
        for record in recorded.prefix(2) { try cloud.record(record, madeOn: .iPhone, appVersion: "1.4") }
        #expect(try ids(in: device).count == 5)

        #expect(try device.moveFinishedPlays(to: cloud, batchSize: 2) == 3)
        #expect(try ids(in: cloud) == recorded.map(\.playID))
        #expect(try ids(in: device).isEmpty)
        #expect(try device.moveFinishedPlays(to: cloud) == 0, "moving again finds nothing")
    }

    /// Two copies of one play in the device's store, as a store restored from a backup might hold, arrive as one.
    @Test func twoCopiesOfAPlayArriveAsOne() throws {
        let twice = play(1_000)
        let context = device.container.mainContext
        context.insert(FinishedPlay(twice, madeOn: .iPhone, appVersion: "1.4"))
        context.insert(FinishedPlay(twice, madeOn: .iPhone, appVersion: "1.4"))
        try context.save()
        #expect(try device.moveFinishedPlays(to: cloud) == 1)
        #expect(try ids(in: cloud) == [twice.playID])
        #expect(try ids(in: device).isEmpty)
    }

    // MARK: Copying, as the switch goes off

    @Test func copyingWritesWhatIsMissingAndLeavesTheSourceAsItIs() throws {
        let recorded = (1...3).map { play(Double($0) * 1_000) }
        for record in recorded { try cloud.record(record, madeOn: .iPad, appVersion: "1.4") }
        try device.record(recorded[1], madeOn: .Mac, appVersion: "1.4")
        #expect(try cloud.copyFinishedPlays(to: device, batchSize: 2) == 2)
        #expect(try ids(in: device) == recorded.map(\.playID))
        #expect(try plays(in: device)[1].madeOn == "Mac", "the device's own copy stays")
        #expect(try ids(in: cloud) == recorded.map(\.playID), "nothing in the iCloud store changes")
    }

    /// A copy cut short is finished by copying again: what is there is skipped.
    @Test func aCopyCutShortIsFinishedByCopyingAgain() throws {
        let recorded = (1...5).map { play(Double($0) * 1_000) }
        for record in recorded { try cloud.record(record, madeOn: .iPad, appVersion: "1.4") }
        for record in recorded.prefix(2) { try device.record(record, madeOn: .iPad, appVersion: "1.4") }
        #expect(try cloud.copyFinishedPlays(to: device, batchSize: 2) == 3)
        #expect(try ids(in: device) == recorded.map(\.playID))
        #expect(try cloud.copyFinishedPlays(to: device) == 0)
    }

    // MARK: What a copy carries

    /// A record copied to the other store is the same record, field for field, even one this build does not understand.
    @Test func aCopyCarriesEveryFieldAsItIs() throws {
        let original = FinishedPlay(play(1_000, moves: 400), madeOn: .iPad, appVersion: "9.1")
        original.rules = PlayRecord.rules + 1
        original.startRings = "a later kind of arrangement"
        original.undos = 3
        original.movesPlayedForThePerson = 6
        original.secondsSpent = 77.25
        device.container.mainContext.insert(original)
        try device.container.mainContext.save()

        try device.moveFinishedPlays(to: cloud)
        let copy = try #require(try plays(in: cloud).first)
        #expect(copy.playID == original.playID && copy.finishedAt == original.finishedAt)
        #expect(copy.startedAt == original.startedAt && copy.startRings == "a later kind of arrangement")
        #expect(copy.endRings == "000000000" && copy.moves == 400 && copy.undos == 3)
        #expect(copy.movesPlayedForThePerson == 6 && copy.secondsSpent == 77.25)
        #expect(copy.madeOn == "iPad" && copy.appVersion == "9.1" && copy.rules == PlayRecord.rules + 1)
        #expect(copy.record == nil, "still a record this build does not read")
    }

    /// Every stored field is copied: a field added to a model must be added to its copy too.
    @Test func theCopiesCarryEveryFieldOfTheSchema() {
        let fields = Dictionary(uniqueKeysWithValues: RecordStore.schema.entities.map { ($0.name, Set($0.attributes.map(\.name))) })
        #expect(fields["FinishedPlay"] == FinishedPlay.copiedFields)
        #expect(fields["SavedToy"] == SavedToy.copiedFields)
    }

    // MARK: A play recorded twice

    /// The same play recorded on two devices, both copies brought together in the iCloud store: it shows once, the
    /// earlier, and both stay.
    @Test func aPlayRecordedOnTwoDevicesShowsOnce() throws {
        let id = UUID()
        try cloud.record(play(1_000, id: id), madeOn: .iPhone, appVersion: "1.4")
        let laterCopy = FinishedPlay(play(1_005, id: id), madeOn: .Mac, appVersion: "1.4")
        cloud.container.mainContext.insert(laterCopy)
        try cloud.container.mainContext.save()
        try device.record(play(2_000), madeOn: .Mac, appVersion: "1.4")
        try device.moveFinishedPlays(to: cloud)

        let history = try cloud.history()
        #expect(history.count == 2)
        #expect(history.last?.playID == id && history.last?.madeOn == "iPhone")
        #expect(try plays(in: cloud).count == 3, "nothing is deleted")
    }

    // MARK: The stores' configurations

    /// In a folder, the iCloud store syncs with the app's own container, through CloudKit's private database, in a file
    /// of its own for each environment, in an `iCloud` folder beside the device's store.
    @Test(arguments: RecordStore.CloudEnvironment.allCases)
    func theICloudStoreSyncsWithTheAppsContainer(environment: RecordStore.CloudEnvironment) throws {
        let folder = URL(filePath: "/somewhere/NineRings", directoryHint: .isDirectory)
        let configuration = RecordStore.cloudConfiguration(in: .folder(folder), environment: environment)
        let described = String(reflecting: configuration.cloudKitDatabase)
        #expect(described == String(reflecting: ModelConfiguration.CloudKitDatabase.private("iCloud.com.chentianren.PlayNineRings")))
        #expect(described != String(reflecting: ModelConfiguration.CloudKitDatabase.automatic))
        #expect(described != String(reflecting: ModelConfiguration.CloudKitDatabase.none))
        #expect(configuration.url == folder.appending(path: "iCloud/\(environment.rawValue).store"))
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(configuration.url != RecordStore.deviceConfiguration(in: .folder(folder)).url)
    }

    @Test func eachEnvironmentHasAFileOfItsOwn() {
        let folder = RecordStore.folder
        let urls = Set(RecordStore.CloudEnvironment.allCases.map { RecordStore.cloudConfiguration(in: .folder(folder), environment: $0).url })
        #expect(urls.count == RecordStore.CloudEnvironment.allCases.count)
    }

    /// A debug build's iCloud store is in its own folder: it never opens a release build's file.
    @Test(arguments: RecordStore.CloudEnvironment.allCases)
    func aDebugBuildsICloudStoreIsItsOwn(environment: RecordStore.CloudEnvironment) {
        let release = RecordStore.cloudConfiguration(in: .folder(RecordStore.folder), environment: environment).url
        let debug = RecordStore.cloudConfiguration(in: .folder(RecordStore.debugFolder), environment: environment).url
        #expect(release != debug)
        #expect(debug.deletingLastPathComponent().deletingLastPathComponent() == RecordStore.debugFolder)
    }

    /// In memory, the iCloud store is a stand-in that never syncs: a launch in memory opens no iCloud store.
    @Test(arguments: RecordStore.CloudEnvironment.allCases)
    func inMemoryTheICloudStoreNeverSyncs(environment: RecordStore.CloudEnvironment) throws {
        let configuration = RecordStore.cloudConfiguration(in: .memory, environment: environment)
        #expect(configuration.isStoredInMemoryOnly)
        #expect(String(reflecting: configuration.cloudKitDatabase) == String(reflecting: ModelConfiguration.CloudKitDatabase.none))
        let container = try RecordStore.cloudContainer(in: .memory, environment: environment)
        let inMemory = container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        #expect(inMemory)
    }
}
