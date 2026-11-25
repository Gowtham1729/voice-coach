#!/bin/zsh
# Installs Ichido's optional Sound comparison engines without any hosting:
# downloads the original weights from Hugging Face, converts them to Core ML with
# tools/sound-comparison/convert.py, and writes them to
# ~/Library/Application Support/VoiceCoach/SoundComparison/<engine>/.
#
#   ./scripts/setup-sound-comparison.sh [lite|full|all]   (default: full)
#
# Needs uv (https://docs.astral.sh/uv/) and git. lite is about 126 MB, full about 519 MB.
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CHOICE="${1:-full}"
case "$CHOICE" in
    lite) ENGINES=(lite) ;;
    full) ENGINES=(full) ;;
    all) ENGINES=(lite full) ;;
    *) print -u2 "usage: $0 [lite|full|all]"; exit 2 ;;
esac

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Sound comparison needs a Mac with Apple silicon."
    exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
    print -u2 "uv is required: brew install uv (or see https://docs.astral.sh/uv/)."
    exit 1
fi

# ZIPA model code (MIT), pinned. Cloned, not vendored.
ZIPA_REPO="https://github.com/lingjzhu/zipa"
ZIPA_COMMIT="21e9e8aa4cc6c130cb05d836a1979886f9245302"

DEST_ROOT="${VOICE_COACH_SOUND_COMPARISON_DIR:-$HOME/Library/Application Support/VoiceCoach/SoundComparison}"
WORK="$(mktemp -d -t ichido-sound-comparison)"
trap 'rm -rf -- "$WORK"' EXIT

print "Fetching ZIPA code at ${ZIPA_COMMIT:0:12}…"
git -C "$WORK" init -q zipa
git -C "$WORK/zipa" fetch -q --depth 1 "$ZIPA_REPO" "$ZIPA_COMMIT"
git -C "$WORK/zipa" checkout -q FETCH_HEAD

mkdir -p "$DEST_ROOT"
for ENGINE in "${ENGINES[@]}"; do
    print "Building the $ENGINE engine…"
    STAGE="$WORK/$ENGINE"
    UV_CACHE_DIR="${UV_CACHE_DIR:-$WORK/uv-cache}" uv run --quiet --no-project --python 3.12 \
        --with torch==2.7.1 --with coremltools==9.0 --with transformers==5.24.0 \
        --with huggingface-hub==2.4.0 --with numpy==2.3.5 --with safetensors==0.8.0 \
        python -I "$PROJECT_DIR/tools/sound-comparison/convert.py" "$ENGINE" "$STAGE" "$WORK/zipa"
    # Replace an existing install only once the new one is complete. The app compiles the
    # packages into compiled/ on first use.
    rm -rf -- "$DEST_ROOT/$ENGINE.previous"
    [[ -d "$DEST_ROOT/$ENGINE" ]] && mv "$DEST_ROOT/$ENGINE" "$DEST_ROOT/$ENGINE.previous"
    mv "$STAGE" "$DEST_ROOT/$ENGINE"
    rm -rf -- "$DEST_ROOT/$ENGINE.previous"
    print "Ichido Sound comparison is ready: $ENGINE ($(du -sh "$DEST_ROOT/$ENGINE" | cut -f1)) in $DEST_ROOT/$ENGINE"
done
