import XCTest
@testable import InsomniaCore

final class InstallerTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("insomnia-inst-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func write(_ contents: String, to name: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func loadJSON(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    // MARK: - Claude Code

    func testClaudeInstallPreservesOtherKeysAndAddsHooks() throws {
        let url = try write("""
        {
          "enabledPlugins": { "foo@bar": true },
          "permissions": { "defaultMode": "auto" },
          "effortLevel": "xhigh"
        }
        """, to: "settings.json")

        try ClaudeInstaller(configFile: url).install(hookBinaryPath: "/opt/insomnia-hook")

        let root = try loadJSON(url)
        XCTAssertNotNil(root["enabledPlugins"], "must preserve unrelated keys")
        XCTAssertNotNil(root["permissions"])
        XCTAssertEqual(root["effortLevel"] as? String, "xhigh")

        let hooks = root["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)
        for event in ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "SessionEnd"] {
            let groups = hooks?[event] as? [[String: Any]]
            XCTAssertEqual(groups?.count, 1, "expected one group for \(event)")
            let cmd = ((groups?.first?["hooks"] as? [[String: Any]])?.first?["command"]) as? String
            XCTAssertEqual(groups?.first?["matcher"] as? String, "*")
            XCTAssertTrue(cmd?.contains("insomnia-hook") ?? false)
            XCTAssertTrue(cmd?.contains("claude-code") ?? false)
        }
        // Backup of the pristine file was made.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathExtension("insomnia.bak").path))
    }

    func testClaudeInstallIsIdempotent() throws {
        let url = try write("{}", to: "settings.json")
        let installer = ClaudeInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        let hooks = try loadJSON(url)["hooks"] as? [String: Any]
        XCTAssertEqual((hooks?["Stop"] as? [[String: Any]])?.count, 1,
                       "installing twice must not duplicate entries")
    }

    func testClaudeInstallUpdatesStalePathInPlace() throws {
        let url = try write("{}", to: "settings.json")
        let installer = ClaudeInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/old/insomnia-hook")
        XCTAssertEqual(installer.status(expectedHookBinaryPath: "/new/insomnia-hook"), .stale)
        try installer.install(hookBinaryPath: "/new/insomnia-hook")
        XCTAssertEqual(installer.status(expectedHookBinaryPath: "/new/insomnia-hook"), .installed)
        let hooks = try loadJSON(url)["hooks"] as? [String: Any]
        XCTAssertEqual((hooks?["Stop"] as? [[String: Any]])?.count, 1)
    }

    func testClaudeUninstallRemovesOnlyOurHooks() throws {
        let url = try write("""
        { "permissions": { "defaultMode": "auto" } }
        """, to: "settings.json")
        let installer = ClaudeInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        try installer.uninstall()

        let root = try loadJSON(url)
        XCTAssertNotNil(root["permissions"], "unrelated keys survive uninstall")
        XCTAssertNil(root["hooks"], "our hooks (the only ones) are gone")
        XCTAssertEqual(installer.status(expectedHookBinaryPath: nil), .notInstalled)
    }

    func testClaudeUninstallKeepsUserHooksInSharedEvent() throws {
        // The user has their own Stop hook; ours is added alongside it.
        let url = try write("""
        {
          "hooks": {
            "Stop": [
              { "hooks": [ { "type": "command", "command": "/usr/bin/say done" } ] }
            ]
          }
        }
        """, to: "settings.json")
        let installer = ClaudeInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        try installer.uninstall()

        let stop = (try loadJSON(url)["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1, "user's own Stop hook must remain")
        let cmd = (stop?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        XCTAssertEqual(cmd, "/usr/bin/say done")
    }

    func testClaudeStatusConfigMissing() {
        let url = tmpDir.appendingPathComponent("does-not-exist.json")
        XCTAssertEqual(ClaudeInstaller(configFile: url).status(expectedHookBinaryPath: nil),
                       .configMissing)
    }

    // MARK: - Gemini CLI

    func testGeminiInstallCreatesFileWithMillisecondTimeoutAndNoMatcher() throws {
        let url = tmpDir.appendingPathComponent("gemini-settings.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try GeminiInstaller(configFile: url).install(hookBinaryPath: "/opt/insomnia-hook")

        let hooks = try loadJSON(url)["hooks"] as? [String: Any]
        for event in ["SessionStart", "BeforeAgent", "AfterAgent", "SessionEnd"] {
            let group = (hooks?[event] as? [[String: Any]])?.first
            XCTAssertNotNil(group, "expected \(event) group")
            XCTAssertNil(group?["matcher"], "Gemini lifecycle hooks take no matcher")
            let entry = (group?["hooks"] as? [[String: Any]])?.first
            XCTAssertEqual(entry?["timeout"] as? Int, 5000, "Gemini timeout is in ms")
            XCTAssertTrue((entry?["command"] as? String)?.contains("gemini-cli") ?? false)
        }
    }

    func testGeminiRoundTripInstallUninstall() throws {
        let url = try write("{ \"theme\": \"dark\" }", to: "gemini-settings.json")
        let installer = GeminiInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        XCTAssertEqual(installer.status(expectedHookBinaryPath: "/opt/insomnia-hook"), .installed)
        try installer.uninstall()
        let root = try loadJSON(url)
        XCTAssertEqual(root["theme"] as? String, "dark")
        XCTAssertNil(root["hooks"])
    }

    // MARK: - Codex CLI

    func testCodexInstallAddsBlockAndFlagPreservingUserContent() throws {
        let url = try write("""
        model = "gpt-5.5"

        [features]
        some_other_flag = true

        [mcp_servers.example]
        command = "foo"
        """, to: "config.toml")

        try CodexInstaller(configFile: url).install(hookBinaryPath: "/opt/insomnia-hook")
        let result = try text(url)

        // User content untouched.
        XCTAssertTrue(result.contains(#"model = "gpt-5.5""#))
        XCTAssertTrue(result.contains("some_other_flag = true"))
        XCTAssertTrue(result.contains("[mcp_servers.example]"))
        // Our additions.
        XCTAssertTrue(result.contains("codex_hooks = true  # managed by insomnia"))
        XCTAssertTrue(result.contains("[[hooks.UserPromptSubmit]]"))
        XCTAssertTrue(result.contains("[[hooks.UserPromptSubmit.hooks]]"))
        XCTAssertTrue(result.contains("codex working"))
        XCTAssertTrue(result.contains("codex session-start"))
        XCTAssertTrue(result.contains("codex idle"))
        // Flag was inserted into the existing [features] table, not a new one.
        XCTAssertEqual(occurrences(of: "[features]", in: result), 1)
    }

    func testCodexInstallIsIdempotent() throws {
        let url = try write("model = \"gpt-5.5\"\n", to: "config.toml")
        let installer = CodexInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        let result = try text(url)
        XCTAssertEqual(occurrences(of: "# >>> insomnia", in: result), 1,
                       "only one managed block after installing twice")
        XCTAssertEqual(occurrences(of: "codex_hooks", in: result), 1,
                       "only one feature-flag line after installing twice")
        XCTAssertTrue(result.contains("[features]"),
                      "a [features] table is appended when none existed")
    }

    func testCodexLeavesUserSetFeatureFlagAlone() throws {
        let url = try write("""
        [features]
        codex_hooks = true
        """, to: "config.toml")
        try CodexInstaller(configFile: url).install(hookBinaryPath: "/opt/insomnia-hook")
        let result = try text(url)
        XCTAssertEqual(occurrences(of: "codex_hooks", in: result), 1)
        XCTAssertFalse(result.contains("# managed by insomnia"),
                       "must not touch a flag the user already set")
    }

    func testCodexUninstallRemovesBlockAndManagedFlagOnly() throws {
        let url = try write("""
        model = "gpt-5.5"

        [features]
        some_other_flag = true
        """, to: "config.toml")
        let installer = CodexInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/opt/insomnia-hook")
        try installer.uninstall()
        let result = try text(url)

        XCTAssertFalse(result.contains("# >>> insomnia"))
        XCTAssertFalse(result.contains("[[hooks."))
        XCTAssertFalse(result.contains("# managed by insomnia"))
        // Everything that was the user's stays.
        XCTAssertTrue(result.contains(#"model = "gpt-5.5""#))
        XCTAssertTrue(result.contains("[features]"))
        XCTAssertTrue(result.contains("some_other_flag = true"))
        XCTAssertEqual(installer.status(expectedHookBinaryPath: nil), .notInstalled)
    }

    func testCodexStatusReportsStaleOnPathChange() throws {
        let url = try write("", to: "config.toml")
        let installer = CodexInstaller(configFile: url)
        try installer.install(hookBinaryPath: "/old/insomnia-hook")
        XCTAssertEqual(installer.status(expectedHookBinaryPath: "/old/insomnia-hook"), .installed)
        XCTAssertEqual(installer.status(expectedHookBinaryPath: "/new/insomnia-hook"), .stale)
    }
}
