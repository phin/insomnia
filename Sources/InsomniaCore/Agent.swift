import Foundation

/// An AI coding assistant whose activity Insomnia can follow.
///
/// Each agent reports session activity through its own mechanism (Claude Code
/// hooks, Codex `[hooks]`, Gemini CLI hooks); `insomnia-hook` normalizes all of
/// them into `SessionState` files on disk.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex      = "codex"
    case geminiCLI  = "gemini-cli"

    /// Human-readable name shown in the menu bar UI.
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .geminiCLI:  return "Gemini CLI"
        }
    }
}
