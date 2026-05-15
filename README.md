# Insomnia

<p align="center">
  <img src="docs/images/hero.jpg" alt="Insomnia — keep your Mac awake while AI agents work" width="720">
</p>

**Keep your Mac awake while an AI coding agent is working.**

When Claude Code, Codex, or Gemini CLI is grinding through a long autonomous
task, you can't just walk away — the Mac hits its idle-sleep timer and the task
halts mid-run. Insomnia is a tiny macOS menu bar app that holds a system
idle-sleep assertion **only while a followed agent is actively working** (plus a
short grace period after each turn), then lets the Mac sleep normally once the
agent goes idle.

The display is still allowed to sleep — so you can literally close your eyes and
go to bed while the work continues.

No API keys, no telemetry, nothing to configure. Open source under the MIT
license.

> Not affiliated with Kong's "Insomnia" API client — same word, different tool.

## How it works

```
agent CLI ──hook──▶ insomnia-hook ──writes──▶ session state files
                                                     │
                                              watcher + 10s timer
                                                     │
                                                     ▼
                                          Insomnia.app reconciles
                                                     │
                                          ┌──────────┴──────────┐
                                   IOKit power assertion   menu bar icon
```

Each agent's hook system runs the bundled `insomnia-hook` helper on session
events. The helper records one small JSON file per active session. The menu bar
app watches that directory, and a pure reconcile engine decides whether to hold
an IOKit `PreventUserIdleSystemSleep` assertion.

## Supported agents

| Agent | Integration | Config file |
|-------|-------------|-------------|
| **Claude Code** | hooks | `~/.claude/settings.json` |
| **Codex CLI** | `[hooks]` + `codex_hooks` feature | `~/.codex/config.toml` |
| **Gemini CLI** | hooks | `~/.gemini/settings.json` |

You pick which agents to follow in the Settings window (also shown on first
launch as a short onboarding). Insomnia installs and removes each integration
for you, and never clobbers your existing config — see
[docs/HOOKS.md](docs/HOOKS.md).

## Install

1. Download `Insomnia-<version>.zip` from the [Releases](../../releases) page and
   unzip it.
2. Move `Insomnia.app` to `/Applications`.
3. **First launch:** because the app isn't notarized, right-click it → **Open** →
   **Open**. You only do this once. See [docs/GATEKEEPER.md](docs/GATEKEEPER.md).
4. On first run, the Settings window opens so you can pick which agents to
   follow. You can change this anytime from the menu bar's **Settings…** item.
5. **Restart any running agent sessions** so they pick up the new hooks.

That's it — a `zzZ` indicator appears in your menu bar. It bumps to a heavier
weight when Insomnia is holding an awake assertion.

## Build from source

Requires the Xcode Command Line Tools and macOS 13+.

```sh
git clone <this-repo>
cd insomnia
swift build -c release        # build the executables
./Bundle/bundle.sh            # assemble dist/Insomnia.app (ad-hoc signed)
```

Run the tests with `swift test`, and the hook integration script with
`./scripts/test-hook.sh`. `./scripts/install-dev.sh` builds and copies the app
into `/Applications` for local testing.

## Usage

The menu bar item shows the current state and a small set of controls:

- **Header** — `Keeping Mac awake` or `Idle — Mac can sleep`, plus a line per
  active session.
- **Keep Awake Anyway** — force the Mac awake regardless of agent activity.
- **Settings…** — opens a one-page window for everything else: which agents to
  follow, grace period, AC-only mode, launch at login.

The Settings window is also what appears on first launch as a short
onboarding — pick your agents and you're done.

## Where it works (and where it doesn't)

Under the hood Insomnia holds the same IOKit `PreventUserIdleSystemSleep`
assertion that Apple's built-in `caffeinate -i` uses. It's a "smart
`caffeinate`" that knows when your agent is actually working.

### ✅ Insomnia keeps the Mac awake

| Scenario | Result |
|---|---|
| Lid open, no input for 10/15/30 min, agent working | Stays awake. Display can still sleep. |
| Multiple agents running at once | Awake while *any* followed session is working; grace period waits for the last one. |
| On AC power | Works. |
| On battery | Works by default; flip *Only on AC Power* in Settings if you'd rather not drain the battery. |
| Network drops / Wi-Fi sleeps | Insomnia doesn't manage networking — Power Nap and Wi-Fi-on-sleep are separate macOS settings. |

### ❌ Insomnia can *not* help

| Scenario | Why |
|---|---|
| Laptop lid closed (clamshell sleep) | The IOKit assertion Insomnia uses doesn't override clamshell. Two real workarounds below — neither requires Insomnia itself. |
| Sleep from Apple menu, or pressing the power button | User-initiated sleep is intentional and bypasses every assertion — by design. |
| Battery empty | Obvious. The Mac will sleep before it powers off. |
| Insomnia.app is quit, or Mac restarts | The assertion lives with the process. Turn on *Launch at Login* so it comes back. |
| Display sleep (screen goes black) | Insomnia only blocks *system* sleep, not the display. This is deliberate so you can shut your eyes while the agent works. |
| Agent exits without firing its end hook | Picked up by the 10-second reconcile timer, the PID liveness check, and an absolute safety cap — released within ~10 s in practice, and a hard cap of 4 hours even in pathological cases. |

### Closed-lid (clamshell) workarounds

Insomnia itself can't beat clamshell — the IOKit assertion lives in the wrong
layer. But two macOS-native tricks do, and either one combines fine with
Insomnia:

**Option A — AC power + an external display attached.** Any HDMI/USB-C
display works, including a $5 HDMI dummy plug. macOS keeps the system awake
on its own when that combination is present, no settings to flip. The Apple-
sanctioned recipe.

**Option B — `sudo pmset -a disablesleep 1`.** Apple Silicon respects this
global preference: on AC power, the Mac stays awake with the lid closed even
without an external display. To undo:

```sh
sudo pmset -a disablesleep 1   # prevent sleep with lid closed (AC only)
sudo pmset -a disablesleep 0   # back to default
```

Caveats: it's a **system-wide, persistent** setting (survives reboots), not
scoped to Insomnia or a single agent session — so remember to flip it off
when you're done. On battery the Mac will sleep anyway. And the built-in
display can't render with the lid shut, so this is for "run overnight on
charger" scenarios, not "use the laptop closed."

### How is this different from `caffeinate`?

`caffeinate -i &` holds the assertion until you remember to kill it.
Insomnia holds it **only** while your agent's hook reports *working*, plus a
configurable grace period, so the Mac sleeps normally the moment your work
is done. You set it up once and forget about it.

## Notes

- **Unsigned in v1** — no Apple Developer notarization yet (see
  [docs/GATEKEEPER.md](docs/GATEKEEPER.md)).
- The app must be running to hold the assertion. Turn on *Launch at Login*
  and forget about it.

## Disclaimer

Insomnia keeps your Mac awake — which means it **uses more power than letting it
sleep**, and on battery it will drain faster. It will not help your battery
life; if anything, expect the opposite. Turn on **Only on AC Power** if that
matters to you.

Insomnia is provided as-is, with no warranty of any kind — **use at your own
risk**. See [LICENSE](LICENSE).

## Uninstall

1. Open **Settings…** from the menu and uncheck each followed agent (removes
   the hooks), or run `insomnia-hook uninstall`.
2. Quit Insomnia and delete `Insomnia.app`.
3. Delete `~/Library/Application Support/Insomnia/` if you want to remove its
   state and config.

The original, pre-Insomnia copy of each agent config is kept beside it as
`<config>.insomnia.bak`.

## Roadmap

- Notarized, signed builds
- Homebrew tap (`brew install --cask insomnia`)
- Per-project allow/deny lists

## License

MIT — see [LICENSE](LICENSE).
