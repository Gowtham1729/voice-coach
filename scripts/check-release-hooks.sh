#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BINARY="$PROJECT_DIR/build/Ichido.app/Contents/MacOS/VoiceCoachApp"
[[ -f "$BINARY" ]] || { echo "Missing release app binary: $BINARY" >&2; exit 1; }

# Every VOICECOACH_ environment name is a DEBUG-only QA hook, as are the labels
# of the QA take injection UI.
STRINGS_OUTPUT="$(/usr/bin/strings "$BINARY")"

hits="$(print -r -- "$STRINGS_OUTPUT" | /usr/bin/grep -oE 'VOICECOACH_[A-Za-z0-9_]*' | /usr/bin/sort -u || true)"
if [[ -n "$hits" ]]; then
    echo "Release binary contains QA hooks:" >&2
    print -r -- "$hits" >&2
    exit 1
fi
echo "absent: VOICECOACH_*"

for label in "Inject QA take" "QA import failed" "needs a WAV file"; do
    if print -r -- "$STRINGS_OUTPUT" | /usr/bin/grep -F "$label" > /dev/null; then
        echo "Release binary contains DEBUG-only QA text: $label" >&2
        exit 1
    fi
    echo "absent: $label"
done
