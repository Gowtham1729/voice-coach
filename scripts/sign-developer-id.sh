#!/bin/zsh
# Re-sign Ichido.app with a Developer ID Application identity.
# Sparkle is signed inside-out. Downloader.xpc keeps its existing entitlements.
# There is no ad-hoc fallback and no `codesign --deep`.
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEAM_ID="88HMB5SB4X"
ENTITLEMENTS="$PROJECT_DIR/Resources/IchidoDirect.entitlements"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <Developer ID Application identity> [Ichido.app]" >&2
    exit 2
fi

IDENTITY="$1"
APP="${2:-$PROJECT_DIR/build/Ichido.app}"

if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
    echo "A Developer ID Application identity is required. Refusing an ad-hoc signature." >&2
    exit 1
fi

case "$IDENTITY" in
    "Developer ID Application: "*" (${TEAM_ID})")
        ;;
    *)
        echo "Identity must be Developer ID Application for team ${TEAM_ID}." >&2
        exit 1
        ;;
esac

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "Missing entitlements file: $ENTITLEMENTS" >&2
    exit 1
fi

key_count="$(grep -c '<key>' "$ENTITLEMENTS" || true)"
if [[ "$key_count" != "1" ]]; then
    echo "Direct-distribution entitlements must contain exactly one key." >&2
    exit 1
fi
if ! grep -q '<key>com.apple.security.device.audio-input</key>' "$ENTITLEMENTS"; then
    echo "Direct-distribution entitlements must set com.apple.security.device.audio-input." >&2
    exit 1
fi
if ! grep -q '<true/>' "$ENTITLEMENTS"; then
    echo "com.apple.security.device.audio-input must be true." >&2
    exit 1
fi
if grep -q 'com.apple.security.app-sandbox' "$ENTITLEMENTS"; then
    echo "Direct-distribution entitlements must not enable the App Sandbox." >&2
    exit 1
fi
if grep -q 'SUAutomaticallyUpdate' "$PROJECT_DIR/Resources/Info.plist"; then
    echo "SUAutomaticallyUpdate must stay unset." >&2
    exit 1
fi

if [[ ! -d "$APP" ]]; then
    echo "App bundle not found: $APP" >&2
    exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    echo "SUAutomaticallyUpdate must stay unset on the built app." >&2
    exit 1
fi

FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
INSTALLER="$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
DOWNLOADER="$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
AUTOUPDATE="$FRAMEWORK/Versions/B/Autoupdate"
UPDATER="$FRAMEWORK/Versions/B/Updater.app"

for path in "$INSTALLER" "$DOWNLOADER" "$AUTOUPDATE" "$UPDATER" "$FRAMEWORK"; do
    if [[ ! -e "$path" ]]; then
        echo "Missing Sparkle component: $path" >&2
        exit 1
    fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
before="$tmp/downloader-before.plist"
after="$tmp/downloader-after.plist"

read_entitlements() {
    local target="$1"
    local dest="$2"
    if ! /usr/bin/codesign -d --entitlements :- "$target" >"$dest" 2>"$tmp/codesign-entitlements.err"; then
        echo "Unable to read entitlements for $target" >&2
        cat "$tmp/codesign-entitlements.err" >&2
        exit 1
    fi
}

normalize_plist() {
    local src="$1"
    local dest="$2"
    if [[ ! -s "$src" ]]; then
        : >"$dest"
        return
    fi
    /usr/bin/plutil -convert xml1 -o "$dest" "$src"
}

read_entitlements "$DOWNLOADER" "$before"

keychain_args=()
if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then
    keychain_args=(--keychain "$SIGN_KEYCHAIN")
fi

sign_item() {
    /usr/bin/codesign --force --sign "$IDENTITY" "${keychain_args[@]}" --options runtime --timestamp "$@"
}

# Sparkle 2.6+ order. --preserve-metadata=entitlements is only for Downloader.xpc.
# Do not pass --deep: it would replace that XPC signature and drop its entitlements.
sign_item "$INSTALLER"
sign_item --preserve-metadata=entitlements "$DOWNLOADER"
sign_item "$AUTOUPDATE"
sign_item "$UPDATER"
sign_item "$FRAMEWORK"
sign_item --entitlements "$ENTITLEMENTS" "$APP"

read_entitlements "$DOWNLOADER" "$after"
normalize_plist "$before" "$tmp/downloader-before-norm.plist"
normalize_plist "$after" "$tmp/downloader-after-norm.plist"
if ! cmp -s "$tmp/downloader-before-norm.plist" "$tmp/downloader-after-norm.plist"; then
    echo "Downloader.xpc entitlements changed during re-sign." >&2
    diff -u "$tmp/downloader-before-norm.plist" "$tmp/downloader-after-norm.plist" >&2 || true
    exit 1
fi

app_entitlements="$tmp/app.plist"
read_entitlements "$APP" "$app_entitlements"
if ! grep -q 'com.apple.security.device.audio-input' "$app_entitlements"; then
    echo "Signed app is missing com.apple.security.device.audio-input." >&2
    exit 1
fi
if grep -q 'com.apple.security.app-sandbox' "$app_entitlements"; then
    echo "Signed app must not enable the App Sandbox." >&2
    exit 1
fi

require_developer_id() {
    local target="$1"
    local info
    if ! info="$(/usr/bin/codesign -dv --verbose=4 "$target" 2>&1)"; then
        echo "codesign failed to describe $target" >&2
        printf '%s\n' "$info" >&2
        exit 1
    fi
    if printf '%s\n' "$info" | grep -q 'Signature=adhoc'; then
        echo "$target is ad-hoc signed." >&2
        exit 1
    fi
    if ! printf '%s\n' "$info" | grep -q "TeamIdentifier=${TEAM_ID}"; then
        echo "$target is not signed for team ${TEAM_ID}." >&2
        printf '%s\n' "$info" >&2
        exit 1
    fi
    if ! printf '%s\n' "$info" | grep -E -q "Authority=Developer ID Application: .* \\(${TEAM_ID}\\)"; then
        echo "$target is missing a Developer ID Application authority for team ${TEAM_ID}." >&2
        printf '%s\n' "$info" >&2
        exit 1
    fi
    if ! printf '%s\n' "$info" | grep -q 'flags=.*runtime'; then
        echo "$target does not have the hardened runtime enabled." >&2
        printf '%s\n' "$info" >&2
        exit 1
    fi
    if ! printf '%s\n' "$info" | grep -q '^Timestamp='; then
        echo "$target does not have a secure timestamp." >&2
        printf '%s\n' "$info" >&2
        exit 1
    fi
    if ! /usr/bin/codesign --verify --strict --verbose=2 "$target"; then
        echo "codesign verify failed for $target" >&2
        exit 1
    fi
}

for path in "$INSTALLER" "$DOWNLOADER" "$AUTOUPDATE" "$UPDATER" "$FRAMEWORK" "$APP"; do
    require_developer_id "$path"
done
