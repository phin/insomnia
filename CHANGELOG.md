# Changelog

All notable changes to Insomnia are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## 0.1.0

First release.

### Added

- Menu bar app that keeps the Mac awake (system idle sleep only — the display
  still sleeps) while a followed AI coding agent is actively working, plus a
  configurable grace period after each turn.
- Integrations for **Claude Code**, **Codex CLI**, and **Gemini CLI** via each
  CLI's hook system. Install/remove per agent from the menu, the first-run
  prompt, or `insomnia-hook install` / `uninstall`.
- Surgical, idempotent, non-clobbering edits to each agent's config, with a
  one-time `<config>.insomnia.bak` backup.
- `insomnia-hook` helper: a fast, silent, never-blocking hook target plus
  `install` / `uninstall` / `status` subcommands.
- Pure reconcile engine: per-session working/grace/reap logic, PID-liveness
  checks, an absolute safety cap for crashed sessions, and per-agent following.
- Menu controls: manual "Keep Awake Anyway" / "Allow Sleep Now" overrides,
  "Only on AC Power", grace-period presets, and "Launch at Login".
- Low-latency directory watcher plus a 10-second reconcile backstop; power-source
  change detection; stale temp-file sweeping.
