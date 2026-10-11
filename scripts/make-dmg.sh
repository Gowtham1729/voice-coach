#!/bin/bash
# Build a disk image that opens with Ichido beside an Applications drop target.
# The image is not signed or notarized here. The notarize workflow does that
# after this script returns, and Sparkle keeps using the zip.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
set -euo pipefail

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    echo "usage: $0 <Ichido.app> <output.dmg>" >&2
    exit 2
fi

APP="$1"
OUTPUT="$2"
APP_NAME="$(basename "$APP")"
VOLUME_NAME="Ichido"
BACKGROUND="$(cd "$(dirname "$0")/.." && pwd)/Resources/dmg-background.png"
WIN_X=200
WIN_Y=120
WIN_W=660
WIN_H=400

if [[ "$APP_NAME" != "Ichido.app" || ! -d "$APP" ]]; then
    echo "Expected an Ichido.app bundle, got: ${APP}" >&2
    exit 1
fi
if [[ ! -s "$BACKGROUND" ]]; then
    echo "Missing disk-image background: ${BACKGROUND}" >&2
    exit 1
fi
if ! command -v hdiutil >/dev/null 2>&1 || ! command -v osascript >/dev/null 2>&1; then
    echo "make-dmg.sh needs macOS hdiutil and Finder." >&2
    exit 1
fi

bg_width="$(sips -g pixelWidth "$BACKGROUND" | awk '/pixelWidth/ { print $2 }')"
bg_height="$(sips -g pixelHeight "$BACKGROUND" | awk '/pixelHeight/ { print $2 }')"
if [[ "$bg_width" != "$WIN_W" || "$bg_height" != "$WIN_H" ]]; then
    echo "Background must be ${WIN_W}x${WIN_H}, got ${bg_width}x${bg_height}." >&2
    exit 1
fi

WORK="$(mktemp -d)"
RW_IMAGE="$WORK/ichido-rw.dmg"
STAGE="$WORK/stage"
APPLESCRIPT="$WORK/layout.applescript"
DEV_NAME=""

cleanup() {
    if [[ -n "$DEV_NAME" ]]; then
        hdiutil detach "$DEV_NAME" >/dev/null 2>&1 || hdiutil detach -force "$DEV_NAME" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME"

hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_IMAGE" >/dev/null
min_mb="$(hdiutil resize -limits "$RW_IMAGE" | awk 'NR==1 { print int($1 / 2048 + 1) }')"
if [[ -z "$min_mb" || "$min_mb" == "0" ]]; then
    echo "Could not measure the disk image." >&2
    exit 1
fi
hdiutil resize -size "$((min_mb + 32))m" "$RW_IMAGE" >/dev/null

attach_log="$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse "$RW_IMAGE")"
printf '%s\n' "$attach_log"
DEV_NAME="$(printf '%s\n' "$attach_log" | awk '/Apple_HFS/ { print $1; exit }')"
MOUNT_DIR="$(printf '%s\n' "$attach_log" | awk '/Apple_HFS/ { print $3; exit }')"
if [[ -z "$DEV_NAME" || -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "Could not mount the disk image." >&2
    exit 1
fi

mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND" "$MOUNT_DIR/.background/background.png"
ln -s /Applications "$MOUNT_DIR/Applications"
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" || true
        SetFile -a C "$MOUNT_DIR" || true
    fi
fi

DISK_NAME="$(basename "$MOUNT_DIR")"
cat > "$APPLESCRIPT" <<EOF
on run argv
    set diskName to item 1 of argv
    set mountDir to item 2 of argv
    tell application "Finder"
        tell disk diskName
            open
            set theXOrigin to ${WIN_X}
            set theYOrigin to ${WIN_Y}
            set theWidth to ${WIN_W}
            set theHeight to ${WIN_H}
            set theBottomRightX to (theXOrigin + theWidth)
            set theBottomRightY to (theYOrigin + theHeight)
            set dsStore to quoted form of (mountDir & "/.DS_Store")
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
                set position of every item to {theBottomRightX + 100, 100}
            end tell
            set opts to the icon view options of container window
            tell opts
                set icon size to 128
                set text size to 16
                set arrangement to not arranged
            end tell
            set background picture of opts to file ".background:background.png"
            set position of item "Ichido.app" to {180, 190}
            set position of item "Applications" to {480, 190}
            set the extension hidden of item "Ichido.app" to true
            close
            open
            delay 1
            tell container window
                set statusbar visible to false
                set the bounds to {theXOrigin, theYOrigin, theBottomRightX - 10, theBottomRightY - 10}
            end tell
            delay 1
            tell container window
                set statusbar visible to false
                set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
            end tell
            delay 3
            set waitTime to 0
            repeat
                delay 1
                set waitTime to waitTime + 1
                if (do shell script "[ -f " & dsStore & " ]; echo \$?") = "0" then exit repeat
                if waitTime > 20 then error "Finder did not write the disk image window"
            end repeat
        end tell
    end tell
end run
EOF

# Finder sometimes answers -1728 ("Can't get disk") immediately after attach.
sleep 2
layout_ok=0
for attempt in 1 2 3; do
    if /usr/bin/osascript "$APPLESCRIPT" "$DISK_NAME" "$MOUNT_DIR"; then
        layout_ok=1
        break
    fi
    if [[ "$attempt" -lt 3 ]]; then
        sleep $((attempt * 2))
    fi
done
if [[ "$layout_ok" -ne 1 ]]; then
    echo "Finder did not lay out Ichido beside Applications." >&2
    exit 1
fi
sleep 4

if [[ "$(uname -m)" == "arm64" ]]; then
    bless --folder "$MOUNT_DIR" || true
else
    bless --folder "$MOUNT_DIR" --openfolder "$MOUNT_DIR" || true
fi
rm -rf "$MOUNT_DIR/.fseventsd" || true

sync
detach_ok=0
for attempt in 1 2 3 4 5; do
    if hdiutil detach "$DEV_NAME"; then
        detach_ok=1
        DEV_NAME=""
        break
    fi
    sleep $((attempt * 2))
done
if [[ "$detach_ok" -ne 1 ]]; then
    hdiutil detach -force "$DEV_NAME"
    DEV_NAME=""
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT" "${OUTPUT}.dmg"
hdiutil convert "$RW_IMAGE" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" >/dev/null
if [[ ! -s "$OUTPUT" && -s "${OUTPUT}.dmg" ]]; then
    mv "${OUTPUT}.dmg" "$OUTPUT"
fi
test -s "$OUTPUT"
echo "$OUTPUT"
