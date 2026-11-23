#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
out=Tests/VoculaSlowTests/Fixtures
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$out"

require_voice() {
    voice=$1
    # `say -v` accepts a voice that is not installed, exits 0, and renders in the
    # DEFAULT voice — so a Mac without Zosia would write English audio into a
    # Polish fixture and the language test would read as a model regression.
    if ! say -v '?' | grep -q "^$voice "; then
        echo "voice $voice is not installed — install it in System Settings → Accessibility → Spoken Content" >&2
        exit 1
    fi
}

# Existing fixtures are KEPT: `say` does not render the same bytes across macOS
# releases, and re-rendering one silently changes the audio a test measures —
# a regenerated es-phrase stopped saying "prueba" at peak 0.02. The size is
# printed either way, because `say` interrupted between its two commands leaves
# a SHORT .f32 that every later run then keeps in silence.
render() {
    voice=$1; text=$2; file=$3
    if [ -f "$out/$file.f32" ]; then
        echo "$out/$file.f32 — kept, $(wc -c < "$out/$file.f32" | tr -d ' ') bytes; delete it to re-render"
        return
    fi
    require_voice "$voice"
    say -v "$voice" -o "$scratch/$file.aiff" "$text"
    ffmpeg -v error -y -i "$scratch/$file.aiff" -ar 16000 -ac 1 -f f32le "$out/$file.f32"
    echo "$out/$file.f32 — $(wc -c < "$out/$file.f32" | tr -d ' ') bytes"
}

render Mónica   "Hola, esto es una prueba" es-phrase
render Samantha "Hello, this is a test"    en-phrase
render Zosia    "Jestem szczęśliwy i zadowolony" pl-phrase
render Milena   "Я счастлив и доволен"           ru-phrase

# The start cue is RECORDED into every dictation on built-in speakers, so one
# fixture carries it: 565 ms of Frog, raised to the speech's own peak, ahead of
# the Polish phrase. It is the worst case, not the typical one.
if [ -f "$out/pl-cue.f32" ]; then
    echo "$out/pl-cue.f32 — kept, $(wc -c < "$out/pl-cue.f32" | tr -d ' ') bytes; delete it to re-render"
else
    ffmpeg -v error -y -i /System/Library/Sounds/Frog.aiff -t 0.565 \
           -ar 16000 -ac 1 -af "volume=3.1" -f f32le "$scratch/cue.f32"
    cat "$scratch/cue.f32" "$out/pl-phrase.f32" > "$out/pl-cue.f32"
    echo "$out/pl-cue.f32 — $(wc -c < "$out/pl-cue.f32" | tr -d ' ') bytes"
fi

if [ -f "$out/two-voices.f32" ]; then
    echo "$out/two-voices.f32 — kept, $(wc -c < "$out/two-voices.f32" | tr -d ' ') bytes; delete it to re-render"
else
    require_voice Samantha
    require_voice Daniel
    head -c 57600 /dev/zero > "$scratch/gap.f32"
    : > "$scratch/two-voices.f32"
    turn=0
    for line in \
        "Samantha|Let's go over the release plan for next week before the review on Monday." \
        "Daniel|The build passed on every machine this morning, including the old laptops." \
        "Samantha|Good. Then we can freeze the branch on Wednesday and start the testing." \
        "Daniel|I still need one more day to finish the translations for the settings." \
        "Samantha|Fine, we can move the freeze to Thursday and keep the same release date." \
        "Daniel|Great, I will write the notes and send them to everyone after this call."; do
        say -v "${line%%|*}" -o "$scratch/turn$turn.aiff" "${line#*|}"
        ffmpeg -v error -y -i "$scratch/turn$turn.aiff" -ar 16000 -ac 1 -f f32le "$scratch/turn$turn.f32"
        cat "$scratch/turn$turn.f32" "$scratch/gap.f32" >> "$scratch/two-voices.f32"
        turn=$((turn + 1))
    done
    mv "$scratch/two-voices.f32" "$out/two-voices.f32"
    echo "$out/two-voices.f32 — $(wc -c < "$out/two-voices.f32" | tr -d ' ') bytes"
fi
