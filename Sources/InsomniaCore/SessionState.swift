import Foundation

/// Whether an agent session is actively working or waiting/idle.
public enum SessionActivityState: String, Codable, Sendable {
    case working
    case idle
}

/// One JSON file on disk per active agent session, written by `insomnia-hook`
/// and consumed by the menu bar app.
public struct SessionState: Codable, Equatable, Sendable {
    public var version: Int
    public var agent: AgentKind
    /// Session identifier as reported by the agent CLI. Unique per agent;
    /// combined with `agent` it is globally unique (see `storeKey`).
    public var sessionId: String
    /// Best-effort PID of the agent process. Advisory only — may be nil or stale.
    public var pid: Int32?
    /// Working directory of the session, for display.
    public var cwd: String?
    public var state: SessionActivityState
    /// Epoch seconds of the most recent activity event for this session.
    public var updatedAt: TimeInterval

    public static let currentVersion = 1

    public init(agent: AgentKind,
                sessionId: String,
                pid: Int32? = nil,
                cwd: String? = nil,
                state: SessionActivityState,
                updatedAt: TimeInterval,
                version: Int = SessionState.currentVersion) {
        self.version = version
        self.agent = agent
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.state = state
        self.updatedAt = updatedAt
    }

    /// Filesystem-safe key, globally unique across agents, used as the state
    /// file name. Non-alphanumeric characters are collapsed to `_`.
    public static func storeKey(agent: AgentKind, sessionId: String) -> String {
        let raw = "\(agent.rawValue)-\(sessionId)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    public var storeKey: String {
        Self.storeKey(agent: agent, sessionId: sessionId)
    }
}
