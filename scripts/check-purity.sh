#!/bin/sh
set -e
imports=$(
  # Status captured explicitly: taken from a command substitution it is the last command in the pipeline, so a failing grep is invisible.
  grep -rnE --include='*.swift' \
    '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' Sources/VoculaKit
) || {
  echo "no Swift imports found under Sources/VoculaKit — nothing was checked" >&2
  exit 1
}
offenders=$(
  printf '%s\n' "$imports" |
  awk -F'import[ \t]+' '{
    module = $2
    sub(/^(class|struct|enum|protocol|func|var|let|typealias|precedencegroup)[ \t]+/, "", module)
    sub(/[^A-Za-z0-9_].*$/, "", module)
    if (module != "Foundation") print $0
  }'
)
if [ -n "$offenders" ]; then
  echo "$offenders" >&2
  echo "VoculaKit may import only Foundation" >&2
  exit 1
fi
echo "VoculaKit is pure"
