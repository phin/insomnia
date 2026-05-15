import Foundation

/// Reads/writes a JSON settings file as a generic `[String: Any]` tree, so
/// unknown keys written by the agent (or the user) are always preserved on a
/// round trip. Used by the Claude Code and Gemini CLI installers.
struct JSONSettingsStore {
    let url: URL

    /// Parse the file, or return an empty object if it's missing/empty.
    func loadOrEmpty() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.unexpectedShape(
                "\(url.lastPathComponent) is not a JSON object")
        }
        return obj
    }

    func write(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try InstallerSupport.atomicWrite(data, to: url)
    }
}

/// Surgically merges (and removes) Insomnia's hook entries inside the
/// `hooks` object of a Claude Code / Gemini CLI settings tree.
///
/// Both CLIs share the same nesting: `hooks.<EventName>` is an array of
/// matcher-groups, each group has a `hooks` array of `{type, command, timeout}`
/// entries. The only differences are captured by `matcher` and `timeout`.
struct JSONHookMerger {
    let agent: AgentKind
    /// Native event name → Insomnia semantic event.
    let eventMap: [(native: String, semantic: SemanticEvent)]
    /// Matcher to write on new groups (`"*"` for Claude; `nil` for Gemini).
    let matcher: String?
    /// Timeout value to write (seconds for Claude; milliseconds for Gemini).
    let timeout: Int

    // MARK: Install

    /// Insert or refresh our hook entries. Idempotent. Throws rather than
    /// clobber a `hooks` tree that has an unexpected shape.
    func merge(into root: inout [String: Any], hookBinaryPath: String) throws {
        var hooks = try hooksObject(in: root)
        for (native, semantic) in eventMap {
            var groups = try eventArray(hooks[native], event: native)
            let command = InstallerSupport.hookCommand(
                binaryPath: hookBinaryPath, agent: agent, event: semantic)
            if !updateExistingEntry(in: &groups, command: command) {
                var group: [String: Any] = [
                    "hooks": [["type": "command", "command": command, "timeout": timeout]]
                ]
                if let matcher { group["matcher"] = matcher }
                groups.append(group)
            }
            hooks[native] = groups
        }
        root["hooks"] = hooks
    }

    /// Update the command of an existing Insomnia entry in place. Returns true
    /// if one was found and updated.
    private func updateExistingEntry(in groups: inout [[String: Any]],
                                     command: String) -> Bool {
        for i in groups.indices {
            guard var inner = groups[i]["hooks"] as? [[String: Any]] else { continue }
            var updated = false
            for j in inner.indices {
                if let c = inner[j]["command"] as? String,
                   InstallerSupport.isInsomniaCommand(c) {
                    inner[j]["type"] = "command"
                    inner[j]["command"] = command
                    inner[j]["timeout"] = timeout
                    updated = true
                }
            }
            if updated {
                groups[i]["hooks"] = inner
                return true
            }
        }
        return false
    }

    // MARK: Uninstall

    /// Remove only Insomnia's entries. Returns true if anything changed.
    func remove(from root: inout [String: Any]) throws -> Bool {
        guard root["hooks"] != nil else { return false }
        var hooks = try hooksObject(in: root)
        var changed = false
        for (native, _) in eventMap {
            guard hooks[native] != nil else { continue }
            var groups = try eventArray(hooks[native], event: native)
            let before = groups
            groups = groups.compactMap { group -> [String: Any]? in
                guard var inner = group["hooks"] as? [[String: Any]] else { return group }
                inner.removeAll { entry in
                    (entry["command"] as? String)
                        .map(InstallerSupport.isInsomniaCommand) ?? false
                }
                if inner.isEmpty { return nil }  // group held only our hook(s)
                var g = group
                g["hooks"] = inner
                return g
            }
            if groups.count != before.count { changed = true }
            if groups.isEmpty { hooks.removeValue(forKey: native) }
            else { hooks[native] = groups }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") }
        else { root["hooks"] = hooks }
        return changed
    }

    // MARK: Status

    func status(in root: [String: Any],
                expectedHookBinaryPath: String?) -> IntegrationStatus {
        let hooks: [String: Any]
        do { hooks = try hooksObject(in: root) }
        catch { return root["hooks"] == nil ? .notInstalled
                                             : .error("\(error.localizedDescription)") }
        var foundAll = true
        var anyStale = false
        for (native, semantic) in eventMap {
            let groups = (hooks[native] as? [[String: Any]]) ?? []
            let ourCommands = groups
                .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
                .compactMap { $0["command"] as? String }
                .filter(InstallerSupport.isInsomniaCommand)
            if ourCommands.isEmpty {
                foundAll = false
                continue
            }
            if let expected = expectedHookBinaryPath {
                let want = InstallerSupport.hookCommand(
                    binaryPath: expected, agent: agent, event: semantic)
                if !ourCommands.contains(want) { anyStale = true }
            }
        }
        if !foundAll { return .notInstalled }
        return anyStale ? .stale : .installed
    }

    // MARK: Shape guards

    private func hooksObject(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let dict = value as? [String: Any] else {
            throw InstallerError.unexpectedShape("'hooks' is not an object")
        }
        return dict
    }

    private func eventArray(_ value: Any?, event: String) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let array = value as? [[String: Any]] else {
            throw InstallerError.unexpectedShape(
                "'hooks.\(event)' is not an array of objects")
        }
        return array
    }
}
