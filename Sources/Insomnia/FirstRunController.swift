import AppKit
import InsomniaCore

/// On launch, if no agent integration is set up yet, opens the settings window
/// in onboarding mode so the user can pick which agents to follow. Shown at
/// most once (tracked in `UserDefaults`) so a user who declines isn't nagged.
enum FirstRunController {
    private static let didOfferKey = "InsomniaDidOfferIntegrationSetup"

    /// Run the first-launch check. Safe to call on every launch — it returns
    /// immediately once the offer has been made.
    /// - Parameter open: closure to open the settings window in onboarding mode.
    static func runIfNeeded(open: () -> Void) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didOfferKey) else { return }

        let hookPath = AgentIntegration.defaultHookBinaryPath()
        var alreadyIntegrated = false
        var hasCandidate = false

        for agent in AgentKind.allCases {
            let installer = AgentIntegration.installer(for: agent)
            switch installer.status(expectedHookBinaryPath: hookPath) {
            case .installed, .stale:
                alreadyIntegrated = true
            case .notInstalled, .configMissing, .error:
                if installer.isAgentPresent { hasCandidate = true }
            }
        }

        // Make the offer at most once, regardless of the outcome.
        defaults.set(true, forKey: didOfferKey)

        // Don't prompt if something is already wired up, or if there's nothing
        // on this machine to wire up.
        guard !alreadyIntegrated, hasCandidate else { return }

        open()
    }
}
