#!/bin/bash
set -euo pipefail

BUNDLE_ID="app.vocula.mac"
SUPPORT="$HOME/Library/Application Support/$BUNDLE_ID"
LOG="$SUPPORT/diagnostics.json"
failures=0

say()  { printf '%s\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; failures=$((failures + 1)); }

# The INSTALLED copy by default, never the build directory: this test needs a
# real Accessibility grant, and macOS keys that grant on the bundle
# identifier while rewriting which binary holds it. Pointing it at a build
# directory hands the grant to a bundle that a clean build deletes, and takes it
# from the copy the developer dictates with.
APP="${1:-/Applications/Vocula.app}"
[ -d "$APP" ] || { say "No app at $APP — run ./scripts/install-local.sh first."; exit 2; }
say "App: $APP"

signature=$(codesign -dv "$APP" 2>&1 || true)
case "$signature" in
  *"Identifier=$BUNDLE_ID"*) ;;
  *) say "That bundle is not $BUNDLE_ID."; exit 2 ;;
esac

if pgrep -f "Vocula.app/Contents/MacOS/Vocula" >/dev/null; then
  say "Quitting the copy that is already running…"
  osascript -e 'tell application "Vocula" to quit' >/dev/null 2>&1 || true
  sleep 2
fi

before_stamp=$(python3 - "$LOG" <<'PY' 2>/dev/null || echo -1
import json, sys
try:
    events = json.load(open(sys.argv[1]))
except Exception:
    events = []
# Mark the place by TIMESTAMP, never a count: the log is capped, so past the cap every slice is empty.
print(events[-1]["timestamp"] if events else -1)
PY
)
open "$APP" --args -VoculaNoUpdates
sleep 6
pgrep -f "Vocula.app/Contents/MacOS/Vocula" >/dev/null \
  && pass "the app is running" || { fail "the app did not stay up"; exit 1; }

new_events() {
  python3 - "$LOG" "$before_stamp" <<'PY'
import json, sys
try:
    events = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
since = float(sys.argv[2])
for e in events:
    if float(e.get("timestamp", 0)) > since:
        print(f"{e.get('kind')} {e.get('detail')}".strip())
PY
}

say "Launch:"
launched=$(new_events)
[ -n "$launched" ] \
  || fail "the log recorded nothing at all since launch — $LOG is unreadable or not being written" 
case "$launched" in
  *"tap.install ok=true"*) pass "the event tap installed" ;;
  *) fail "no 'tap.install ok=true' — Accessibility is probably not granted" ;;
esac
case "$launched" in
  *"permission.microphone state=granted"*) pass "the microphone is granted" ;;
  *) fail "the microphone is not granted (dictation cannot run)" ;;
esac

read_setting() { defaults read "$BUNDLE_ID" "$1" 2>/dev/null || echo ""; }
state() { echo "auto=$(read_setting language.autoDetect) pinned=$(read_setting language.pinned)"; }

bound=$(defaults export "$BUNDLE_ID" - 2>/dev/null \
  | plutil -extract 'binding\.languageCycle' raw -o - - 2>/dev/null \
  | base64 -d 2>/dev/null || echo "")
case "$bound" in
  "")           say "  --    no language-cycle binding stored; the default ⌃⇧L applies" ;;
  *'"modifiers":80'*) : ;;
  *) fail "the language key is not ⌃⇧L any more ($bound) — this script can only post ⌃⇧L, so the checks below would blame the tap for a rebinding" ;;
esac

codes=$(read_setting language.codes)
[ -n "$codes" ] || codes="en"
steps=$(( $(echo "$codes" | tr ',' '\n' | grep -c .) + 1 ))
start_state=$(state)
say "Language cycle ($codes, so a full turn is $steps presses), from: $start_state"

seen_change=0
for step in $(seq 1 "$steps"); do
  if ! osascript -e 'tell application "System Events" to key code 37 using {control down, shift down}' 2>/dev/null; then
    fail "could not post ⌃⇧L — grant Accessibility to the terminal running this"
    break
  fi
  sleep 1.5
  now=$(state)
  say "    press $step -> $now"
  [ "$now" = "$start_state" ] || seen_change=1
done

[ "$seen_change" = 1 ] \
  && pass "the cycle moved the setting" \
  || fail "the setting never changed — ⌃⇧L is not reaching the app"
if [ "$seen_change" = 1 ]; then
  [ "$(state)" = "$start_state" ] \
    && pass "a full turn came back to where it started ($start_state)" \
    || fail "the cycle did not return: was $start_state, now $(state)"
  [ "$(read_setting language.codes)" = "$codes" ] \
    && pass "the language set survived the cycle" \
    || fail "the language set changed: was $codes, now $(read_setting language.codes)"
else
  say "  --    the round trip and the language set were NOT checked: nothing moved"
fi
logged=$(new_events | grep -c '^language.cycle' || true)
[ "$logged" = "$steps" ] \
  && pass "the diagnostic log recorded $steps cycles" \
  || fail "the log recorded $logged cycles, expected $steps"

say ""
if [ "$failures" = 0 ]; then say "smoke: all checks passed"; else say "smoke: $failures check(s) failed"; fi
exit "$failures"
