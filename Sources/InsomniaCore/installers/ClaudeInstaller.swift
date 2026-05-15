import Foundation

/// Installs Insomnia's hooks into Claude Code's `~/.claude/settings.json`.
///
/// Claude Code uses the "direct" hook format: a top-level `hooks` object whose
/// keys are event names. The merge preserves every other key in the file
/// (`enabledPlugins`, `permissions`, …) — only `hooks` is touched.
public struct ClaudeInstaller: AgentInstaller {
    public let agent: AgentKind = .claudeCode
    public let configFile: URL
    private let store: JSONSettingsStore
    private let merger: JSONHookMerger

    public init(configFile: URL = Paths.claudeSettingsFile) {
        self.configFile = configFile
        self.store = JSONSettingsStore(url: configFile)
        self.merger = JSONHookMerger(
            agent: .claudeCode,
            eventMap: [
                ("SessionStart",     .sessionStart),
                ("UserPromptSubmit", .working),
                ("Stop",             .idle),
                ("Notification",     .idle),
                ("SessionEnd",       .sessionEnd),
            ],
            matcher: "*",
            timeout: 5)
    }

    public func install(hookBinaryPath: String) throws {
        var root = try store.loadOrEmpty()
        try merger.merge(into: &root, hookBinaryPath: hookBinaryPath)
        try InstallerSupport.backupIfNeeded(configFile)
        try store.write(root)
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        var root = try store.loadOrEmpty()
        if try merger.remove(from: &root) {
            try InstallerSupport.backupIfNeeded(configFile)
            try store.write(root)
        }
    }

    public func status(expectedHookBinaryPath: String?) -> IntegrationStatus {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return .configMissing
        }
        do {
            return merger.status(in: try store.loadOrEmpty(),
                                 expectedHookBinaryPath: expectedHookBinaryPath)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
