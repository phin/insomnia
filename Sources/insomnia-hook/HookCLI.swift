import Foundation
import InsomniaCore

/// User-facing subcommands of `insomnia-hook`. Unlike hook mode, these are run
/// by a human in a terminal, so they may print to stdout and exit non-zero.
enum HookCLI {
    static func runSubcommand(_ args: [String]) {
        let sub = args.first ?? "help"
        let rest = Array(args.dropFirst())
        switch sub {
        case "install":   runInstall(rest)
        case "uninstall": runUninstall(rest)
        case "status":    runStatus()
        default:          printUsage()
        }
    }

    // MARK: - install / uninstall

    private static func runInstall(_ agentArgs: [String]) {
        let hookPath = AgentIntegration.defaultHookBinaryPath()
        let (agents, explicit) = resolveAgents(agentArgs)
        guard !agents.isEmpty else { return }

        for agent in agents {
            let installer = AgentIntegration.installer(for: agent)
            if !explicit && !installer.isAgentPresent {
                print("•  \(agent.displayName): skipped — not detected "
                    + "(run `insomnia-hook install \(agent.rawValue)` to force)")
                continue
            }
            do {
                try installer.install(hookBinaryPath: hookPath)
                print("✓  \(agent.displayName): integration installed "
                    + "→ \(installer.configFile.path)")
            } catch {
                print("✗  \(agent.displayName): \(error.localizedDescription)")
            }
        }
        print("\nRestart any running agent sessions for the hooks to take effect.")
    }

    private static func runUninstall(_ agentArgs: [String]) {
        let (agents, _) = resolveAgents(agentArgs)
        for agent in agents {
            let installer = AgentIntegration.installer(for: agent)
            do {
                try installer.uninstall()
                print("✓  \(agent.displayName): integration removed")
            } catch {
                print("✗  \(agent.displayName): \(error.localizedDescription)")
            }
        }
    }

    private static func runStatus() {
        let hookPath = AgentIntegration.defaultHookBinaryPath()
        print("insomnia-hook binary: \(hookPath)\n")

        print("Agent integrations:")
        for agent in AgentKind.allCases {
            let installer = AgentIntegration.installer(for: agent)
            let status = installer.status(expectedHookBinaryPath: hookPath)
            let name = agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0)
            // A missing config file still means "installable" when the agent's
            // own directory exists (e.g. Gemini before its settings.json is written).
            let summary = (status == .configMissing && installer.isAgentPresent)
                ? "not installed" : status.summary
            print("  \(name) \(summary)")
        }

        let sessions = SessionStore().list()
        print("\nActive session files: \(sessions.count)  (\(Paths.sessionsDir.path))")
        for loaded in sessions {
            let s = loaded.state
            print("  \(s.agent.displayName)  \(s.sessionId)  \(s.state.rawValue)")
        }
    }

    // MARK: - helpers

    /// Resolve agent-name arguments. With no args, returns every agent and
    /// `explicit == false` (callers then skip undetected agents). With args,
    /// returns the named agents and `explicit == true`.
    private static func resolveAgents(_ args: [String]) -> (agents: [AgentKind], explicit: Bool) {
        guard !args.isEmpty else { return (AgentKind.allCases, false) }
        var result: [AgentKind] = []
        for arg in args {
            if let a = agentKind(from: arg) {
                if !result.contains(a) { result.append(a) }
            } else {
                FileHandle.standardError.write(
                    Data("insomnia-hook: unknown agent '\(arg)'\n".utf8))
            }
        }
        return (result, true)
    }

    private static func agentKind(from s: String) -> AgentKind? {
        switch s.lowercased() {
        case "claude-code", "claude", "claudecode": return .claudeCode
        case "codex":                               return .codex
        case "gemini-cli", "gemini", "geminicli":   return .geminiCLI
        default:                                    return AgentKind(rawValue: s)
        }
    }

    static func printUsage() {
        print("""
        insomnia-hook — Insomnia's agent hook helper

        Hook mode (invoked by agent CLIs; reads the hook JSON on stdin):
          insomnia-hook <agent> <event>
            agent:  claude-code | codex | gemini-cli
            event:  working | idle | session-start | session-end

        Subcommands (run these yourself):
          install [agent...]     Install Insomnia's integration. With no agents,
                                 installs for every detected agent.
          uninstall [agent...]   Remove Insomnia's integration.
          status                 Show integration and active-session status.
          help, --help, -h       Show this help.

        Agent names accept aliases: claude, gemini.
        """)
    }
}
