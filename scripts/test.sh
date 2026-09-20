#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

XCODE_DEVELOPER="/Applications/Xcode.app/Contents/Developer"
if [[ -x "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER"
    SWIFT_BIN="$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
else
    SWIFT_BIN="swift"
fi

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache"

MODE="${1:-unit}"

case "$MODE" in
    unit|--unit)
        [[ $# -gt 0 ]] && shift
        "$SWIFT_BIN" test --disable-sandbox "$@"
        ;;
    self-test|--self-test)
        shift
        "$SWIFT_BIN" run --disable-sandbox VoiceCoachSelfTest "$@"
        ;;
    all|--all)
        shift
        "$SWIFT_BIN" test --disable-sandbox
        "$SWIFT_BIN" run --disable-sandbox VoiceCoachSelfTest "$@"
        ;;
    *)
        echo "usage: $0 [--unit|--self-test|--all] [arguments...]" >&2
        exit 2
        ;;
esac
