#!/bin/zsh
set -euo pipefail

MODE="${1:-run}"
PROJECT_DIR="${0:A:h:h}"
APP_BUNDLE="$PROJECT_DIR/build/Voice Coach.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/VoiceCoachApp"
PROCESS_NAME="VoiceCoachApp"
BUNDLE_ID="com.gowtham.voicecoach"

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
"$PROJECT_DIR/scripts/build-app.sh"

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    debug|--debug)
        lldb -- "$APP_BINARY"
        ;;
    logs|--logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
        ;;
    telemetry|--telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    verify|--verify)
        open_app
        for attempt in {1..20}; do
            if pgrep -x "$PROCESS_NAME" >/dev/null; then
                echo "$PROCESS_NAME is running"
                exit 0
            fi
            sleep 0.25
        done
        echo "$PROCESS_NAME did not start" >&2
        exit 1
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
