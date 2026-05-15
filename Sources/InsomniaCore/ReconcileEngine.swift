import Foundation

/// A manual override the user can set from the menu bar, taking precedence
/// over agent activity.
public enum ManualOverride: String, Codable, Sendable {
    /// No override — follow agent activity.
    case none
    /// Keep the Mac awake unconditionally.
    case forceAwake
    /// Allow the Mac to sleep even while an agent is working.
    case forceAllowSleep
}

/// One session that currently justifies keeping the Mac awake, for display in
/// the menu.
public struct ActiveSession: Equatable, Sendable {
    public enum DisplayState: Equatable, Sendable {
        case working
        case grace(secondsRemaining: Int)
    }
    public let agent: AgentKind
    public let sessionId: String
    public let cwd: String?
    public let displayState: DisplayState

    public init(agent: AgentKind, sessionId: String, cwd: String?, displayState: DisplayState) {
        self.agent = agent
        self.sessionId = sessionId
        self.cwd = cwd
        self.displayState = displayState
    }
}

/// The outcome of one reconcile pass.
public struct ReconcileDecision: Equatable, Sendable {
    /// Whether the power assertion should be held.
    public let shouldKeepAwake: Bool
    /// Human-readable reason string (shows in `pmset -g assertions`).
    public let reason: String
    /// Sessions keeping the Mac awake (working or in grace), for the menu.
    public let activeSessions: [ActiveSession]
    /// Session files the caller should delete (dead, expired, or over the cap).
    public let filesToDelete: [URL]

    public init(shouldKeepAwake: Bool,
                reason: String,
                activeSessions: [ActiveSession],
                filesToDelete: [URL]) {
        self.shouldKeepAwake = shouldKeepAwake
        self.reason = reason
        self.activeSessions = activeSessions
        self.filesToDelete = filesToDelete
    }
}

/// The pure decision function at the heart of Insomnia: given the current set
/// of session files, user config, manual override, and power state, decide
/// whether to hold the sleep assertion and which stale files to reap.
///
/// No side effects — the caller performs the IOKit and filesystem actions.
public enum ReconcileEngine {

    /// `kill(pid, 0)` liveness check: 0 → exists; `EPERM` → exists but owned by
    /// another user; `ESRCH` → gone.
    public static func defaultIsProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public static func reconcile(
        sessions: [LoadedSession],
        config: Config,
        followedAgents: Set<AgentKind>,
        manualOverride: ManualOverride,
        onACPower: Bool,
        now: TimeInterval = Date().timeIntervalSince1970,
        isProcessAlive: (Int32) -> Bool = ReconcileEngine.defaultIsProcessAlive
    ) -> ReconcileDecision {
        var active: [ActiveSession] = []
        var filesToDelete: [URL] = []
        var workingCount = 0
        var graceCount = 0

        for loaded in sessions {
            let s = loaded.state
            let age = now - s.updatedAt

            // Sessions from agents the user isn't following don't count, but
            // their files are still tidied up once sufficiently stale.
            guard followedAgents.contains(s.agent) else {
                if age > config.idleReapSeconds { filesToDelete.append(loaded.url) }
                continue
            }

            // Absolute backstop: a session older than the cap is reaped no
            // matter its state (handles a CLI that died without an end event).
            if age > config.absoluteSafetyCapSeconds {
                filesToDelete.append(loaded.url)
                continue
            }

            switch s.state {
            case .working:
                if let pid = s.pid, !isProcessAlive(pid) {
                    filesToDelete.append(loaded.url)   // process is gone
                } else {
                    active.append(ActiveSession(agent: s.agent, sessionId: s.sessionId,
                                                cwd: s.cwd, displayState: .working))
                    workingCount += 1
                }

            case .idle:
                let graceDeadline = s.updatedAt + config.gracePeriodSeconds
                if now < graceDeadline {
                    let remaining = max(0, Int((graceDeadline - now).rounded(.up)))
                    active.append(ActiveSession(
                        agent: s.agent, sessionId: s.sessionId, cwd: s.cwd,
                        displayState: .grace(secondsRemaining: remaining)))
                    graceCount += 1
                } else if age > config.idleReapSeconds {
                    filesToDelete.append(loaded.url)
                }
                // else: idle, past grace, not yet reapable — keep the file
                // around (the session may resume) but don't keep the Mac awake.
            }
        }

        let activityWantsAwake = !active.isEmpty
        let shouldKeepAwake: Bool
        switch manualOverride {
        case .forceAllowSleep:
            shouldKeepAwake = false
        case .forceAwake:
            shouldKeepAwake = true
        case .none:
            if config.onACOnly && !onACPower {
                shouldKeepAwake = false
            } else {
                shouldKeepAwake = activityWantsAwake
            }
        }

        let reason = reasonString(manualOverride: manualOverride,
                                  shouldKeepAwake: shouldKeepAwake,
                                  workingCount: workingCount,
                                  graceCount: graceCount,
                                  active: active)

        return ReconcileDecision(shouldKeepAwake: shouldKeepAwake,
                                 reason: reason,
                                 activeSessions: active,
                                 filesToDelete: filesToDelete)
    }

    private static func reasonString(manualOverride: ManualOverride,
                                     shouldKeepAwake: Bool,
                                     workingCount: Int,
                                     graceCount: Int,
                                     active: [ActiveSession]) -> String {
        if manualOverride == .forceAwake {
            return "Insomnia: manual override (keep awake)"
        }
        if !shouldKeepAwake {
            return "Insomnia: idle"
        }
        if workingCount > 0 {
            let names = Set(active.filter { $0.displayState == .working }
                .map { $0.agent.displayName }).sorted().joined(separator: ", ")
            let noun = workingCount == 1 ? "session" : "sessions"
            return "Insomnia: \(names) working (\(workingCount) \(noun))"
        }
        let noun = graceCount == 1 ? "session" : "sessions"
        return "Insomnia: grace period (\(graceCount) \(noun))"
    }
}
