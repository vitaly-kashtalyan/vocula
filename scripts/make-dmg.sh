#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

LAYOUT="Packaging/dmg"
BACKGROUND="$LAYOUT/background.png"
DS_STORE="$LAYOUT/DS_Store"
VOLUME="Vocula"
SCRATCH=""
DEVICE=""
ROOT=""
trap 'if [ -n "$DEVICE" ]; then hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true; fi
      rm -rf "${SCRATCH:-}"' EXIT

fail() { echo "❌ $1" >&2; exit 1; }

usage() {
    cat >&2 <<'EOF'
usage:
  make-dmg.sh <Vocula.app> <out.dmg>   assemble a release image
  make-dmg.sh --capture-layout         re-record the window layout; needs a Mac
                                       with a desktop, writes Packaging/dmg/DS_Store
EOF
    exit 2
}

# DEVICE and ROOT are set in the CALLER's shell, not returned: a command
# substitution runs in a subshell, so an attach that produced a device but no
# mounted volume left the caller with nothing for the trap to detach, and the
# backing file was then deleted from under an attached device.
attach_image() {
    local listing
    listing=$(hdiutil attach "$1" -nobrowse -noverify -noautoopen)
    DEVICE=$(printf '%s\n' "$listing" | awk 'NR==1{ print $1 }')
    ROOT=$(printf '%s\n' "$listing" \
        | awk '/\/Volumes\//{ $1=""; $2=""; sub(/^ +/,""); print; exit }')
    [ -n "$ROOT" ] || fail "hdiutil attach mounted no volume for $1"
}

stage() {
    local app="$1" root="$2"
    ditto "$app" "$root/$(basename "$app")"
    ln -s /Applications "$root/Applications"
    if [ -f "$BACKGROUND" ]; then
        mkdir -p "$root/.background"
        ditto "$BACKGROUND" "$root/.background/background.png"
    fi
}

# A disk image cannot grow once created, and one sized to the app exactly leaves
# no room for .background or the filesystem's own overhead, so hdiutil fails at
# copy time rather than at create time.
size_for() {
    local kilobytes
    kilobytes=$(du -sk "$1" | cut -f1)
    echo $(( kilobytes / 1024 + 60 ))m
}

capture_layout() {
    local app="build/notarize/dd/Build/Products/Release/Vocula.app"
    [ -d "$app" ] || fail "no app at $app — run scripts/notarize.sh first"

    SCRATCH=$(mktemp -d)
    local image="$SCRATCH/layout.dmg"
    hdiutil create -size "$(size_for "$app")" -volname "$VOLUME" -fs HFS+ "$image" >/dev/null
    attach_image "$image"
    local root="$ROOT" volume
    volume=$(basename "$ROOT")
    stage "$app" "$root"

    osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 550}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    if exists file ".background:background.png" then
      set background picture of theViewOptions to file ".background:background.png"
    end if
    set position of item "Vocula.app" of container window to {150, 200}
    set position of item "Applications" of container window to {450, 200}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

    mkdir -p "$LAYOUT"
    ditto "$root/.DS_Store" "$DS_STORE"
    hdiutil detach "$DEVICE" -force >/dev/null
    DEVICE=""
    ROOT=""
    echo "✅ layout recorded: $DS_STORE"
    echo "   Commit it. Every later image is assembled from it with no desktop."
}

assemble() {
    local app="$1" out="$2"
    [ -d "$app" ] || fail "no app at $app"
    [ -f "$DS_STORE" ] || fail "no layout at $DS_STORE — run: $0 --capture-layout"

    SCRATCH=$(mktemp -d)
    local writable="$SCRATCH/rw.dmg"

    hdiutil create -size "$(size_for "$app")" -volname "$VOLUME" -fs HFS+ "$writable" >/dev/null
    attach_image "$writable"
    local root="$ROOT"
    stage "$app" "$root"
    ditto "$DS_STORE" "$root/.DS_Store"
    hdiutil detach "$DEVICE" -force >/dev/null
    DEVICE=""
    ROOT=""

    rm -f "$out"
    hdiutil convert "$writable" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null

    local identity
    identity=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/') || true
    [ -n "${identity:-}" ] || fail "no 'Developer ID Application' certificate to sign the image"
    codesign --sign "$identity" --timestamp "$out"
    codesign --verify --strict "$out"

    echo "✅ $out"
    ls -lh "$out" | awk '{print "   " $5}'
}

case "${1:-}" in
    --capture-layout) capture_layout ;;
    "" | -h | --help) usage ;;
    *) [ $# -eq 2 ] || usage; assemble "$1" "$2" ;;
esac
