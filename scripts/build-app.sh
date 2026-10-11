#!/bin/zsh
# macos-26 zsh does not always inherit the system directories.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

# No arguments: ad-hoc signature for CI and local builds. Not a public release.
# --developer-id: tag releases via notarize.yml. Never falls through to ad-hoc.
DEVELOPER_ID_IDENTITY=""
if [[ $# -gt 0 ]]; then
    if [[ "$1" != "--developer-id" ]]; then
        echo "usage: $0 [--developer-id <identity>]" >&2
        exit 2
    fi
    if [[ $# -ne 2 || -z "${2:-}" || "$2" == "-" ]]; then
        echo "build-app.sh: --developer-id requires a Developer ID Application identity. Refusing an ad-hoc signature." >&2
        exit 1
    fi
    DEVELOPER_ID_IDENTITY="$2"
fi

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

APP_DIR="$PROJECT_DIR/build/Ichido.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
mkdir -p "$CONTENTS_DIR/Frameworks"
cp "$PROJECT_DIR/.build/release/VoiceCoachApp" "$MACOS_DIR/VoiceCoachApp"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
chmod +x "$MACOS_DIR/VoiceCoachApp"

if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
    "$PROJECT_DIR/scripts/sign-developer-id.sh" "$DEVELOPER_ID_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi
echo "$APP_DIR"
