#if DEBUG
import CloudKit
import Foundation
#if os(macOS)
import AppKit
import Security
#endif

/// A probe of what `CKSyncEngine` does where Apple does not document it, run against CloudKit's development
/// environment by a debug build that a launch asks for it. `docs/icloud-probe.md` says what it showed, and how to run it.
///
/// - `-cloudkit-probe all` asks questions 1 to 14 and A to G; `-cloudkit-probe zones` asks A to G; `-cloudkit-probe 1,2,E`
///   asks those, and a question named twice is asked twice (``ProbeRun/titles``).
/// - Questions 15 and 16 take a launch each, in that order: 15 ends the process when a save's confirmation arrives, and
///   16 starts from what 15 kept.
/// - Question D's third part takes three launches: two at once, `-cloudkit-probe race -probe-zone <name> -probe-role <X>
///   -probe-at <seconds since 1970>`, which save the same new zone at that moment, then `-cloudkit-probe race-check
///   -probe-zone <name>`, which looks at the zone and deletes it. `scripts/cloudkit-probe-race.sh` runs the three.
///
/// The report goes to standard output, line by line, and to the log. The app writes no file: whoever launches it says
/// where standard output goes. The app quits when the probe is done. While the probe runs, the app keeps its own records
/// in memory (`LaunchOptions.recordPlace`), so that nothing else in it talks to CloudKit.
///
/// The probe uses the iCloud account the device is signed in to, in its private database, and only zones whose names
/// begin with ``ProbeRun/zonePrefix``: it deletes each question's zone at the question's end, and every such zone at
/// the start and the end of a run. It stops before reaching CloudKit when the build lacks the iCloud entitlement or
/// would talk to production.
enum CloudProbe {
    /// The app's iCloud container, named here so that the probe does not depend on the cloud code it is there to inform.
    nonisolated static let container = "iCloud.com.chentianren.PlayNineRings"

    /// The questions this launch asks, in order, or nil when it asks for no probe.
    static let questions: [String]? = {
        guard let value = argument("-cloudkit-probe") else { return nil }
        if value == "all" { return ProbeRun.askedByAll }
        if value == "zones" { return ProbeRun.askedByZones }
        let names = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }()

    /// The value that follows `name` among the launch's arguments.
    nonisolated private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Whether this launch runs the probe.
    static var isAsked: Bool { questions != nil }

    /// Starts the probe when the launch asks for it.
    static func startIfAsked() {
        guard let questions else { return }
        Task.detached { await run(questions) }
    }

    nonisolated private static func run(_ questions: [String]) async {
        let report = ProbeReport()
        let info = ProcessInfo.processInfo
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        await report.say("--", "Nine Rings CloudKit probe: \(info.operatingSystemVersionString), app build \(build), \(Date.now.formatted(.iso8601))")
        await report.say("--", "questions: \(questions)")
        defer { Task { @MainActor in quit() } }

        guard entitlement("com.apple.developer.icloud-container-identifiers").contains(container) else {
            return await report.say("--", "STOPPED: this build does not have the iCloud entitlement for \(container)")
        }
        let environment = entitlement("com.apple.developer.icloud-container-environment")
        guard !environment.contains("Production") else {
            return await report.say("--", "STOPPED: this build talks to CloudKit's production environment; the probe runs in development only")
        }
        await report.say("--", "the build talks to the development environment of \(container)")

        let cloud = CKContainer(identifier: container)
        do {
            let status = try await cloud.accountStatus()
            await report.say("--", "account status: \(describe(status))")
            guard status == .available else {
                return await report.say("--", "STOPPED: no iCloud account is available")
            }
        } catch {
            return await report.say("--", "STOPPED: the account status could not be read: \(ProbeText.error(error))")
        }

        let run = ProbeRun(database: cloud.privateCloudDatabase, report: report, run: String(UUID().uuidString.prefix(6)))
        // The launches of question D's third part leave the other zones alone: two of them run at once.
        if questions == ["race"] || questions == ["race-check"] {
            guard let zoneName = argument("-probe-zone") else { return await report.say("--", "STOPPED: no -probe-zone") }
            if questions == ["race-check"] {
                await report.heading("D.3 Two launches that saved the same new zone: what is there")
                return await run.raceCheck(zoneName: zoneName)
            }
            guard let role = argument("-probe-role"), let at = argument("-probe-at").flatMap(Double.init) else {
                return await report.say("--", "STOPPED: a race launch needs -probe-role and -probe-at")
            }
            await report.heading("D.3 One of two launches saving the same new zone at one moment")
            return await run.raceSave(zoneName: zoneName, role: role, at: Date(timeIntervalSince1970: at))
        }
        await run.describeStart()
        await run.removeProbeZones()
        for question in questions {
            await run.ask(question)
        }
        await report.heading("End")
        await run.removeProbeZones()
        await report.say("--", "done")
    }

    /// The values of entitlement `key`, as strings: none when the build does not carry it.
    nonisolated private static func entitlement(_ key: String) -> [String] {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil), let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return [] }
        return (value as? [String]) ?? (value as? String).map { [$0] } ?? []
        #else
        // On iPhone and iPad a debug build is installed by Xcode, signed with its entitlements, and talks to development.
        return key == "com.apple.developer.icloud-container-identifiers" ? [container] : []
        #endif
    }

    nonisolated private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .noAccount: "no account"
        case .restricted: "restricted"
        case .couldNotDetermine: "could not be determined"
        case .temporarilyUnavailable: "temporarily unavailable"
        @unknown default: "\(status.rawValue)"
        }
    }

    private static func quit() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #endif
    }
}
#endif
