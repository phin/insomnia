import Foundation

/// Canonical filesystem locations used across Insomnia.
///
/// Every location can be redirected with an environment variable, which keeps
/// the app and `insomnia-hook` honest under test (`scripts/test-hook.sh`, the
/// unit tests, and end-to-end checks) without ever touching real configs.
public enum Paths {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/Library/Application Support/Insomnia/`
    public static var appSupportDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Insomnia", isDirectory: true)
    }

    /// `~/Library/Application Support/Insomnia/sessions/` — one JSON file per
    /// active session. Override: `INSOMNIA_SESSIONS_DIR`.
    public static var sessionsDir: URL {
        overridable("INSOMNIA_SESSIONS_DIR",
                    default: appSupportDir.appendingPathComponent("sessions", isDirectory: true))
    }

    /// `~/Library/Application Support/Insomnia/config.json`
    public static var configFile: URL {
        appSupportDir.appendingPathComponent("config.json", isDirectory: false)
    }

    // MARK: - Per-agent config locations

    /// Claude Code settings. Override: `INSOMNIA_CLAUDE_SETTINGS`.
    public static var claudeSettingsFile: URL {
        overridable("INSOMNIA_CLAUDE_SETTINGS",
                    default: home.appendingPathComponent(".claude/settings.json"))
    }

    /// Codex CLI config. Override: `INSOMNIA_CODEX_CONFIG`.
    public static var codexConfigFile: URL {
        overridable("INSOMNIA_CODEX_CONFIG",
                    default: home.appendingPathComponent(".codex/config.toml"))
    }

    /// Gemini CLI settings. Override: `INSOMNIA_GEMINI_SETTINGS`.
    public static var geminiSettingsFile: URL {
        overridable("INSOMNIA_GEMINI_SETTINGS",
                    default: home.appendingPathComponent(".gemini/settings.json"))
    }

    /// Create the Application Support directory tree (including `sessions/`) if needed.
    public static func ensureAppSupportDir() throws {
        try FileManager.default.createDirectory(
            at: sessionsDir, withIntermediateDirectories: true)
    }

    /// Returns the path named by `envKey`, or `defaultURL` if it's unset/empty.
    private static func overridable(_ envKey: String,
                                    default defaultURL: @autoclosure () -> URL) -> URL {
        if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return defaultURL()
    }
}
