#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_CODE="${1:-}"
if [ -z "$LANG_CODE" ]; then
    echo "usage: $0 <locale>   e.g. $0 ru" >&2
    exit 1
fi

catalogs=(App/Vocula/Localizable.xcstrings
          Sources/VoculaKit/Resources/Localizable.xcstrings
          App/Vocula/InfoPlist.xcstrings)

count=$(jq -s --arg l "$LANG_CODE" '
    [.[] | .strings | to_entries[] | select((.value.localizations // {})[$l] != null)] | length' \
    "${catalogs[@]}")
if [ "$count" -eq 0 ]; then
    echo "review: nothing was checked - no entries for locale $LANG_CODE" >&2
    exit 1
fi

echo "# Review — $LANG_CODE"
echo
echo "$count strings. Everything here is a machine draft; nothing ships until it"
echo "is read. The line under each key is why the words are what they are."
echo
echo "Marks: **P** the sentence is a promise about the product · **A** the term"
echo "is Apple's and must match that Mac · **L** the string is drawn on the indicator strip, which clips ·"
echo "**N** never translated."
echo

jq -rs --arg l "$LANG_CODE" '
    def value: if .stringUnit then .stringUnit.value
               else ((.variations.plural // {}) | to_entries
                     | map("  \(.key): \(.value.stringUnit.value)") | join("\n"))
               end;
    def marks(c):
        [ (if (c | test("promise|privacy|PRIVACY|must keep")) then "P" else empty end),
          (if (c | test("macOS|Apple|pane")) then "A" else empty end),
          (if (c | test("clamps at three lines")) then "L" else empty end),
          (if (c | test("never translated|not translated|NEVER")) then "N" else empty end) ]
        | unique | if length == 0 then "" else " **[" + join("") + "]**" end;
    [ .[] | .strings | to_entries[] | select((.value.localizations // {})[$l] != null) ]
    | map({ key: .key,
            group: (.key | split(".")[0]),
            comment: (.value.comment // ""),
            en: ((.value.localizations.en // {}) | value),
            tr: ((.value.localizations[$l]) | value) })
    | group_by(.group) | .[]
    | "## \(.[0].group)\n" + ( map(
        "### `\(.key)`" + marks(.comment) + "\n" +
        (if .comment == "" then "" else "_\(.comment)_\n\n" end) +
        "- en: \(.en)\n- " + $l + ": \(.tr)\n"
      ) | join("\n") )
' "${catalogs[@]}"
