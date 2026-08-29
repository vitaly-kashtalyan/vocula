#!/bin/bash
# Usage: ./scripts/uninstall-local.sh
#
# Removes the installed app and every trace it leaves, so the next
# ./scripts/install-local.sh is the run a buyer gets. Destroys real data: every
# dictation ever made, its encryption key, the settings, and 1.6 GB of weights.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f App/project.yml ] || { echo "uninstall: not the repository root" >&2; exit 1; }

APP="/Applications/Vocula.app"
SUPPORT="$HOME/Library/Application Support"
removed=0
gone() { printf '  removed  %s\n' "$*"; removed=$((removed + 1)); }
absent() { printf '  absent   %s\n' "$*"; }

echo "This deletes $APP, every dictation in its history, its encryption key,"
echo "its settings, and 1.6 GB of downloaded models."
printf 'Type "yes" to continue: '
read -r answer
[ "$answer" = "yes" ] || { echo "uninstall: nothing was done"; exit 1; }

# applicationShouldTerminate drains a pending clipboard restore, so the quit is
# awaited rather than assumed.
if pgrep -x Vocula >/dev/null 2>&1; then
  osascript -e 'tell application "Vocula" to quit' >/dev/null 2>&1 || true
  waited=0
  while pgrep -x Vocula >/dev/null 2>&1; do
    sleep 0.2
    waited=$((waited + 1))
    [ "$waited" -lt 50 ] || { echo "uninstall: Vocula would not quit" >&2; exit 1; }
  done
  gone "the running copy"
else
  absent "a running copy"
fi

if [ -d "$APP" ]; then rm -rf "$APP"; gone "$APP"; else absent "$APP"; fi

# app.vocula.Vocula is what this app was called before the rename, and
# app.vocula.Probe was a build made to prove the rename fixed the menu bar.
for name in app.vocula.mac app.vocula.Vocula; do
  if [ -d "$SUPPORT/$name" ]; then rm -rf "$SUPPORT/$name"; gone "$SUPPORT/$name"
  else absent "$SUPPORT/$name"; fi
done

for domain in app.vocula.mac app.vocula.mac.uitest app.vocula.Vocula app.vocula.Probe; do
  if defaults read "$domain" >/dev/null 2>&1; then
    defaults delete "$domain"; gone "defaults domain $domain"
  else absent "defaults domain $domain"; fi
done
killall cfprefsd >/dev/null 2>&1 || true

for service in app.vocula.mac app.vocula.Vocula; do
  if security find-generic-password -s "$service" >/dev/null 2>&1; then
    security delete-generic-password -s "$service" >/dev/null
    gone "history key for $service"
  else absent "history key for $service"; fi
done

for identifier in app.vocula.mac app.vocula.Vocula; do
  if tccutil reset All "$identifier" >/dev/null 2>&1; then gone "permissions for $identifier"
  else absent "permissions for $identifier"; fi
done

# Every build ever run registers another bundle under this identifier, and a
# stale one can answer an `open -a` meant for the installed copy.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
stale=$("$LSREG" -dump 2>/dev/null | grep -oE '/[^ ]*Vocula\.app' | sort -u || true)
if [ -n "$stale" ]; then
  count=$(printf '%s\n' "$stale" | wc -l | tr -d ' ')
  printf '%s\n' "$stale" | while read -r path; do "$LSREG" -u "$path" >/dev/null 2>&1 || true; done
  gone "$count LaunchServices registrations"
else
  absent "LaunchServices registrations"
fi

echo
[ "$removed" -gt 0 ] || { echo "uninstall: nothing was there to remove"; exit 0; }
echo "uninstall: $removed things removed. Everything a script can reach is gone."
echo
echo "One step is left, and only you can do it:"
echo
echo "  System Settings → General → Login Items & Extensions → Open at Login"
echo "  Delete every row named Vocula."
echo
echo "Then: ./scripts/install-local.sh"
