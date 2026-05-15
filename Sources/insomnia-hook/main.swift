import Foundation
import InsomniaCore

// insomnia-hook
//
// Two modes:
//   * Hook mode  — `insomnia-hook <agent> <event>`, invoked by an agent CLI's
//     hook system. Reads the hook JSON on stdin, normalizes it into a
//     SessionState file. MUST never write to stdout and MUST always exit 0, so
//     it can never block or disrupt the calling agent (Gemini even runs hooks
//     synchronously in its agent loop).
//   * Subcommand mode — `install` / `uninstall` / `status` / `help`, run by a
//     human in a terminal; may print and exit non-zero.

let args = Array(CommandLine.arguments.dropFirst())

// Subcommand mode.
if let sub = args.first,
   ["install", "uninstall", "status", "help", "--help", "-h"].contains(sub) {
    HookCLI.runSubcommand(args)
    exit(0)
}
if args.isEmpty {
    HookCLI.printUsage()
    exit(0)
}

// Hook mode. Every failure path below exits 0 silently — a misconfigured hook
// must never break the agent that called it.
guard args.count >= 2,
      let agent = AgentKind(rawValue: args[0]),
      let event = SemanticEvent(rawValue: args[1]) else {
    FileHandle.standardError.write(Data(
        "insomnia-hook: invalid hook invocation; expected <agent> <event>\n".utf8))
    exit(0)
}

let stdinData = (try? FileHandle.standardInput.readToEnd()) ?? Data()
let payload = HookPayload(jsonData: stdinData)

guard let sessionId = payload.sessionId, !sessionId.isEmpty else {
    // No session id — nothing trackable. (PID resolution lands in step 10.)
    exit(0)
}

// Best-effort: walk up the process tree to find the agent's PID, so the app
// can reap the session promptly if the agent dies without a clean end event.
let agentPID = ProcessTree.findAgentPID(for: agent)

do {
    try HookProcessor().apply(agent: agent, event: event,
                              sessionId: sessionId, cwd: payload.cwd, pid: agentPID)
} catch {
    // Best-effort only: never surface an error to the calling agent.
}

exit(0)
