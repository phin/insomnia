import Foundation
import Darwin

/// Best-effort process-tree inspection, used by `insomnia-hook` to resolve the
/// PID of the agent CLI that spawned it.
///
/// None of the agent hook payloads include a PID, and the hook's immediate
/// parent is usually a shell — so we walk up the ancestry looking for the
/// agent's own executable. The result is advisory only: if the walk finds
/// nothing, the hook records no PID and the reconcile engine falls back to the
/// grace period and absolute safety cap.
public enum ProcessTree {

    /// Parent PID of `pid` via `sysctl(KERN_PROC_PID)`, or nil.
    public static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard rc == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// Executable basename of `pid` (e.g. `"node"`, `"codex"`) via
    /// `proc_pidpath`, or nil.
    public static func executableName(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : (path as NSString).lastPathComponent
    }

    /// Walk up from `start` looking for a process whose executable basename is
    /// one of `names` (case-insensitive). Returns that PID, or nil if none of
    /// the first `maxDepth` ancestors match.
    public static func findAncestor(from start: Int32,
                                    matching names: Set<String>,
                                    maxDepth: Int = 8) -> Int32? {
        let wanted = Set(names.map { $0.lowercased() })
        var current = start
        for _ in 0..<maxDepth {
            if current <= 1 { break }   // launchd / kernel
            if let name = executableName(of: current),
               wanted.contains(name.lowercased()) {
                return current
            }
            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }
        return nil
    }

    /// Executable names that identify each agent CLI's own process.
    public static func candidateExecutableNames(for agent: AgentKind) -> Set<String> {
        switch agent {
        case .claudeCode: return ["claude", "node"]
        case .codex:      return ["codex"]
        case .geminiCLI:  return ["gemini", "node"]
        }
    }

    /// Best-effort PID of the agent process that (transitively) spawned this
    /// hook. Starts from the hook's own parent and walks up.
    public static func findAgentPID(for agent: AgentKind) -> Int32? {
        findAncestor(from: getppid(), matching: candidateExecutableNames(for: agent))
    }
}
