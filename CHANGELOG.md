# Changelog

All notable changes to Insomnia are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## 0.2.0

### Added

- One-page **Settings** window for picking which agents to follow, grace
  period, AC-only mode, and Launch at Login. Doubles as a friendly first-run
  onboarding screen, replacing the previous NSAlert prompt.
- App icon (`AppIcon.icns`) — proper Finder / About / Spotlight icon.
- "How it works" section inside Settings, and a Follow @nsphin on X link.

### Changed

- **Slimmed the menu bar menu** to just status header, active sessions,
  *Keep Awake Anyway*, *Settings…*, and *Quit*. Everything else (agent
  toggles, grace period, AC-only, Launch at Login) moved to the Settings
  window.
- **Menu bar indicator** is now a `zzZ` text glyph that bumps to heavy weight
  while an awake assertion is held, replacing the `cup.and.saucer` SF Symbol.
- README — added a hero image and updated copy to match the new menu and
  onboarding flow.

### Removed

- *Allow Sleep Now* manual override. *Keep Awake Anyway* covers the common
  case; uninstalling an agent or quitting Insomnia covers the rest.

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
