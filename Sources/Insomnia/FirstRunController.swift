import AppKit
import InsomniaCore

/// On launch, if no agent integration is set up yet, offers to install one for
/// whichever agents are detected on the machine. Shown at most once (tracked in
/// `UserDefaults`) so a user who declines isn't nagged on every launch.
enum FirstRunController {
    private static let didOfferKey = "InsomniaDidOfferIntegrationSetup"

    /// Run the first-launch check. Safe to call on every launch — it returns
    /// immediately once the offer has been made.
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didOfferKey) else { return }

        let hookPath = AgentIntegration.defaultHookBinaryPath()
        var integrated: [AgentKind] = []
        var candidates: [AgentKind] = []

        for agent in AgentKind.allCases {
            let installer = AgentIntegration.installer(for: agent)
            switch installer.status(expectedHookBinaryPath: hookPath) {
            case .installed, .stale:
                integrated.append(agent)
            case .notInstalled, .configMissing, .error:
                if installer.isAgentPresent { candidates.append(agent) }
            }
        }

        // Make the offer at most once, regardless of the outcome.
        defaults.set(true, forKey: didOfferKey)

        // Don't prompt if something is already wired up, or if there's nothing
        // on this machine to wire up.
        guard integrated.isEmpty, !candidates.isEmpty else { return }

        promptAndInstall(candidates: candidates, hookPath: hookPath)
    }

    private static func promptAndInstall(candidates: [AgentKind], hookPath: String) {
        NSApp.activate(ignoringOtherApps: true)

        let names = candidates.map(\.displayName).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Set up Insomnia?"
        alert.informativeText = """
            Insomnia keeps your Mac awake while an AI coding agent is working, \
            so long tasks aren't cut off when the Mac sleeps.

            Detected on this machine: \(names).

            Install the integration now? You can change this anytime from the \
            menu bar. Restart any running agent sessions afterward.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var failures: [String] = []
        for agent in candidates {
            do {
                try AgentIntegration.installer(for: agent).install(hookBinaryPath: hookPath)
            } catch {
                failures.append("\(agent.displayName): \(error.localizedDescription)")
            }
        }

        let result = NSAlert()
        if failures.isEmpty {
            result.messageText = "Integration installed"
            result.informativeText =
                "Restart any running agent sessions for the hooks to take effect."
            result.alertStyle = .informational
        } else {
            result.messageText = "Some integrations could not be installed"
            result.informativeText = failures.joined(separator: "\n")
            result.alertStyle = .warning
        }
        result.runModal()
    }
}
