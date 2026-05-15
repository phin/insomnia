import AppKit
import InsomniaCore

/// Everything the menu needs to render itself in one pass.
struct MenuState {
    let decision: ReconcileDecision
    let manualOverride: ManualOverride
    let config: Config
    /// Agents whose integration is currently installed (derived, not stored).
    let followedAgents: Set<AgentKind>
    let launchAtLoginEnabled: Bool
}

/// Menu actions are reported back to the owner (the `AppDelegate`), which holds
/// the policy and persists state.
protocol StatusItemControllerDelegate: AnyObject {
    func statusItemDidSetManualOverride(_ override: ManualOverride)
    func statusItemDidSetGracePeriod(_ seconds: TimeInterval)
    func statusItemDidSetOnACOnly(_ enabled: Bool)
    func statusItemDidToggleAgent(_ agent: AgentKind, followed: Bool)
    func statusItemDidToggleLaunchAtLogin(_ enabled: Bool)
    func statusItemDidRequestQuit()
}

/// Owns the `NSStatusItem` (menu bar icon) and rebuilds its menu from a
/// `MenuState`. Pure presentation — it holds no policy, just forwards clicks.
final class StatusItemController: NSObject {
    weak var delegate: StatusItemControllerDelegate?

    private var statusItem: NSStatusItem?
    private var state: MenuState?

    private static let gracePresets: [(label: String, seconds: TimeInterval)] = [
        ("1 minute", 60), ("5 minutes", 300), ("10 minutes", 600),
        ("15 minutes", 900), ("30 minutes", 1800),
    ]

    /// Create the menu bar item. Call once, after the app finishes launching.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.icon(awake: false)
        statusItem = item
    }

    /// Update the icon and rebuild the menu from the latest state.
    func render(_ state: MenuState) {
        self.state = state
        statusItem?.button?.image = Self.icon(awake: state.decision.shouldKeepAwake)
        statusItem?.menu = buildMenu(state)
    }

    // MARK: - Icon

    private static func icon(awake: Bool) -> NSImage? {
        let name = awake ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: awake ? "Keeping Mac awake" : "Idle")
        image?.isTemplate = true   // adapt to light/dark menu bar
        return image
    }

    // MARK: - Menu

    private func buildMenu(_ state: MenuState) -> NSMenu {
        let menu = NSMenu()
        let decision = state.decision

        let header = NSMenuItem(
            title: decision.shouldKeepAwake ? "Keeping Mac awake" : "Idle — Mac can sleep",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !decision.activeSessions.isEmpty {
            menu.addItem(.separator())
            for session in decision.activeSessions {
                let item = NSMenuItem(title: Self.sessionLine(session),
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        // Manual overrides (mutually exclusive — a single enum value).
        menu.addItem(.separator())
        menu.addItem(check("Keep Awake Anyway", #selector(keepAwakeClicked),
                           on: state.manualOverride == .forceAwake))
        menu.addItem(check("Allow Sleep Now", #selector(allowSleepClicked),
                           on: state.manualOverride == .forceAllowSleep))

        // Preferences.
        menu.addItem(.separator())
        menu.addItem(check("Only on AC Power", #selector(onACOnlyClicked),
                           on: state.config.onACOnly))
        let grace = NSMenuItem(title: "Grace Period", action: nil, keyEquivalent: "")
        grace.submenu = buildGraceSubmenu(current: state.config.gracePeriodSeconds)
        menu.addItem(grace)

        // Per-agent follow toggles.
        menu.addItem(.separator())
        for agent in AgentKind.allCases {
            let item = check("Follow \(agent.displayName)", #selector(followAgentClicked),
                             on: state.followedAgents.contains(agent))
            item.representedObject = agent
            menu.addItem(item)
        }

        // App settings.
        menu.addItem(.separator())
        menu.addItem(check("Launch at Login", #selector(launchAtLoginClicked),
                           on: state.launchAtLoginEnabled))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Insomnia",
                              action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func buildGraceSubmenu(current: TimeInterval) -> NSMenu {
        let submenu = NSMenu()
        for preset in Self.gracePresets {
            let item = NSMenuItem(title: preset.label,
                                  action: #selector(gracePeriodClicked), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.seconds
            item.state = (abs(current - preset.seconds) < 0.5) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    /// A self-targeted checkable menu item.
    private func check(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private static func sessionLine(_ session: ActiveSession) -> String {
        let dir = session.cwd.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "—"
        let stateText: String
        switch session.displayState {
        case .working:
            stateText = "working"
        case .grace(let seconds):
            stateText = String(format: "grace %d:%02d", seconds / 60, seconds % 60)
        }
        return "\(session.agent.displayName): \(dir)  —  \(stateText)"
    }

    // MARK: - Actions

    @objc private func keepAwakeClicked() {
        let current = state?.manualOverride ?? .none
        delegate?.statusItemDidSetManualOverride(current == .forceAwake ? .none : .forceAwake)
    }

    @objc private func allowSleepClicked() {
        let current = state?.manualOverride ?? .none
        delegate?.statusItemDidSetManualOverride(
            current == .forceAllowSleep ? .none : .forceAllowSleep)
    }

    @objc private func onACOnlyClicked() {
        delegate?.statusItemDidSetOnACOnly(!(state?.config.onACOnly ?? false))
    }

    @objc private func gracePeriodClicked(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? TimeInterval {
            delegate?.statusItemDidSetGracePeriod(seconds)
        }
    }

    @objc private func followAgentClicked(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? AgentKind else { return }
        let followed = state?.followedAgents.contains(agent) ?? false
        delegate?.statusItemDidToggleAgent(agent, followed: !followed)
    }

    @objc private func launchAtLoginClicked() {
        delegate?.statusItemDidToggleLaunchAtLogin(!(state?.launchAtLoginEnabled ?? false))
    }

    @objc private func quitClicked() {
        delegate?.statusItemDidRequestQuit()
    }
}
