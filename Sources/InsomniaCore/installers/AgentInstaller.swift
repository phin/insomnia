import Foundation

/// Result of inspecting an agent's config for Insomnia's integration.
public enum IntegrationStatus: Equatable, Sendable {
    /// Our hooks are present and point at the expected `insomnia-hook` binary.
    case installed
    /// Our hooks are present but point at a different path (app moved/upgraded).
    case stale
    /// The config exists but contains none of our hooks.
    case notInstalled
    /// The agent's config file/directory does not exist.
    case configMissing
    /// The config could not be parsed or has an unexpected shape.
    case error(String)

    public var summary: String {
        switch self {
        case .installed:     return "installed"
        case .stale:         return "installed (stale path — re-run install)"
        case .notInstalled:  return "not installed"
        case .configMissing: return "agent not detected"
        case .error(let m):  return "error: \(m)"
        }
    }
}

public enum InstallerError: Error, LocalizedError {
    case unexpectedShape(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedShape(let m): return m
        }
    }
}

/// Installs / removes Insomnia's hook integration for one agent CLI.
public protocol AgentInstaller {
    var agent: AgentKind { get }
    /// The config file this installer reads and writes.
    var configFile: URL { get }
    /// Whether the agent appears to be set up on this machine (its config
    /// directory exists).
    var isAgentPresent: Bool { get }

    /// Install or refresh the integration, pointing hooks at `hookBinaryPath`.
    /// Idempotent: running it twice leaves the config in the same state.
    func install(hookBinaryPath: String) throws
    /// Remove only Insomnia's entries, leaving the rest of the config intact.
    func uninstall() throws
    /// Inspect the config without modifying it.
    func status(expectedHookBinaryPath: String?) -> IntegrationStatus
}

public extension AgentInstaller {
    var isAgentPresent: Bool {
        FileManager.default.fileExists(atPath: configFile.deletingLastPathComponent().path)
    }
}

/// Entry point for picking the right installer for an agent.
public enum AgentIntegration {
    public static func installer(for agent: AgentKind) -> AgentInstaller {
        switch agent {
        case .claudeCode: return ClaudeInstaller()
        case .codex:      return CodexInstaller()
        case .geminiCLI:  return GeminiInstaller()
        }
    }

    /// Best-effort absolute path to the `insomnia-hook` binary to wire hooks to.
    ///
    /// - When the running executable *is* `insomnia-hook` (the CLI), use it.
    /// - When it's the menu bar app, `insomnia-hook` sits beside it in the
    ///   bundle's `Contents/MacOS/`.
    public static func defaultHookBinaryPath() -> String {
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            if exe.lastPathComponent == "insomnia-hook" { return exe.path }
            let sibling = exe.deletingLastPathComponent()
                .appendingPathComponent("insomnia-hook")
            if FileManager.default.isExecutableFile(atPath: sibling.path) {
                return sibling.path
            }
            return exe.path
        }
        return CommandLine.arguments.first ?? "insomnia-hook"
    }
}

/// Shared filesystem helpers for the installers.
enum InstallerSupport {
    /// Back up `url` to `<url>.insomnia.bak`, but only if no backup exists yet,
    /// so the very first (pre-Insomnia) state is preserved. No-op if `url`
    /// doesn't exist.
    static func backupIfNeeded(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let backup = url.appendingPathExtension("insomnia.bak")
        guard !fm.fileExists(atPath: backup.path) else { return }
        try fm.copyItem(at: url, to: backup)
    }

    /// Write `data` to `url` via a temp file + `rename()`, creating parent
    /// directories as needed.
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
        try data.write(to: tmp, options: [])
        if rename(tmp.path, url.path) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: tmp)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey:
                            "rename failed: \(String(cString: strerror(code)))"])
        }
    }

    /// Single-quote a path for safe embedding in a shell-executed hook command.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The full command string an agent's hook should run.
    static func hookCommand(binaryPath: String,
                            agent: AgentKind,
                            event: SemanticEvent) -> String {
        "\(shellQuote(binaryPath)) \(agent.rawValue) \(event.rawValue)"
    }

    /// Whether a hook command string is one of Insomnia's.
    static func isInsomniaCommand(_ command: String) -> Bool {
        command.contains("insomnia-hook")
    }
}
