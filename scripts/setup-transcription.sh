#!/bin/zsh
set -euo pipefail

MODEL_ID="nvidia/parakeet-tdt-0.6b-v3"
RUNTIME_BIN="$(command -v nemo-speech || true)"

if [[ -z "$RUNTIME_BIN" ]]; then
    SETUP_SCRIPT="$(mktemp -t voice-coach-nemo-setup)"
    trap 'rm -f -- "$SETUP_SCRIPT"' EXIT
    curl -fsSL "https://github.com/NVIDIA/NeMo-Speech.cpp/raw/main/scripts/install.sh" \
        -o "$SETUP_SCRIPT"
    /bin/sh "$SETUP_SCRIPT"

    RUNTIME_BIN="$(command -v nemo-speech || true)"
    if [[ -z "$RUNTIME_BIN" ]]; then
        USER_DIRECTORY="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
        if [[ -x "$USER_DIRECTORY/.local/bin/nemo-speech" ]]; then
            RUNTIME_BIN="$USER_DIRECTORY/.local/bin/nemo-speech"
        fi
    fi
fi

if [[ -z "$RUNTIME_BIN" || ! -x "$RUNTIME_BIN" ]]; then
    print -u2 "nemo-speech was installed but its executable could not be found. Open a new terminal and rerun this script."
    exit 1
fi

"$RUNTIME_BIN" pull "$MODEL_ID"
"$RUNTIME_BIN" doctor
print "Voice Coach local transcription is ready: $MODEL_ID"
