#!/bin/bash

# GMCC daemon build + install script — THE DEVELOPER PATH.
#
# Builds the GMCCDaemon Swift package (plugins/gmcc/daemon/) in release mode
# and installs the gmcc_daemon + gmcc_mcp + gmcc_hook binaries into ~/gmcc/bin/.
#
# THIS IS NO LONGER WHAT AN INSTALL RUNS. install_daemon.sh is the front door:
# it fetches the prebuilt universal binaries for the pinned daemon/VERSION and
# only falls back here when there is no release to download and a toolchain is
# present. That split exists because compiling 44k lines of Swift is a
# reasonable thing to ask of the person editing them and an unreasonable thing
# to ask of the person installing a Claude Code plugin.
#
# A build from here stamps the runtime version file with a `+src.<sha>` suffix,
# which install_daemon.sh reads as "a developer owns this bin directory" and
# refuses to overwrite without --force. Your local build never loses to a
# download.
#
# Usage:
#   build_daemon.sh            # rebuild only if sources are newer than the
#                              # installed binaries (find -newer staleness check)
#   build_daemon.sh --force    # always rebuild
#
# ${CLAUDE_PLUGIN_ROOT} is only resolved inside hook/command strings, so —
# like gmcc_session_startup.sh — the plugin root is derived from this script's own
# location with the dirname trick.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DAEMON_PKG="$GMCC_PLUGIN_DIR/daemon"

GMCC_RUNTIME="${GMCC_ROOT:-$HOME/gmcc}"
GMCC_BIN="$GMCC_RUNTIME/bin"
VERSION_STAMP="$GMCC_BIN/.gmcc_version"
PINNED_VERSION="$(cat "$DAEMON_PKG/VERSION" 2>/dev/null || echo unknown)"

if [ ! -f "$DAEMON_PKG/Package.swift" ]; then
    echo "[GMB] ERROR: daemon package not found at $DAEMON_PKG" >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "[GMB] ERROR: swift toolchain not found — install Xcode command line tools" >&2
    exit 1
fi

# --- staleness check --------------------------------------------------------
# Rebuild when either installed binary is missing, or any package source is
# newer than the installed gmcc_daemon.
needs_build=0
if [ "$1" = "--force" ]; then
    needs_build=1
elif [ ! -x "$GMCC_BIN/gmcc_daemon" ] || [ ! -x "$GMCC_BIN/gmcc_mcp" ] || [ ! -x "$GMCC_BIN/gmcc_hook" ]; then
    needs_build=1
elif [ -n "$(find "$DAEMON_PKG/Sources" "$DAEMON_PKG/Package.swift" -newer "$GMCC_BIN/gmcc_daemon" -print -quit 2>/dev/null)" ]; then
    needs_build=1
fi

if [ "$needs_build" -eq 0 ]; then
    echo "[GMB] daemon binaries up to date at $GMCC_BIN"
    exit 0
fi

# --- BuildInfo stamping -----------------------------------------------------
# Generated (gitignored) build identity returned by `gmcc_hook ping` / PING. A dev
# placeholder is written by hand once so bare `swift build` compiles; this
# overwrites it with the real sha + date before every scripted build. The
# heredoc moved to stamp_build_info.sh so CI stamps the identical shape.
bash "$SCRIPT_DIR/stamp_build_info.sh" "$DAEMON_PKG" "$PINNED_VERSION"

# --- build ------------------------------------------------------------------
echo "[GMB] building GMCCDaemon (release)..."
swift build -c release --package-path "$DAEMON_PKG"

BIN_DIR="$(swift build -c release --package-path "$DAEMON_PKG" --show-bin-path)"

# --- install ----------------------------------------------------------------
# rm before cp: overwriting a signed Mach-O in place leaves the kernel's
# code-signature cache pointing at the old inode contents, and the next exec
# of the binary dies with SIGKILL (exit 137, no output). Fresh inodes only.
mkdir -p "$GMCC_BIN"
# The retired CLI is removed from the runtime bin too: a stale `gm` left on
# disk is a binary that still opens the socket and still writes.
rm -f "$GMCC_BIN/gm"
rm -f "$GMCC_BIN/gmcc_daemon" "$GMCC_BIN/gmcc_mcp" "$GMCC_BIN/gmcc_hook"
cp "$BIN_DIR/gmcc_daemon" "$GMCC_BIN/gmcc_daemon"
cp "$BIN_DIR/gmcc_mcp" "$GMCC_BIN/gmcc_mcp"
cp "$BIN_DIR/gmcc_hook" "$GMCC_BIN/gmcc_hook"
chmod +x "$GMCC_BIN/gmcc_daemon" "$GMCC_BIN/gmcc_mcp" "$GMCC_BIN/gmcc_hook"

# --- version stamp ----------------------------------------------------------
# `<pinned>+src.<sha>` — the `+src` marks this bin directory as developer-owned.
# check_daemon_stale.sh sees the suffix and reverts to the mtime staleness check
# (the right check while sources are being edited), and install_daemon.sh sees it
# and declines to replace your build with a download.
BUILD_SHA="$(git -C "$DAEMON_PKG" rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf '%s+src.%s\n' "$PINNED_VERSION" "$BUILD_SHA" > "$VERSION_STAMP"

echo "[GMB] installed $PINNED_VERSION+src.$BUILD_SHA:"
echo "  $GMCC_BIN/gmcc_daemon"
echo "  $GMCC_BIN/gmcc_mcp"
echo "  $GMCC_BIN/gmcc_hook"
echo ""
echo "[GMB] a running daemon (if any) is now stale — restart it (launchctl kickstart, or stop it and let the next client autostart)"
echo "      (the protocol handshake auto-retires it only across a wire-version bump)"
