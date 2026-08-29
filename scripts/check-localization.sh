#!/bin/bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

SHIPPING_FILE="$ROOT/Localization/shipping.txt"
shipping=""
if [ -f "$SHIPPING_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ""|\#*) continue ;; esac
        shipping="$shipping $line"
    done < "$SHIPPING_FILE"
fi

if [ ! -d "$ROOT" ]; then
    echo "localization: nothing was checked — no such root: $ROOT" >&2
    exit 1
fi

catalogs=()
while IFS= read -r line; do catalogs+=("$line"); done < <(
    find "$ROOT" -name "*.xcstrings" -not -path "*/.build/*" 2>/dev/null | sort)

if [ "${#catalogs[@]}" -eq 0 ]; then
    echo "localization: 0 catalogs, 0 keys"
    echo "localization: nothing was checked — no .xcstrings under $ROOT" >&2
    exit 1
fi

total_keys=0
problems=0
regions_seen=""

for catalog in "${catalogs[@]}"; do
    if ! jq -e . "$catalog" >/dev/null 2>&1; then
        echo "localization: nothing was checked — $catalog will not parse" >&2
        exit 1
    fi

    source_language=$(jq -r '.sourceLanguage // "en"' "$catalog")
    keys=$(jq -r '.strings | length' "$catalog")
    total_keys=$((total_keys + keys))

    while IFS= read -r region; do
        [ -z "$region" ] && continue
        case " $regions_seen " in *" $region "*) ;; *) regions_seen="$regions_seen $region" ;; esac
    done < <(jq -r '[.strings[].localizations // {} | keys[]] | unique[]' "$catalog")

    missing_comment=$(jq -r --arg src "$source_language" '
        .strings | to_entries
        | map(select((.value.shouldTranslate // true) and ((.value.comment // "") == "")))
        | map(.key) | .[]' "$catalog")
    if [ -n "$missing_comment" ]; then
        while IFS= read -r key; do
            echo "localization: $catalog: \"$key\" has no comment" >&2
            problems=$((problems + 1))
        done <<< "$missing_comment"
    fi

    unreviewed=$(jq -r --arg src "$source_language" '
        .strings | to_entries | map(
            .key as $k | .value.localizations // {} | to_entries
            | map(select(.key != $src))
            | map(
                .key as $lang
                | [ (.value.stringUnit.state // empty),
                    ((.value.variations.plural // {}) | to_entries | map(.value.stringUnit.state // "missing"))[]
                  ]
                | map(select(. != "translated"))
                | map("\($k) [\($lang)] \(.)")[]
              ) | .[]
        ) | .[]' "$catalog")
    if [ -n "$unreviewed" ]; then
        while IFS= read -r line; do
            lang=$(printf '%s' "$line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
            case " $shipping " in
                *" $lang "*)
                    echo "localization: $catalog: $line" >&2
                    problems=$((problems + 1)) ;;
                *)
                    echo "localization: draft $lang: $line" ;;
            esac
        done <<< "$unreviewed"
    fi

    for lang in $shipping; do
        [ "$lang" = "$source_language" ] && continue
        absent=$(jq -r --arg r "$lang" '
            .strings | to_entries
            | map(select((.value.shouldTranslate // true)
                         and ((.value.localizations // {})[$r] == null)))
            | map("\(.key) [\($r)] has no translation at all")[]' "$catalog")
        if [ -n "$absent" ]; then
            while IFS= read -r line; do
                echo "localization: $catalog: $line" >&2
                problems=$((problems + 1))
            done <<< "$absent"
        fi
    done

    mismatched=$(jq -r --arg src "$source_language" '
        def specs: [match("%%|%[0-9]*\\$?[@a-zA-Z]+"; "g").string] | sort;
        def variants:
            if .stringUnit then [.stringUnit.value // ""]
            else [((.variations.plural // {}) | to_entries[] | .value.stringUnit.value // "")]
            end;
        def isFlat: (.stringUnit != null);
        .strings | to_entries | map(
            .key as $k
            | (.value.localizations // {}) as $l
            | ($l[$src] // {}) as $source
            | ($source | variants) as $sourceValues
            | (if ($sourceValues | length) == 0 then [] else ($sourceValues[0] | specs) end) as $exact
            | ([$sourceValues[] | specs[]] | unique) as $allowed
            | ($source | isFlat) as $sourceFlat
            | $l | to_entries | map(select(.key != $src))
            | map(
                .key as $lang
                | .value as $target
                | ($target | variants)
                | map(select(
                    if $sourceFlat and ($target | isFlat)
                    then (. | specs) != $exact
                    else ((. | specs) - $allowed) != []
                    end))
                | map("\($k) [\($lang)] format specifiers differ from \($src)")[]
              ) | .[]
        ) | .[]' "$catalog")
    if [ -n "$mismatched" ]; then
        while IFS= read -r line; do
            echo "localization: $catalog: $line" >&2
            problems=$((problems + 1))
        done <<< "$mismatched"
    fi

    budgeted=$(jq -r '
        .strings | to_entries[]
        | select((.value.comment // "") | test("max-length"))
        | .key' "$catalog")
    if [ -n "$budgeted" ]; then
        while IFS= read -r key; do
            echo "localization: $catalog: \"$key\" carries a max-length: marker, which nothing counts — say where it is drawn instead" >&2
            problems=$((problems + 1))
        done <<< "$budgeted"
    fi

    strayed=$(jq -r '
        .strings | to_entries[] as $e
        | ($e.value.localizations // {}) | to_entries[]
        | select(.key | test("^(en|de|es|fr|it|pl|pt-BR)$"))
        | .key as $lang
        | [ .value.stringUnit.value // empty ]
          + [ (.value.variations // {}) | .. | .stringUnit? // empty | .value // empty ]
        | .[]
        | select(test("[а-яА-ЯёЁїЇієІЄґҐ]"))
        | "\($e.key) [\($lang)] holds Cyrillic: \(.)"' "$catalog")
    if [ -n "$strayed" ]; then
        while IFS= read -r line; do
            echo "localization: $catalog: $line" >&2
            problems=$((problems + 1))
        done <<< "$strayed"
    fi

    leaked=$(jq -r '
        .strings | keys[]
        | select(test("^VOC-[A-Z]+-[0-9][0-9]$") or test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))' "$catalog")
    if [ -n "$leaked" ]; then
        while IFS= read -r key; do
            echo "localization: $catalog: \"$key\" is data, not copy" >&2
            problems=$((problems + 1))
        done <<< "$leaked"
    fi
done

region_count=$(echo "$regions_seen" | wc -w | tr -d ' ')
echo "localization: ${#catalogs[@]} catalogs, $total_keys keys, $region_count regions"

for region in $regions_seen; do
    missing=0
    for catalog in "${catalogs[@]}"; do
        src=$(jq -r '.sourceLanguage // "en"' "$catalog")
        [ "$region" = "$src" ] && continue
        n=$(jq -r --arg r "$region" '[.strings[] | select((.localizations // {})[$r] == null)] | length' "$catalog")
        missing=$((missing + n))
    done
    case " $shipping " in
        *" $region "*) state="shipping" ;;
        *) state="draft" ;;
    esac
    echo "localization: $region ($state) — $missing keys not translated"
done

if [ "$total_keys" -eq 0 ]; then
    echo "localization: nothing was checked — every catalog holds zero keys" >&2
    exit 1
fi

# A catalog has ONE legitimate writer, `xcrun xcstringstool`, and it separates
# key from value as `"key" : value`. Every other JSON tool writes `"key":` with
# no space, so one pass through a formatter or a jq filter rewrites the whole
# file — and the next sync flips all of it back, burying a one-key change in a
# ten-thousand-line diff. Only the separator is checked: reproducing the whole
# serialisation needs xcstringstool's own byte order, and plutil's sort is
# case-insensitive where xcstringstool's is not.
foreign=0
for catalog in "${catalogs[@]}"; do
    if grep -qE '^[[:space:]]*"[^"]*":[[:space:]]' "$catalog"; then
        echo "localization: $(basename "$(dirname "$catalog")")/$(basename "$catalog") was written by something other than xcstringstool — the next sync would rewrite every line" >&2
        foreign=$((foreign + 1))
        problems=$((problems + 1))
    fi
done
echo "localization: $((${#catalogs[@]} - foreign)) of ${#catalogs[@]} catalogs in xcstringstool's format"

[ "$problems" -eq 0 ] || exit 1
