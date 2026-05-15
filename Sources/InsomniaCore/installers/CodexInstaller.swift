import Foundation

/// Installs Insomnia's hooks into Codex CLI's `~/.codex/config.toml`.
///
/// Codex's config is TOML. Rather than depend on a TOML parser, the installer
/// makes two narrow, marker-delimited edits that round-trip cleanly:
///
///  1. **Feature flag** — Codex's `[hooks]` system requires
///     `[features] codex_hooks = true`. We add it under an existing
///     `[features]` table (or append one), tagged with a marker comment so
///     uninstall can remove exactly the line we added.
///  2. **Managed block** — the `[[hooks.*]]` array-of-tables are written as a
///     single block between `# >>> insomnia … >>>` / `# <<< … <<<` markers,
///     appended at end of file. Reinstall replaces it; uninstall removes it.
///
/// The user's own content is never parsed or rewritten — only our block and
/// our flag line are touched. A `.insomnia.bak` copy is made before the first
/// edit. (Codex has no `SessionEnd` hook, so stale sessions are reaped by the
/// grace period and absolute safety cap instead.)
public struct CodexInstaller: AgentInstaller {
    public let agent: AgentKind = .codex
    public let configFile: URL

    private static let blockStart = "# >>> insomnia (managed block — do not edit) >>>"
    private static let blockEnd   = "# <<< insomnia (managed block) <<<"
    private static let flagMarker = "# managed by insomnia"

    private let eventMap: [(native: String, semantic: SemanticEvent)] = [
        ("SessionStart",     .sessionStart),
        ("UserPromptSubmit", .working),
        ("Stop",             .idle),
    ]

    public init(configFile: URL = Paths.codexConfigFile) {
        self.configFile = configFile
    }

    // MARK: AgentInstaller

    public func install(hookBinaryPath: String) throws {
        let original = (try? String(contentsOf: configFile, encoding: .utf8)) ?? ""
        var text = stripManagedBlock(from: original)
        text = ensureFeatureFlag(in: text)
        text = appendManagedBlock(to: text, hookBinaryPath: hookBinaryPath)
        try InstallerSupport.backupIfNeeded(configFile)
        try InstallerSupport.atomicWrite(Data(text.utf8), to: configFile)
    }

    public func uninstall() throws {
        guard let original = try? String(contentsOf: configFile, encoding: .utf8) else { return }
        var text = stripManagedBlock(from: original)
        text = removeManagedFeatureFlag(in: text)
        if text != original {
            try InstallerSupport.backupIfNeeded(configFile)
            try InstallerSupport.atomicWrite(Data(text.utf8), to: configFile)
        }
    }

    public func status(expectedHookBinaryPath: String?) -> IntegrationStatus {
        guard let text = try? String(contentsOf: configFile, encoding: .utf8) else {
            return .configMissing
        }
        guard text.contains(Self.blockStart) else { return .notInstalled }
        if let expected = expectedHookBinaryPath {
            let want = InstallerSupport.hookCommand(
                binaryPath: expected, agent: .codex, event: .working)
            if !text.contains(want) { return .stale }
        }
        return .installed
    }

    // MARK: Managed block

    private func stripManagedBlock(from text: String) -> String {
        guard let startRange = text.range(of: Self.blockStart),
              let endRange = text.range(of: Self.blockEnd),
              startRange.lowerBound < endRange.lowerBound else {
            return text
        }
        // Extend the removal to the whole line containing the start marker …
        var lower = startRange.lowerBound
        while lower > text.startIndex,
              text[text.index(before: lower)] != "\n" {
            lower = text.index(before: lower)
        }
        // … through the newline that ends the end-marker line.
        var upper = endRange.upperBound
        if upper < text.endIndex, text[upper] == "\n" {
            upper = text.index(after: upper)
        }
        var result = text
        result.removeSubrange(lower..<upper)
        return result
    }

    private func appendManagedBlock(to text: String, hookBinaryPath: String) -> String {
        var base = text
        while base.hasSuffix("\n") || base.hasSuffix(" ") || base.hasSuffix("\t") {
            base.removeLast()
        }
        let separator = base.isEmpty ? "" : "\n\n"
        return base + separator + buildBlock(hookBinaryPath: hookBinaryPath) + "\n"
    }

    private func buildBlock(hookBinaryPath: String) -> String {
        var s = Self.blockStart + "\n"
        s += "# Keeps your Mac awake while Codex is working. Managed by Insomnia.\n"
        for (native, semantic) in eventMap {
            let cmd = InstallerSupport.hookCommand(
                binaryPath: hookBinaryPath, agent: .codex, event: semantic)
            s += "[[hooks.\(native)]]\n"
            s += "[[hooks.\(native).hooks]]\n"
            s += "type = \"command\"\n"
            s += "command = \(tomlBasicString(cmd))\n\n"
        }
        s += Self.blockEnd
        return s
    }

    // MARK: Feature flag

    private func ensureFeatureFlag(in text: String) -> String {
        // Already enabled anywhere? Leave the user's line untouched.
        if text.range(of: #"(?m)^[ \t]*codex_hooks[ \t]*=[ \t]*true"#,
                      options: .regularExpression) != nil {
            return text
        }
        var lines = text.components(separatedBy: "\n")
        if let idx = lines.firstIndex(where: {
            $0.range(of: #"^[ \t]*\[[ \t]*features[ \t]*\][ \t]*$"#,
                     options: .regularExpression) != nil
        }) {
            lines.insert("codex_hooks = true  \(Self.flagMarker)", at: idx + 1)
            return lines.joined(separator: "\n")
        }
        var result = text
        while result.hasSuffix("\n") { result.removeLast() }
        let separator = result.isEmpty ? "" : "\n\n"
        return result + separator + "[features]\ncodex_hooks = true  \(Self.flagMarker)\n"
    }

    private func removeManagedFeatureFlag(in text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !($0.contains(Self.flagMarker) && $0.contains("codex_hooks")) }
            .joined(separator: "\n")
    }

    // MARK: TOML

    /// Encode a string as a TOML basic (double-quoted) string.
    private func tomlBasicString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:   out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
