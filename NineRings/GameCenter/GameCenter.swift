import Foundation
import GameKit
import Observation
import Session

/// Game Center, for the achievements: the player signed in at launch, what was earned reported, and the dashboard.
///
/// - It starts when the window first appears, as Apple advises, and presents the sign-in Game Center asks for. With no
///   player signed in the app works the same; the menu item that opens the dashboard is disabled.
/// - What is earned is kept on the device (``AchievementLedger``) and reported as soon as a player is signed in: at
///   once, or when one signs in later, or at the next launch if reporting failed.
/// - No player identifier is read, and nothing goes anywhere but to Game Center.
/// - The store pictures and the capture mode leave it off, so that its banners never show in them.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    /// Whether a player is signed in to Game Center on this device.
    private(set) var isSignedIn = false

    @ObservationIgnored private var ledger: AchievementLedger
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isReporting = false

    private static let ledgerKey = "gameCenter.ledger"

    private init() {
        #if DEBUG
        if Self.option == "reset" { UserDefaults.standard.removeObject(forKey: Self.ledgerKey) }
        #endif
        ledger = UserDefaults.standard.data(forKey: Self.ledgerKey)
            .flatMap { try? JSONDecoder().decode(AchievementLedger.self, from: $0) } ?? AchievementLedger()
    }

    /// Whether Game Center is used at all in this launch.
    static var isEnabled: Bool {
        #if DEBUG
        if option == "off" || Capture.request != nil { return false }
        #endif
        return !StoreCapture.isActive
    }

    #if DEBUG
    /// `-game-center off` leaves Game Center out of this launch and records nothing, for scripted runs that should not
    /// earn anything for the person signed in on this Mac. `-game-center reset` forgets what this device has earned
    /// and reported, so that earning an achievement again reports it again (Game Center keeps what it has taken).
    private static var option: String? { value(after: "-game-center") }

    /// `-earn far_end,all_nine_back_on`: those achievements earned at launch, by their identifiers, to try reporting
    /// and Apple's banner without playing hundreds of moves. The rules themselves are the package's tests.
    private static var earnedAtLaunch: Set<Achievement> {
        Set((value(after: "-earn") ?? "").split(separator: ",").compactMap { Achievement(rawValue: String($0)) })
    }

    private static func value(after option: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #endif

    // MARK: Signing in

    /// Asks Game Center for the player, once per launch. Game Center calls back whenever the player signs in or out.
    func start() {
        guard Self.isEnabled, !hasStarted else { return }
        hasStarted = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                Self.present(viewController)
            }
            isSignedIn = GKLocalPlayer.local.isAuthenticated
            log(isSignedIn ? "signed in" : "not signed in: \(error?.localizedDescription ?? "no player")")
            reportPending()
        }
        #if DEBUG
        earn(Self.earnedAtLaunch)
        #endif
    }

    #if os(iOS)
    private static func present(_ viewController: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(viewController, animated: true)
    }
    #else
    private static func present(_ viewController: NSViewController) {
        let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first { $0.isVisible && $0.level == .normal }
        window?.contentViewController?.presentAsSheet(viewController)
    }
    #endif

    // MARK: Achievements

    /// Takes in what a change to the toy earned: kept on the device, and reported if a player is signed in.
    func earn(_ achievements: Set<Achievement>) {
        guard Self.isEnabled, !achievements.isEmpty, !ledger.earn(achievements).isEmpty else { return }
        save()
        reportPending()
    }

    /// Reports everything earned and not yet taken, with Apple's banner for each.
    private func reportPending() {
        let pending = ledger.pending
        guard isSignedIn, !isReporting, !pending.isEmpty else { return }
        isReporting = true
        let achievements = pending.map { achievement in
            let reported = GKAchievement(identifier: achievement.rawValue)
            reported.percentComplete = 100
            reported.showsCompletionBanner = true
            return reported
        }
        Task {
            do {
                try await GKAchievement.report(achievements)
            } catch {
                // Kept as pending: reported again at the next sign-in, earning or launch.
                isReporting = false
                log("could not report \(pending.map(\.rawValue).sorted()): \(error.localizedDescription)")
                return
            }
            ledger.markReported(pending)
            save()
            log("reported \(pending.map(\.rawValue).sorted())")
            // Cleared before reporting what was earned while this report was on its way, which would otherwise wait.
            isReporting = false
            reportPending()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        UserDefaults.standard.set(data, forKey: Self.ledgerKey)
    }

    // MARK: The dashboard

    /// Opens Game Center's dashboard for this app, over the app. The access point itself is never shown.
    func showDashboard() {
        guard isSignedIn else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    private func log(_ line: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("Game Center: \(line)\n".utf8))
        #endif
    }
}
