#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

APP_CATALOG="$ROOT/App/Vocula/Localizable.xcstrings"
KIT_CATALOG="$ROOT/Sources/VoculaKit/Resources/Localizable.xcstrings"
INFO_CATALOG="$ROOT/App/Vocula/InfoPlist.xcstrings"

DERIVED=$(xcodebuild -project "$ROOT/App/Vocula.xcodeproj" -scheme Vocula \
              -configuration Debug -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ OBJROOT = /{print $2; exit}')
if [ -z "$DERIVED" ] || [ ! -d "$DERIVED" ]; then
    echo "sync-strings: nothing was checked — xcodebuild reported no OBJROOT." >&2
    echo "  Build once first: xcodebuild -project App/Vocula.xcodeproj -scheme Vocula build" >&2
    exit 1
fi

sync_one() {
    local catalog="$1" fragment="$2" label="$3"
    [ -f "$catalog" ] || { echo "sync-strings: $label has no catalog at $catalog" >&2; return 0; }

    local data=()
    while IFS= read -r line; do data+=("$line"); done < <(
        find "$DERIVED" -path "*${fragment}*" -name "*.stringsdata" 2>/dev/null | sort)

    if [ "${#data[@]}" -eq 0 ]; then
        echo "sync-strings: nothing was checked — no .stringsdata under *${fragment}*." >&2
        echo "  SWIFT_EMIT_LOC_STRINGS must be YES and the target must have been built." >&2
        return 1
    fi

    local args=()
    for f in "${data[@]}"; do args+=(--stringsdata "$f"); done
    xcrun xcstringstool sync "$catalog" "${args[@]}"
    echo "sync-strings: $label — ${#data[@]} stringsdata → $(basename "$catalog")"
}

failed=0
# The target fragment pins the TARGET: /Vocula.build/ alone also matches .../Vocula.build/Debug/VoculaKit.build/.
sync_one "$APP_CATALOG" "/Debug/Vocula.build/" "app" || failed=1
sync_one "$KIT_CATALOG" "/Debug/VoculaKit.build/" "kit" || failed=1
[ -f "$INFO_CATALOG" ] && { sync_one "$INFO_CATALOG" "/Debug/Vocula.build/" "InfoPlist" || failed=1; }

exit "$failed"
