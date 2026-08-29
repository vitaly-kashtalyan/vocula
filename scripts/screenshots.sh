#!/bin/sh
# Usage: ./scripts/screenshots.sh [locale ...]   (default: en)
# Takes over the screen, so it cannot run on a runner.
set -eu
cd "$(dirname "$0")/.."
[ -f App/project.yml ] || { echo "screenshots: not the repository root" >&2; exit 1; }
[ $# -gt 0 ] || set -- en

# History, Diagnostics and Licence draw the owner's own data: real transcripts,
# real device names, a real e-mail. The rest is read out of SettingsSection so
# that a section added there cannot be forgotten here.
withheld=" history diagnostics licence "
sections=""
for section in $(awk '/^  case status/{f=1} f{printf "%s ", $0; if ($0 !~ /,$/) exit}' \
  App/Vocula/UI/SettingsWindow.swift | sed 's/case//; s/,/ /g'); do
  case "$withheld" in *" $section "*) continue ;; esac
  sections="$sections $section"
done
[ -n "$sections" ] || { echo "screenshots: SettingsSection listed nothing" >&2; exit 1; }

out="$PWD/build/screenshots"

command -v xcodegen >/dev/null || { echo "screenshots: brew install xcodegen" >&2; exit 1; }
(cd App && xcodegen generate >/dev/null)
mkdir -p "$PWD/build"
xcodebuild -project App/Vocula.xcodeproj -scheme Vocula -configuration Debug build \
  >"$PWD/build/screenshots-build.log" 2>&1 ||
  { echo "screenshots: build failed; see build/screenshots-build.log" >&2; exit 1; }
app=$(xcodebuild -project App/Vocula.xcodeproj -scheme Vocula -configuration Debug \
  -showBuildSettings 2>/dev/null |
  awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')/Vocula.app
binary="$app/Contents/MacOS/Vocula"
[ -x "$binary" ] || { echo "screenshots: no app at $app" >&2; exit 1; }

# applicationShouldTerminate returns .terminateLater and drains, so `open` must
# not race the exit: it answers -600 while the old process is still going.
quit_vocula() {
  osascript -e 'tell application "Vocula" to quit' >/dev/null 2>&1 || true
  waited=0
  while pgrep -x Vocula >/dev/null 2>&1; do
    sleep 0.2
    waited=$((waited + 1))
    [ "$waited" -lt 50 ] || { echo "screenshots: Vocula would not quit" >&2; exit 1; }
  done
}

rm -rf "$out"

for locale in "$@"; do
  [ -d "$app/Contents/Resources/$locale.lproj" ] ||
    { echo "screenshots: $locale is not in the bundle" >&2; exit 1; }
  mkdir -p "$out/$locale"
  echo "> $locale"

  for appearance in light dark; do
    for section in $sections; do
      quit_vocula
      # NOT -VoculaUITest: reopenSettingsIfAsked() guards on it, so the flag
      # that protects key bindings during UI tests also suppresses the very
      # argument this loop drives the app with.
      opened=0
      tries=0
      while [ "$opened" -eq 0 ]; do
        if open -a "$app" --args \
          -VoculaScreenshot \
          -VoculaReopenSection "$section" \
          -appearance "$appearance" \
          -AppleLanguages "($locale)" 2>/dev/null; then
          opened=1
        else
          tries=$((tries + 1))
          [ "$tries" -lt 20 ] ||
            { echo "screenshots: LaunchServices kept refusing to open $app" >&2; exit 1; }
          sleep 0.5
        fi
      done

      # By full path, never by name: this machine has many bundles registered
      # under the same identifier, and photographing an older one would look
      # exactly like success.
      pid=""
      waited=0
      while [ -z "$pid" ]; do
        pid=$(pgrep -f "^$binary" | head -1 || true)
        [ -n "$pid" ] && break
        sleep 0.2
        waited=$((waited + 1))
        [ "$waited" -lt 100 ] ||
          { echo "screenshots: the build under test never started" >&2; exit 1; }
      done

      swift Tools/CaptureWindow.swift "$pid" \
        "$out/$locale/$locale-$appearance-$section.png"
    done
  done
  quit_vocula

  blank=$(find "$out/$locale" -name '*.png' -size -10k | wc -l | tr -d ' ')
  [ "$blank" -eq 0 ] || { echo "screenshots: $blank frames came out empty" >&2; exit 1; }

  # Identical frames mean the appearance argument was ignored. Microphone draws
  # a live meter so its two frames always differ, which is why this is asserted
  # per section rather than trusted once.
  for section in $sections; do
    light="$out/$locale/$locale-light-$section.png"
    dark="$out/$locale/$locale-dark-$section.png"
    # `if` and not a command substitution: set -e is inherited into $( ), so
    # cmp's "they differ" exit status killed the subshell before it was read.
    if cmp -s "$light" "$dark"; then
      echo "screenshots: $section is identical in both appearances" >&2
      exit 1
    fi
  done

  echo "  $(find "$out/$locale" -name '*.png' | wc -l | tr -d ' ') screenshots"
done

# The loop quits the app between every frame, so without this the developer is
# left with no menu bar icon and no record key until they notice.
[ ! -d /Applications/Vocula.app ] || open -a /Applications/Vocula.app 2>/dev/null || true
