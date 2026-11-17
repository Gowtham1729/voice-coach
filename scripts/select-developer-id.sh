#!/bin/zsh
# Read `security find-identity -v -p codesigning` text on stdin.
# Print the one Developer ID Application identity for the given Team ID.
# The certificate common name comes from that text. This script does not invent one.
# macos-26 zsh does not always inherit the system directories.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
    echo "usage: $0 <team-id>" >&2
    exit 2
fi

TEAM_ID="$1"
identities="$(cat)"
matches="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application: .* ('"$TEAM_ID"')\)".*/\1/p' | sed '/^$/d')"
count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"

if [[ "$count" != "1" ]]; then
    echo "Expected exactly one Developer ID Application identity for team ${TEAM_ID}, found ${count}." >&2
    echo "Refusing to invent a certificate name or fall back to an ad-hoc signature." >&2
    if [[ -n "$identities" ]]; then
        echo "Identities:" >&2
        printf '%s\n' "$identities" >&2
    fi
    exit 1
fi

identity="$matches"
case "$identity" in
    -)
        echo "Refusing an ad-hoc signature." >&2
        exit 1
        ;;
    "Developer ID Application: "*" (${TEAM_ID})")
        ;;
    *)
        echo "Refusing identity that is not Developer ID Application for team ${TEAM_ID}." >&2
        exit 1
        ;;
esac

printf '%s\n' "$identity"
