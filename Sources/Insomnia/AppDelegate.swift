import AppKit
import InsomniaCore

/// Owns the app's lifecycle and policy. A directory watcher and a periodic
/// timer both drive a single `reconcile()` entry point, which runs the pure
/// `ReconcileEngine`, applies the result to the IOKit assertion, reaps stale
/// files, and refreshes the menu. Menu clicks come back through
/// `StatusItemControllerDelegate`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusController = StatusItemController()
    private let powerAssertion = PowerAssertion()
    private let sessionStore = SessionStore()

    private var watcher: SessionWatcher?
    private var timer: ReconcileTimer?
    private var powerSourceMonitor: PowerSourceMonitor?
    private var settingsWindow: SettingsWindowController?

    /// Persisted preferences (grace period, caps, on-AC-only).
    private var config = Config.load()
    /// Runtime-only — manual overrides reset on relaunch by design.
    private var manualOverride: ManualOverride = .none

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController.delegate = self
        statusController.install()

        watcher = SessionWatcher(directory: Paths.sessionsDir) { [weak self] in
            self?.reconcile()
        }
        watcher?.start()

        timer = ReconcileTimer(interval: 10) { [weak self] in
            self?.timerTick()
        }
        timer?.start()

        powerSourceMonitor = PowerSourceMonitor { [weak self] in
            self?.reconcile()
        }
        powerSourceMonitor?.start()

        reconcile()
        FirstRunController.runIfNeeded { [weak self] in self?.openSettings(mode: .onboarding) }
        reconcile()   // reflect anything first-run setup just installed
    }

    /// Open (or focus) the settings window in the given mode.
    private func openSettings(mode: SettingsWindowController.Mode) {
        if let existing = settingsWindow {
            existing.refresh(state: currentSettingsState())
            existing.present()
            return
        }
        let window = SettingsWindowController(
            mode: mode,
            state: currentSettingsState(),
            delegate: self)
        settingsWindow = window
        window.present()
    }

    /// Snapshot of the data the settings window needs to render.
    private func currentSettingsState() -> SettingsState {
        var present: Set<AgentKind> = []
        for agent in AgentKind.allCases {
            if AgentIntegration.installer(for: agent).isAgentPresent {
                present.insert(agent)
            }
        }
        return SettingsState(
            followedAgents: followedAgents(),
            presentAgents: present,
            gracePeriodSeconds: config.gracePeriodSeconds,
            onACOnly: config.onACOnly,
            launchAtLoginEnabled: LoginItem.isEnabled)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.stop()
        watcher?.stop()
        powerSourceMonitor?.stop()
        // A leaked assertion keeps the Mac awake until reboot. (IOKit also
        // auto-releases on process exit, but be explicit.)
        powerAssertion.release()
    }

    /// Timer-driven path: sweep stale temp files left by killed hook processes,
    /// then reconcile. (The watcher path calls `reconcile()` directly.)
    private func timerTick() {
        sessionStore.sweepTempFiles(olderThan: 300)
        reconcile()
    }

    /// The single reconcile entry point. Always runs on the main thread.
    private func reconcile() {
        let followed = followedAgents()
        let sessions = sessionStore.list()
        let decision = ReconcileEngine.reconcile(
            sessions: sessions,
            config: config,
            followedAgents: followed,
            manualOverride: manualOverride,
            onACPower: PowerSourceMonitor.isOnACPower)

        powerAssertion.apply(decision)
        for url in decision.filesToDelete {
            sessionStore.delete(url)
        }
        statusController.render(MenuState(
            decision: decision,
            manualOverride: manualOverride,
            config: config,
            followedAgents: followed,
            launchAtLoginEnabled: LoginItem.isEnabled))
        settingsWindow?.refresh(state: currentSettingsState())
    }

    /// Which agents are currently followed — derived from whether each agent's
    /// integration is actually installed, so the app and the `insomnia-hook`
    /// CLI never disagree.
    private func followedAgents() -> Set<AgentKind> {
        let hookPath = AgentIntegration.defaultHookBinaryPath()
        var result: Set<AgentKind> = []
        for agent in AgentKind.allCases {
            switch AgentIntegration.installer(for: agent).status(expectedHookBinaryPath: hookPath) {
            case .installed, .stale: result.insert(agent)
            case .notInstalled, .configMissing, .error: break
            }
        }
        return result
    }

    private func presentError(_ error: Error, doing context: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't \(context)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentInfo(_ message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - StatusItemControllerDelegate

extension AppDelegate: StatusItemControllerDelegate {
    func statusItemDidSetManualOverride(_ override: ManualOverride) {
        manualOverride = override
        reconcile()
    }

    func statusItemDidRequestSettings() {
        openSettings(mode: .settings)
    }

    func statusItemDidRequestQuit() {
        powerAssertion.release()
        NSApp.terminate(nil)
    }
}

// MARK: - SettingsWindowDelegate

extension AppDelegate: SettingsWindowDelegate {
    func settingsDidSetGracePeriod(_ seconds: TimeInterval) {
        config.gracePeriodSeconds = seconds
        config.save()
        reconcile()
    }

    func settingsDidSetOnACOnly(_ enabled: Bool) {
        config.onACOnly = enabled
        config.save()
        reconcile()
    }

    func settingsDidToggleAgent(_ agent: AgentKind, followed: Bool) {
        let installer = AgentIntegration.installer(for: agent)
        do {
            if followed {
                try installer.install(
                    hookBinaryPath: AgentIntegration.defaultHookBinaryPath())
            } else {
                try installer.uninstall()
            }
        } catch {
            presentError(error, doing: followed
                ? "set up the \(agent.displayName) integration"
                : "remove the \(agent.displayName) integration")
        }
        // `followedAgents()` re-reads integration status, so the checkbox
        // updates from ground truth on the next render.
        reconcile()
    }

    func settingsDidToggleLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        // Re-render reflects the real SMAppService status (which may still be
        // "off" if macOS requires approval in System Settings).
        reconcile()
    }
}
