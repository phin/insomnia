# Agent integrations

Insomnia learns when an agent is working by registering hooks with each agent
CLI. The hooks run the bundled `insomnia-hook` helper, which writes one small
JSON file per session into `~/Library/Application Support/Insomnia/sessions/`.

You normally don't touch any of this — the menu bar app's **Follow …** toggles
(and the first-run prompt) install and remove these integrations for you, and
`insomnia-hook install` / `uninstall` / `status` do the same from the terminal.
This document is for understanding or hand-editing the integrations.

All edits are **surgical and idempotent**: Insomnia only adds/updates its own
entries, never touches anything else, and makes a one-time backup of each config
at `<config>.insomnia.bak` before its first edit.

## The helper

`insomnia-hook` is invoked as:

```
insomnia-hook <agent> <event>
```

- `agent` — `claude-code`, `codex`, or `gemini-cli`
- `event` — `working`, `idle`, `session-start`, or `session-end`

It reads the agent's hook JSON on stdin (it only needs `session_id` and `cwd`,
which all three CLIs provide), updates the session file, writes nothing to
stdout, and always exits 0 — so it can never block or disrupt the agent.

Each agent's installer maps that CLI's native events onto these four, so the
helper itself stays agent-agnostic.

## Claude Code — `~/.claude/settings.json`

Insomnia adds a top-level `hooks` object. Event mapping: `SessionStart` →
session-start, `UserPromptSubmit` → working, `Stop` → idle, `Notification` →
idle, `SessionEnd` → session-end. Each entry looks like:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": "*",
        "hooks": [
          { "type": "command",
            "command": "'/Applications/Insomnia.app/Contents/MacOS/insomnia-hook' claude-code working",
            "timeout": 5 }
        ] }
    ]
  }
}
```

## Codex CLI — `~/.codex/config.toml`

Codex's `[hooks]` system requires `[features] codex_hooks = true`. Insomnia adds
that flag (tagged with a `# managed by insomnia` comment) and a marker-delimited
block of `[[hooks.*]]` tables. Event mapping: `SessionStart` → session-start,
`UserPromptSubmit` → working, `Stop` → idle. Codex has no `SessionEnd` hook, so
stale sessions are reaped by the grace period and the absolute safety cap.

```toml
[features]
codex_hooks = true  # managed by insomnia

# >>> insomnia (managed block — do not edit) >>>
[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "'/Applications/Insomnia.app/Contents/MacOS/insomnia-hook' codex working"
# <<< insomnia (managed block) <<<
```

## Gemini CLI — `~/.gemini/settings.json`

Same JSON nesting as Claude Code, but lifecycle hooks take no `matcher` and
`timeout` is in **milliseconds**. Event mapping: `SessionStart` → session-start,
`BeforeAgent` → working, `AfterAgent` → idle, `SessionEnd` → session-end.

```json
{
  "hooks": {
    "BeforeAgent": [
      { "hooks": [
          { "type": "command",
            "command": "'/Applications/Insomnia.app/Contents/MacOS/insomnia-hook' gemini-cli working",
            "timeout": 5000 }
      ] }
    ]
  }
}
```

## After installing

**Hooks load when an agent session starts.** Restart any running Claude Code /
Codex / Gemini sessions after installing, or they won't fire the hooks.

## Troubleshooting

- `insomnia-hook status` — shows where the binary is, each agent's integration
  status, and the current active-session files.
- Check `~/Library/Application Support/Insomnia/sessions/` — there should be a
  JSON file per live session while an agent is working.
- For Claude Code, `claude --debug` logs hook execution.
- Codex's `[hooks]` system can be unreliable with *project-level*
  `.codex/config.toml`; Insomnia always uses the user-level config.
- Verify the Mac is actually being kept awake with `pmset -g assertions` — look
  for `PreventUserIdleSystemSleep` named `"Insomnia: …"`.
