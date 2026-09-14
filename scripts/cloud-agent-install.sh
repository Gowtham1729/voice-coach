#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the Voice Coach Swift package.
#
# Voice Coach ships a macOS studio app (VoiceCoachApp) built on SwiftUI, AppKit,
# AVFoundation, and Metal that only builds and runs on macOS. On the Linux Cloud
# Agent this script provisions the Swift toolchain and builds the cross-platform
# targets: the VoiceCoachCore analysis library and the VoiceCoachSelfTest
# executable, which together cover the DSP/report pipeline.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="$(uname -m)"
SWIFTLY_HOME="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
SWIFTLY_ENV="$SWIFTLY_HOME/env.sh"

install_system_deps() {
    command -v apt-get >/dev/null 2>&1 || return 0
    local SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 && SUDO="sudo" || return 0
    fi
    $SUDO apt-get update -qq
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq \
        binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
        libgcc-13-dev libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev \
        pkg-config tzdata unzip zlib1g-dev libncurses-dev curl >/dev/null
}

install_swift() {
    if [ ! -f "$SWIFTLY_ENV" ]; then
        local tmp
        tmp="$(mktemp -d)"
        curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz" \
            -o "$tmp/swiftly.tar.gz"
        tar -C "$tmp" -zxf "$tmp/swiftly.tar.gz"
        "$tmp/swiftly" init --quiet-shell-followup --assume-yes
        rm -rf "$tmp"
    fi
    # shellcheck source=/dev/null
    . "$SWIFTLY_ENV"
    if ! swift --version >/dev/null 2>&1; then
        swiftly install --assume-yes latest
        # shellcheck source=/dev/null
        . "$SWIFTLY_ENV"
    fi
}

install_system_deps
install_swift

swift --version
# VoiceCoachApp is macOS-only (SwiftUI/AppKit/Metal); build the Linux-buildable
# product only. Building the product (not just the target) links the executable
# so it is ready to run.
swift build --product VoiceCoachSelfTest
echo "Voice Coach Cloud Agent environment ready."
