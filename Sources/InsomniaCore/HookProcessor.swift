import Foundation

/// The fields Insomnia needs out of an agent hook's stdin JSON. All three
/// supported CLIs (Claude Code, Codex, Gemini CLI) use these exact key names.
public struct HookPayload: Sendable {
    public let sessionId: String?
    public let cwd: String?

    public init(sessionId: String?, cwd: String?) {
        self.sessionId = sessionId
        self.cwd = cwd
    }

    /// Parse from raw stdin bytes. Invalid or non-object JSON yields all-nil —
    /// never throws, so a malformed payload can never disrupt the calling agent.
    public init(jsonData: Data) {
        guard !jsonData.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            self.init(sessionId: nil, cwd: nil)
            return
        }
        self.init(sessionId: obj["session_id"] as? String,
                  cwd: obj["cwd"] as? String)
    }
}

/// Applies a normalized `SemanticEvent` to the on-disk session state.
public struct HookProcessor {
    private let store: SessionStore

    public init(store: SessionStore = SessionStore()) {
        self.store = store
    }

    /// Apply a semantic event for one agent session.
    ///
    /// - `working` / `idle` / `sessionStart` upsert the session file (creating
    ///   it if needed) and refresh `updatedAt`; `pid` and `cwd` are only
    ///   overwritten when supplied, so later events don't erase earlier data.
    /// - `sessionEnd` deletes the session file.
    public func apply(agent: AgentKind,
                      event: SemanticEvent,
                      sessionId: String,
                      cwd: String?,
                      pid: Int32?,
                      now: TimeInterval = Date().timeIntervalSince1970) throws {
        switch event {
        case .sessionEnd:
            store.delete(forKey: SessionState.storeKey(agent: agent, sessionId: sessionId))

        case .working, .idle, .sessionStart:
            let newState: SessionActivityState = (event == .working) ? .working : .idle
            try store.upsert(agent: agent, sessionId: sessionId) { s in
                s.state = newState
                s.updatedAt = now
                if let cwd { s.cwd = cwd }
                if let pid { s.pid = pid }
            }
        }
    }
}
