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

if [ -d "$app" ]; then
    # rsync --delete, never cp -R: cp MERGES onto an existing bundle and a leftover file breaks the seal.
    rsync -a --delete "$built"/ "$app"/
else
    ditto "$built" "$app"
fi
# Verify BEFORE launching: an invalid signature silently costs all three TCC grants.
codesign --verify --strict "$app"
echo "installed build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
                       "$app/Contents/Info.plist")"
open -a "$app"
