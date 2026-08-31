#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app=/Applications/Vocula.app
clean=${1:-}

(cd "$root/App" && xcodegen generate >/dev/null)

if [ "$clean" = "--clean" ]; then
    xcodebuild -project "$root/App/Vocula.xcodeproj" -scheme Vocula \
               -configuration Debug clean >/dev/null
elif [ -n "$clean" ]; then
    echo "usage: $0 [--clean]" >&2
    exit 2
fi

xcodebuild -project "$root/App/Vocula.xcodeproj" -scheme Vocula \
           -configuration Debug build >/dev/null
settings=$(xcodebuild -project "$root/App/Vocula.xcodeproj" -scheme Vocula \
                      -configuration Debug -showBuildSettings 2>/dev/null)
built=$(printf '%s\n' "$settings" |
        awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')/Vocula.app
[ -d "$built" ] || { echo "no built app at $built" >&2; exit 1; }

# Quit first: replacing a bundle under a running process makes macOS kill it with Invalid Page.
osascript -e 'quit app "Vocula"' 2>/dev/null || true
sleep 2
if pgrep -x Vocula >/dev/null; then
    echo "Vocula is still running; refusing to replace it" >&2
    exit 1
fi

# Writing INTO an installed bundle needs App Management on macOS 14, and a denial
# lands part-way through, leaving a nested bundle unsigned. Creating one that is
# not there is allowed.
rm -rf "$app"
if [ -e "$app" ]; then
    echo "cannot replace $app." >&2
    echo "Grant this terminal App Management in System Settings ->" >&2
    echo "Privacy & Security -> App Management, then run this again." >&2
    exit 1
fi
ditto "$built" "$app"

# Verify BEFORE launching: an invalid signature silently costs all three TCC
# grants. --deep too: --strict alone does not descend into the nested bundles.
codesign --verify --deep --strict "$app"
echo "installed build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
                       "$app/Contents/Info.plist")"
open -a "$app"
