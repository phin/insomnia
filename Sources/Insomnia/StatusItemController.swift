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
    func statusItemDidRequestSettings()
    func statusItemDidRequestQuit()
}

/// Owns the `NSStatusItem` (menu bar icon) and rebuilds its menu from a
/// `MenuState`. Pure presentation — it holds no policy, just forwards clicks.
final class StatusItemController: NSObject {
    weak var delegate: StatusItemControllerDelegate?

    private var statusItem: NSStatusItem?
    private var state: MenuState?

    /// Create the menu bar item. Call once, after the app finishes launching.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.apply(awake: false, to: item.button)
        statusItem = item
    }

    /// Update the icon and rebuild the menu from the latest state.
    func render(_ state: MenuState) {
        self.state = state
        Self.apply(awake: state.decision.shouldKeepAwake, to: statusItem?.button)
        statusItem?.menu = buildMenu(state)
    }

    // MARK: - Icon

    private static func apply(awake: Bool, to button: NSStatusBarButton?) {
        guard let button else { return }
        // Literal "zzZ" text glyph. Heavy weight while we're holding an awake
        // assertion so the icon "thickens" on duty; regular when idle.
        let weight: NSFont.Weight = awake ? .heavy : .regular
        button.image = nil
        button.attributedTitle = NSAttributedString(
            string: "zzZ",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: weight)])
        button.setAccessibilityLabel(awake ? "Keeping Mac awake" : "Idle")
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
            for session in decision.activeSessions {
                let item = NSMenuItem(title: "  " + Self.sessionLine(session),
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(check("Keep Awake Anyway", #selector(keepAwakeClicked),
                           on: state.manualOverride == .forceAwake))

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(settingsClicked),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Insomnia",
                              action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
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

    @objc private func settingsClicked() {
        delegate?.statusItemDidRequestSettings()
    }

    @objc private func quitClicked() {
        delegate?.statusItemDidRequestQuit()
    }
}
