import Foundation

/// The normalized event vocabulary Insomnia understands, independent of any
/// particular agent CLI. Each agent's installer maps that CLI's native hook
/// events onto these four, so `insomnia-hook` itself stays agent-agnostic.
public enum SemanticEvent: String, Sendable, CaseIterable {
    /// The agent started (or resumed) actively working a turn.
    case working
    /// The agent finished a turn and is now waiting/idle — grace period begins.
    case idle
    /// A session began; register it (idempotent) in the idle state.
    case sessionStart = "session-start"
    /// A session ended; remove its state file.
    case sessionEnd = "session-end"
}
