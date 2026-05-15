import AppKit
import InsomniaCore

/// Settings/onboarding window. A single page with two modes:
/// - `.onboarding`: shown on first launch with a welcome header.
/// - `.settings`:    shown from the menu bar's "Settings…" item.
///
/// All toggles route through `SettingsWindowDelegate`; the controller refreshes
/// its checkbox/popup state from `refresh(state:)` after every change so the
/// UI always reflects ground truth (e.g. installer status, login-item state).
protocol SettingsWindowDelegate: AnyObject {
    func settingsDidSetGracePeriod(_ seconds: TimeInterval)
    func settingsDidSetOnACOnly(_ enabled: Bool)
    func settingsDidToggleAgent(_ agent: AgentKind, followed: Bool)
    func settingsDidToggleLaunchAtLogin(_ enabled: Bool)
    func settingsDidSetPreventLidClosedSleep(_ enabled: Bool)
}

/// What the window needs to render itself. Mirrors the relevant fields of
/// `MenuState` plus per-agent presence info for the onboarding view.
struct SettingsState {
    let followedAgents: Set<AgentKind>
    /// Agents whose CLI is detected on this machine. Followed agents are
    /// always considered "present" even if the binary check would say no.
    let presentAgents: Set<AgentKind>
    let gracePeriodSeconds: TimeInterval
    let onACOnly: Bool
    let launchAtLoginEnabled: Bool
    /// System-wide `pmset -a disablesleep` flag. Read from `pmset -g`, not
    /// from any app-side preference, so it stays in sync if the user flips
    /// it from the terminal.
    let preventLidClosedSleep: Bool
    /// Most recent reconcile decision — drives the Status section. `nil`
    /// only before the first reconcile has run.
    let currentDecision: ReconcileDecision?
}

final class SettingsWindowController: NSWindowController {
    enum Mode { case onboarding, settings }

    weak var delegate: SettingsWindowDelegate?

    private let mode: Mode
    private var state: SettingsState

    private var agentCheckboxes: [AgentKind: NSButton] = [:]
    private var graceMenu: NSPopUpButton!
    private var onACCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var preventLidSleepCheckbox: NSButton!
    private var statusHeadline: NSTextField?
    private var statusSessionsStack: NSStackView?

    private static let gracePresets: [(label: String, seconds: TimeInterval)] = [
        ("1 minute", 60), ("5 minutes", 300), ("10 minutes", 600),
        ("15 minutes", 900), ("30 minutes", 1800),
    ]

    /// Fixed content width — wide enough for the longest row ("Stay awake for
    /// [10 minutes] after a turn ends") with breathing room. Height auto-fits
    /// the stack via Auto Layout.
    private static let contentWidth: CGFloat = 540

    init(mode: Mode, state: SettingsState, delegate: SettingsWindowDelegate) {
        self.mode = mode
        self.state = state
        self.delegate = delegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = mode == .onboarding ? "Welcome to Insomnia" : "Insomnia Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        let content = buildContentView()
        window.contentView = content
        content.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        window.layoutIfNeeded()
        let fittingHeight = content.fittingSize.height
        window.setContentSize(NSSize(width: Self.contentWidth, height: fittingHeight))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Update checkbox/popup state from the latest `SettingsState`. Safe to
    /// call on every reconcile — it just re-syncs control values.
    func refresh(state: SettingsState) {
        self.state = state
        for (agent, checkbox) in agentCheckboxes {
            checkbox.state = state.followedAgents.contains(agent) ? .on : .off
        }
        if let idx = Self.gracePresets.firstIndex(where: {
            abs($0.seconds - state.gracePeriodSeconds) < 0.5
        }) {
            graceMenu.selectItem(at: idx)
        }
        onACCheckbox.state = state.onACOnly ? .on : .off
        launchAtLoginCheckbox.state = state.launchAtLoginEnabled ? .on : .off
        preventLidSleepCheckbox.state = state.preventLidClosedSleep ? .on : .off
        renderStatus(from: state.currentDecision)
    }

    private func renderStatus(from decision: ReconcileDecision?) {
        guard let statusHeadline, let statusSessionsStack else { return }
        let awake = decision?.shouldKeepAwake ?? false
        statusHeadline.stringValue = awake ? "Keeping Mac awake" : "Idle — Mac can sleep"
        statusHeadline.textColor = awake ? .systemGreen : .secondaryLabelColor

        for view in statusSessionsStack.arrangedSubviews {
            statusSessionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let sessions = decision?.activeSessions ?? []
        statusSessionsStack.isHidden = sessions.isEmpty
        for session in sessions {
            let label = NSTextField(labelWithString: Self.sessionLine(session))
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            statusSessionsStack.addArrangedSubview(label)
        }
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
        return "  \(session.agent.displayName) · \(dir) · \(stateText)"
    }

    /// Bring the window to the front. Must be called on the main thread.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Onboarding header (settings mode relies on the window title).
        if mode == .onboarding {
            let title = NSTextField(labelWithString: "Welcome to Insomnia")
            title.font = .systemFont(ofSize: 18, weight: .semibold)
            root.addArrangedSubview(title)

            let blurb = NSTextField(wrappingLabelWithString:
                "Insomnia keeps your Mac awake while an AI coding agent is working, "
                + "so long tasks aren't cut off by idle sleep. Pick which agents to "
                + "follow — you can change this anytime.")
            blurb.font = .systemFont(ofSize: 12)
            blurb.textColor = .secondaryLabelColor
            blurb.preferredMaxLayoutWidth = Self.contentWidth - 48
            root.addArrangedSubview(blurb)
        } else {
            // Status section — current decision + active sessions. Live-updates
            // on every reconcile via `refresh(state:)`.
            root.addArrangedSubview(sectionHeader("Status"))
            let headline = NSTextField(labelWithString: "Idle — Mac can sleep")
            headline.font = .systemFont(ofSize: 13, weight: .medium)
            self.statusHeadline = headline
            root.addArrangedSubview(headline)

            let sessions = NSStackView()
            sessions.orientation = .vertical
            sessions.alignment = .leading
            sessions.spacing = 2
            sessions.isHidden = true
            self.statusSessionsStack = sessions
            root.addArrangedSubview(sessions)
        }

        // Agents section
        root.addArrangedSubview(sectionHeader("Follow agents"))
        for agent in AgentKind.allCases {
            root.addArrangedSubview(makeAgentCheckbox(agent))
        }

        // Behavior section
        root.addArrangedSubview(sectionHeader("Behavior"))
        root.addArrangedSubview(makeGraceRow())
        onACCheckbox = makeCheckbox(
            title: "Only keep awake on AC power",
            action: #selector(onACOnlyToggled),
            on: state.onACOnly)
        root.addArrangedSubview(onACCheckbox)
        launchAtLoginCheckbox = makeCheckbox(
            title: "Launch at login",
            action: #selector(launchAtLoginToggled),
            on: state.launchAtLoginEnabled)
        root.addArrangedSubview(launchAtLoginCheckbox)

        // Closed-lid section — its own block so the caveats are visible
        // in onboarding too, not buried under "Behavior".
        root.addArrangedSubview(sectionHeader("Closed-lid operation"))
        let lidBlurb = NSTextField(wrappingLabelWithString:
            "Insomnia's idle-sleep assertion doesn't override clamshell sleep "
            + "on its own. Enabling this sets the system-wide `pmset -a "
            + "disablesleep 1` flag (asks for your admin password once) so your "
            + "Mac stays awake on AC with the lid shut. It's a persistent macOS "
            + "setting — uncheck here to revert.")
        lidBlurb.font = .systemFont(ofSize: 12)
        lidBlurb.textColor = .secondaryLabelColor
        lidBlurb.preferredMaxLayoutWidth = Self.contentWidth - 48
        root.addArrangedSubview(lidBlurb)
        preventLidSleepCheckbox = makeCheckbox(
            title: "Prevent sleep when the lid is closed",
            action: #selector(preventLidSleepToggled),
            on: state.preventLidClosedSleep)
        root.addArrangedSubview(preventLidSleepCheckbox)

        // How it works
        root.addArrangedSubview(sectionHeader("How it works"))
        let how = NSTextField(wrappingLabelWithString:
            "Each followed agent runs a small hook on session events that tells "
            + "Insomnia when it's working. While at least one agent is active, "
            + "Insomnia holds a system idle-sleep assertion so your task can run "
            + "to completion. After the turn ends, it waits the grace period "
            + "above, then lets the Mac sleep normally.\n\n"
            + "The display is still allowed to sleep — you can close your eyes "
            + "and go to bed while the work continues. Closing the laptop lid "
            + "still sleeps the Mac (no app can override clamshell sleep).")
        how.font = .systemFont(ofSize: 12)
        how.textColor = .secondaryLabelColor
        how.preferredMaxLayoutWidth = Self.contentWidth - 48
        root.addArrangedSubview(how)

        // Author follow link
        let follow = NSButton(
            title: "Follow @nsphin on X",
            target: self, action: #selector(followAuthorClicked))
        follow.bezelStyle = .inline
        follow.controlSize = .small
        root.addArrangedSubview(follow)

        // Footer
        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.keyEquivalent = "\r"
        done.bezelStyle = .rounded
        let footerRow = NSStackView(views: [NSView(), done])
        footerRow.orientation = .horizontal
        footerRow.distribution = .fill
        footerRow.spacing = 8
        root.addArrangedSubview(footerRow)
        footerRow.widthAnchor.constraint(equalTo: root.widthAnchor,
                                         constant: -48).isActive = true

        return root
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func makeAgentCheckbox(_ agent: AgentKind) -> NSView {
        let isPresent = state.presentAgents.contains(agent) ||
                        state.followedAgents.contains(agent)
        let suffix = isPresent ? "" : "  (not detected)"
        let checkbox = NSButton(
            checkboxWithTitle: "\(agent.displayName)\(suffix)",
            target: self, action: #selector(agentToggled(_:)))
        checkbox.state = state.followedAgents.contains(agent) ? .on : .off
        checkbox.tag = AgentKind.allCases.firstIndex(of: agent) ?? 0
        agentCheckboxes[agent] = checkbox
        return checkbox
    }

    private func makeGraceRow() -> NSView {
        let label = NSTextField(labelWithString: "Stay awake for")
        label.font = .systemFont(ofSize: 13)

        graceMenu = NSPopUpButton()
        for preset in Self.gracePresets { graceMenu.addItem(withTitle: preset.label) }
        if let idx = Self.gracePresets.firstIndex(where: {
            abs($0.seconds - state.gracePeriodSeconds) < 0.5
        }) {
            graceMenu.selectItem(at: idx)
        }
        graceMenu.target = self
        graceMenu.action = #selector(graceChanged(_:))

        let trailing = NSTextField(labelWithString: "after a turn ends")
        trailing.font = .systemFont(ofSize: 13)
        trailing.textColor = .secondaryLabelColor

        let row = NSStackView(views: [label, graceMenu, trailing])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeCheckbox(title: String, action: Selector, on: Bool) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        b.state = on ? .on : .off
        return b
    }

    // MARK: - Actions

    @objc private func agentToggled(_ sender: NSButton) {
        let agent = AgentKind.allCases[sender.tag]
        delegate?.settingsDidToggleAgent(agent, followed: sender.state == .on)
    }

    @objc private func graceChanged(_ sender: NSPopUpButton) {
        let seconds = Self.gracePresets[sender.indexOfSelectedItem].seconds
        delegate?.settingsDidSetGracePeriod(seconds)
    }

    @objc private func onACOnlyToggled(_ sender: NSButton) {
        delegate?.settingsDidSetOnACOnly(sender.state == .on)
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        delegate?.settingsDidToggleLaunchAtLogin(sender.state == .on)
    }

    @objc private func preventLidSleepToggled(_ sender: NSButton) {
        let wantEnable = sender.state == .on
        if wantEnable {
            let alert = NSAlert()
            alert.messageText = "Prevent sleep when the lid is closed?"
            alert.informativeText = """
                This sets the system-wide `pmset -a disablesleep 1` flag — \
                a macOS setting, not an Insomnia assertion. On AC power your \
                Mac will stay awake with the lid shut. On battery it will \
                still sleep.

                This is persistent: it survives reboots and stays on until \
                you uncheck this box (or run `sudo pmset -a disablesleep 0` \
                yourself). macOS will prompt for your admin password.
                """
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn {
                sender.state = .off
                return
            }
        }
        delegate?.settingsDidSetPreventLidClosedSleep(wantEnable)
    }

    @objc private func doneClicked() {
        // Final onboarding step: if the user hasn't enabled closed-lid mode,
        // explicitly offer it before closing. Skipped in settings mode (the
        // checkbox is enough for an existing user).
        if mode == .onboarding, !state.preventLidClosedSleep {
            offerClamshellThenClose()
            return
        }
        window?.close()
    }

    private func offerClamshellThenClose() {
        let alert = NSAlert()
        alert.messageText = "One more thing — prevent sleep when the lid is closed?"
        alert.informativeText = """
            Insomnia's idle-sleep assertion doesn't override clamshell sleep \
            on its own. Enabling this sets the system-wide `pmset -a \
            disablesleep 1` flag — your Mac stays awake on AC power with the \
            lid shut. macOS will ask for your admin password once.

            This is a persistent macOS setting (survives reboots). You can \
            turn it off anytime from Settings.
            """
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Skip")
        if alert.runModal() == .alertFirstButtonReturn {
            preventLidSleepCheckbox.state = .on
            delegate?.settingsDidSetPreventLidClosedSleep(true)
        }
        window?.close()
    }

    @objc private func followAuthorClicked() {
        if let url = URL(string: "https://x.com/nsphin") {
            NSWorkspace.shared.open(url)
        }
    }
}
