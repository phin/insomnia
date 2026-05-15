#!/usr/bin/env bash
#
# test-hook.sh — exercise the insomnia-hook binary end-to-end with fake agent
# hook payloads and verify the SessionState files it produces. This is the
# verification step for build step 2.
#
# It runs against a throwaway sessions directory (INSOMNIA_SESSIONS_DIR), so it
# never touches your real ~/Library/Application Support/Insomnia state.

set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product insomnia-hook >/dev/null
HOOK="$(swift build --show-bin-path)/insomnia-hook"

INSOMNIA_SESSIONS_DIR="$(mktemp -d /tmp/insomnia-test.XXXXXX)"
export INSOMNIA_SESSIONS_DIR
trap 'rm -rf "$INSOMNIA_SESSIONS_DIR"' EXIT

fail() { echo "  FAIL: $1" >&2; exit 1; }

# run <agent> <event> <json>  — pipes json to the hook, asserts stdout is empty.
run() {
    local out
    out="$(printf '%s' "$3" | "$HOOK" "$1" "$2")" || fail "hook exited non-zero for '$1 $2'"
    [ -z "$out" ] || fail "hook wrote to stdout for '$1 $2': $out"
}

count()    { ls -1 "$INSOMNIA_SESSIONS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' '; }
state_of() { plutil -extract state raw -o - "$1"; }

echo "1. claude-code session-start -> creates an idle session file"
run claude-code session-start '{"session_id":"cc-1","cwd":"/tmp/p","hook_event_name":"SessionStart"}'
F="$INSOMNIA_SESSIONS_DIR/claude-code-cc-1.json"
[ -f "$F" ]                       || fail "expected $F to exist"
[ "$(count)" = "1" ]              || fail "expected 1 session file, got $(count)"
[ "$(state_of "$F")" = "idle" ]   || fail "expected state idle"

echo "2. working -> session flips to working"
run claude-code working '{"session_id":"cc-1"}'
[ "$(state_of "$F")" = "working" ] || fail "expected state working"

echo "3. idle -> session flips back to idle"
run claude-code idle '{"session_id":"cc-1"}'
[ "$(state_of "$F")" = "idle" ]    || fail "expected state idle"

echo "4. codex working -> separate file, no collision with claude-code"
run codex working '{"session_id":"cx-1","cwd":"/tmp/q"}'
[ "$(count)" = "2" ]               || fail "expected 2 session files, got $(count)"

echo "5. session-end -> file removed"
run claude-code session-end '{"session_id":"cc-1"}'
[ ! -f "$F" ]                      || fail "expected $F to be removed"
[ "$(count)" = "1" ]               || fail "expected 1 file left, got $(count)"

echo "6. garbage stdin -> exit 0, no session file created"
run gemini-cli working 'this is not json'
[ "$(count)" = "1" ]               || fail "garbage input must not create a file"

echo "7. empty stdin -> exit 0, no session file created"
run gemini-cli working ''
[ "$(count)" = "1" ]               || fail "empty input must not create a file"

echo "8. unknown agent -> exit 0, no session file created"
printf '{"session_id":"x"}' | "$HOOK" bogus-agent working >/dev/null \
    || fail "unknown agent must still exit 0"
[ "$(count)" = "1" ]               || fail "unknown agent must not create a file"

echo "9. gemini-cli full lifecycle"
run gemini-cli session-start '{"session_id":"gm-1","cwd":"/tmp/g"}'
run gemini-cli working         '{"session_id":"gm-1"}'
G="$INSOMNIA_SESSIONS_DIR/gemini-cli-gm-1.json"
[ "$(state_of "$G")" = "working" ] || fail "expected gemini session working"
run gemini-cli session-end     '{"session_id":"gm-1"}'
[ ! -f "$G" ]                      || fail "expected gemini session removed"

echo "ALL HOOK TESTS PASSED"
