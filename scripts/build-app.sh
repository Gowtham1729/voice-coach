#!/bin/zsh
# macos-26 zsh does not always inherit the system directories.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

# No arguments: ad-hoc signed release configuration for CI and local builds.
# --debug: separate ad-hoc signed bundle with QA hooks for copied support dirs.
# --developer-id: tag releases via notarize.yml. Never falls through to ad-hoc.
DEVELOPER_ID_IDENTITY=""
BUILD_CONFIG="release"
if [[ $# -gt 0 ]]; then
    case "$1" in
        --debug)
            [[ $# -eq 1 ]] || { echo "usage: $0 [--debug|--developer-id <identity>]" >&2; exit 2; }
            BUILD_CONFIG="debug"
            ;;
        --developer-id)
            if [[ $# -ne 2 || -z "${2:-}" || "$2" == "-" ]]; then
                echo "build-app.sh: --developer-id requires a Developer ID Application identity. Refusing an ad-hoc signature." >&2
                exit 1
            fi
            DEVELOPER_ID_IDENTITY="$2"
            ;;
        *)
            echo "usage: $0 [--debug|--developer-id <identity>]" >&2
            exit 2
            ;;
    esac
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

"$SWIFT_BIN" build -c "$BUILD_CONFIG" --disable-sandbox

if [[ "$BUILD_CONFIG" == "debug" ]]; then
    APP_DIR="$PROJECT_DIR/build/Ichido-Debug.app"
else
    APP_DIR="$PROJECT_DIR/build/Ichido.app"
fi
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
mkdir -p "$CONTENTS_DIR/Frameworks"
cp "$PROJECT_DIR/.build/$BUILD_CONFIG/VoiceCoachApp" "$MACOS_DIR/VoiceCoachApp"
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
