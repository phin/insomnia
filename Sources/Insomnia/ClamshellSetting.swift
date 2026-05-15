import Foundation

/// Helpers for reading and flipping the system-wide `SleepDisabled` PM
/// preference, the one piece of macOS power policy that overrides clamshell
/// sleep on Apple Silicon. The flag is global and persistent — it survives
/// reboots and isn't scoped to any app — so we surface it explicitly in the
/// UI and confirm before flipping it.
enum ClamshellSetting {
    enum Error: Swift.Error, LocalizedError {
        case userCancelled
        case pmsetFailed(stderr: String)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                return "Password prompt cancelled."
            case .pmsetFailed(let stderr):
                return stderr.isEmpty ? "pmset failed" : stderr
            }
        }
    }

    /// Whether `SleepDisabled` is currently 1 according to `pmset -g`. Falls
    /// back to `false` if anything goes wrong — better to under-report than to
    /// claim the system is configured a way it isn't.
    static func isEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return false
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Format: "SleepDisabled        1"  (or 0). Whitespace varies.
            if trimmed.hasPrefix("SleepDisabled") {
                return trimmed.hasSuffix("1")
            }
        }
        return false
    }

    /// Flip the flag via `osascript ... with administrator privileges`. macOS
    /// renders the system password dialog. Throws on failure — including
    /// `userCancelled` if the user dismissed the prompt.
    static func setEnabled(_ enabled: Bool) throws {
        let value = enabled ? "1" : "0"
        // osascript escaping: the shell command is one double-quoted string
        // inside the AppleScript literal. `pmset` takes no quoting, so this
        // is straightforward.
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\""
                   + " with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = (String(data: stderrData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // osascript surfaces user cancellation as a non-zero exit with
            // "User canceled" (sic) in stderr.
            if stderr.contains("User canceled") || stderr.contains("(-128)") {
                throw Error.userCancelled
            }
            throw Error.pmsetFailed(stderr: stderr)
        }
    }
}
