#!/bin/bash

# gmk build + install script — THE DEVELOPER PATH for the gmk/ stack.
#
# *** WRITTEN, NOT EXERCISED (this prompt). ***
# Running this populates ~/gmfs, and populating ~/gmfs is out of scope for the
# reorg prompt that created this file. CI syntax-checks it with `bash -n` and
# NEVER runs it. Do not "helpfully" wire a real build of this script into CI —
# gmk-ci.yml builds and tests the packages directly, which is the thing worth
# gating, and it does so without writing anything outside the workspace.
#
# THIS IS A NEW FILE, NOT AN EDIT of plugins/gmcc/scripts/build_daemon.sh. That
# script is FROZEN and must keep building the currently-installed stack, which
# is what runs this machine until cutover. The two stacks share no binary name,
# no runtime root and no version stamp, which is the whole point of the rename:
# they can coexist on one machine with nothing to collide over.
#
# What it builds — the five gmk packages and the three binaries they produce:
#   gmDaemonSdk            -> gm_hook   (base layer; zero external dependencies)
#   gmDaemon               -> gm_daemon (persistence; the sole GRDB pin)
#   gmMcp                  -> gm_mcp    (the MCP pen)
#   gmUxComponentLibrary   -> library only
#   gmAgententicsSdk       -> library only (compile-only by design; no tests exist)
#
# No stamp_build_info.sh call: the SwiftPM PREBUILD PLUGIN in gmDaemon stamps the
# build identity inside the build graph, so Xcode and every CI job get it for
# free and there is no shell step left to forget.
#
# Usage:
#   build_gm.sh            # rebuild only if sources are newer than the installed binaries
#   build_gm.sh --force    # always rebuild
#
# Env:
#   GM_FS_ROOT             # the one filesystem root (default: $HOME/gmfs)

set -e

# --- locate the repo ---------------------------------------------------------
# git first, because gmk/ sits at the repo root and ${CLAUDE_PLUGIN_ROOT} — the
# only anchor the plugin contract offers — points at plugins/gmcc, which is now
# BELOW the package tree rather than above it. The script-dir walk is the
# fallback for a checkout with no git metadata (a tarball, a vendored copy).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"   # gmk/scripts -> gmk -> repo root
fi
GMK="$REPO_ROOT/gmk"

PACKAGES="gmDaemonSdk gmDaemon gmUxComponentLibrary gmAgententicsSdk gmMcp"
BINARIES="gm_daemon gm_mcp gm_hook"

if [ ! -f "$GMK/gmDaemonSdk/Package.swift" ]; then
    echo "[GMB] ERROR: gmk packages not found under $GMK" >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "[GMB] ERROR: swift toolchain not found — install Xcode command line tools" >&2
    exit 1
fi

GM_RUNTIME="${GM_FS_ROOT:-$HOME/gmfs}"
GM_BIN="$GM_RUNTIME/bin"
VERSION_STAMP="$GM_BIN/.gm_version"
PINNED_VERSION="$(cat "$GMK/VERSION" 2>/dev/null || echo unknown)"

# --- staleness check --------------------------------------------------------
# Rebuild when any installed binary is missing, or any package source is newer
# than the installed gm_daemon.
needs_build=0
if [ "$1" = "--force" ]; then
    needs_build=1
else
    for b in $BINARIES; do
        [ -x "$GM_BIN/$b" ] || needs_build=1
    done
    if [ "$needs_build" -eq 0 ]; then
        for p in $PACKAGES; do
            if [ -n "$(find "$GMK/$p/Sources" "$GMK/$p/Package.swift" \
                        -newer "$GM_BIN/gm_daemon" -print -quit 2>/dev/null)" ]; then
                needs_build=1
                break
            fi
        done
    fi
fi

if [ "$needs_build" -eq 0 ]; then
    echo "[GMB] gm binaries up to date at $GM_BIN"
    exit 0
fi

# --- build ------------------------------------------------------------------
# Each package is built on its own so a failure names the module that broke
# rather than a single opaque graph error — the same property the CI matrix
# buys, kept on the developer path.
for p in $PACKAGES; do
    echo "[GMB] building $p (release)..."
    swift build -c release --package-path "$GMK/$p"
done

SDK_BIN="$(swift build -c release --package-path "$GMK/gmDaemonSdk" --show-bin-path)"
DAEMON_BIN="$(swift build -c release --package-path "$GMK/gmDaemon" --show-bin-path)"
MCP_BIN="$(swift build -c release --package-path "$GMK/gmMcp" --show-bin-path)"

# --- install ----------------------------------------------------------------
# rm before cp: overwriting a signed Mach-O in place leaves the kernel's
# code-signature cache pointing at the old inode contents, and the next exec of
# the binary dies with SIGKILL (exit 137, no output). Fresh inodes only.
mkdir -p "$GM_BIN"
for b in $BINARIES; do
    rm -f "$GM_BIN/$b"
done
cp "$DAEMON_BIN/gm_daemon" "$GM_BIN/gm_daemon"
cp "$MCP_BIN/gm_mcp"       "$GM_BIN/gm_mcp"
cp "$SDK_BIN/gm_hook"      "$GM_BIN/gm_hook"
for b in $BINARIES; do
    chmod +x "$GM_BIN/$b"
done

# --- version stamp ----------------------------------------------------------
# `<pinned>+src.<sha>` — the `+src` marks this bin directory as developer-owned,
# which install_gm.sh reads as "do not replace this with a download".
BUILD_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf '%s+src.%s\n' "$PINNED_VERSION" "$BUILD_SHA" > "$VERSION_STAMP"

echo "[GMB] installed $PINNED_VERSION+src.$BUILD_SHA:"
for b in $BINARIES; do
    echo "  $GM_BIN/$b"
done
echo ""
echo "[GMB] a running gm_daemon (if any) is now stale — retire it and let the next client autostart it"
