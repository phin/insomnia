import Foundation

/// Installs Insomnia's hooks into Gemini CLI's `~/.gemini/settings.json`.
///
/// Same JSON nesting as Claude Code, with two differences: lifecycle events
/// don't take a `matcher`, and `timeout` is in **milliseconds**. Gemini runs
/// hooks synchronously inside its agent loop, so `insomnia-hook` must return
/// immediately (it does — one atomic file write).
public struct GeminiInstaller: AgentInstaller {
    public let agent: AgentKind = .geminiCLI
    public let configFile: URL
    private let store: JSONSettingsStore
    private let merger: JSONHookMerger

    public init(configFile: URL = Paths.geminiSettingsFile) {
        self.configFile = configFile
        self.store = JSONSettingsStore(url: configFile)
        self.merger = JSONHookMerger(
            agent: .geminiCLI,
            eventMap: [
                ("SessionStart", .sessionStart),
                ("BeforeAgent",  .working),
                ("AfterAgent",   .idle),
                ("SessionEnd",   .sessionEnd),
            ],
            matcher: nil,
            timeout: 5000)
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
