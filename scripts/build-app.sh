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

"$SWIFT_BIN" build -c release --disable-sandbox

APP_DIR="$PROJECT_DIR/build/Voice Coach.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/release/VoiceCoachApp" "$MACOS_DIR/VoiceCoachApp"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod +x "$MACOS_DIR/VoiceCoachApp"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
