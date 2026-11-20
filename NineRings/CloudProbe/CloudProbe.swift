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
/// - `-cloudkit-probe all` asks questions 1 to 16; `-cloudkit-probe 1,2,12` asks those (``ProbeRun/questions``).
/// - Questions 17 and 18 take a launch each, in that order: 17 ends the process when a save's confirmation arrives, and
///   18 starts from what 17 kept.
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
    static let questions: [Int]? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-cloudkit-probe"), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        if value == "all" { return ProbeRun.askedByAll }
        let numbers = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return numbers.isEmpty ? nil : numbers
    }()

    /// Whether this launch runs the probe.
    static var isAsked: Bool { questions != nil }

    /// Starts the probe when the launch asks for it.
    static func startIfAsked() {
        guard let questions else { return }
        Task.detached { await run(questions) }
    }

    nonisolated private static func run(_ questions: [Int]) async {
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
