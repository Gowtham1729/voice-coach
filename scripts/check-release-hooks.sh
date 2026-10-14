#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BINARY="$PROJECT_DIR/build/Ichido.app/Contents/MacOS/VoiceCoachApp"
[[ -f "$BINARY" ]] || { echo "Missing release app binary: $BINARY" >&2; exit 1; }

for hook in VOICECOACH_INJECT_TAKE VOICECOACH_REPLAY_LOG VOICECOACH_SUPPORT_DIR; do
    if /usr/bin/strings "$BINARY" | /usr/bin/grep -F "$hook" > /dev/null; then
        echo "Release binary contains QA hook: $hook" >&2
        exit 1
    fi
    echo "absent: $hook"
done
