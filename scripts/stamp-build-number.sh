#!/bin/sh
set -eu

plist="${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
[ -f "$plist" ] || { echo "warning: no built Info.plist at $plist"; exit 0; }

# --first-parent, so a merge counts once rather than dragging in every commit of the branch.
count=$(git -C "${SRCROOT:-.}/.." rev-list --count --first-parent HEAD 2>/dev/null) || {
    echo "warning: not a git checkout; CFBundleVersion left as authored"
    exit 0
}

if [ "$count" -gt 9999 ]; then
    echo "warning: commit count $count exceeds CFBundleVersion's 4-digit first" \
         "component; leaving the authored value. Switch to a two-component" \
         "number (see this script)."
    exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $count" "$plist"
echo "CFBundleVersion = $count"
