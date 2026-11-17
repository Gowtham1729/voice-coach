#!/bin/bash
# Submit one already-signed file to notarytool and wait until Apple accepts it.
# Credentials come from the environment: NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER.
# NOTARY_KEY is the App Store Connect API .p8 PEM, or base64 of that file.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
set -euo pipefail

if [[ $# -ne 1 || ! -s "${1:-}" ]]; then
    echo "usage: $0 <file>" >&2
    exit 2
fi

FILE="$1"
for name in NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER; do
    if [[ -z "${!name:-}" ]]; then
        echo "Missing ${name}." >&2
        exit 1
    fi
done

umask 077
P8="$(mktemp)"
submit_log="$(mktemp)"
cleanup() {
    rm -f "$P8" "$submit_log"
}
trap cleanup EXIT

if [[ "$NOTARY_KEY" == *"PRIVATE KEY"* ]]; then
    printf '%s\n' "$NOTARY_KEY" > "$P8"
else
    if ! printf '%s' "$NOTARY_KEY" | tr -d '[:space:]' | base64 -D > "$P8"; then
        echo "NOTARY_KEY is neither a .p8 PEM nor valid base64." >&2
        exit 1
    fi
fi
if ! grep -q "PRIVATE KEY" "$P8"; then
    echo "NOTARY_KEY must be the App Store Connect API .p8 PEM, or base64 of that file." >&2
    exit 1
fi

set +e
xcrun notarytool submit "$FILE" \
    --key "$P8" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait \
    --timeout 120m \
    | tee "$submit_log"
status=${PIPESTATUS[0]}
set -e
if [[ "$status" -ne 0 ]]; then
    submission_id="$(sed -n 's/^[[:space:]]*id:[[:space:]]*//p' "$submit_log")"
    submission_id="${submission_id%%$'\n'*}"
    if [[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        xcrun notarytool log "$submission_id" \
            --key "$P8" \
            --key-id "$NOTARY_KEY_ID" \
            --issuer "$NOTARY_ISSUER" || true
    fi
    exit "$status"
fi
