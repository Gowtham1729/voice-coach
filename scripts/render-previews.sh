#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
XCODE_DEVELOPER="/Applications/Xcode.app/Contents/Developer"
if [[ -x "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
    SWIFT_BIN="$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    export SDKROOT="$XCODE_DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
else
    SWIFT_BIN="swift"
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache"
"$SWIFT_BIN" run --disable-sandbox VoiceCoachSelfTest
"$SWIFT_BIN" run --disable-sandbox VoiceCoachApp --render-previews "$PROJECT_DIR/build/previews"
