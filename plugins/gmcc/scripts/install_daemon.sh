#!/bin/bash

# GMCC daemon installer — THE FRONT DOOR for everyone who is not editing the
# daemon's sources.
#
# WHY THIS EXISTS. The plugin ships the daemon's SOURCE (44k lines of Swift plus
# GRDB), and until this script existed every install compiled it. That put a
# cold `swift build -c release` and a hard Xcode-toolchain dependency in front of
# a person whose actual request was "install a Claude Code plugin", and it made a
# fresh install's FIRST SESSION BROKEN BY CONSTRUCTION: no binaries on disk means
# run_mcp.sh exits 1, the pen never registers, and the remediation is a
# multi-minute build followed by a session restart.
#
# So: CI builds the universal binaries once per daemon/VERSION and attaches them
# to a `daemon-v<version>` release; this script fetches them. Source stays in the
# repo because the daemon is developed here — what changed is that compiling it
# is no longer the consumer's job.
#
# THE VERSION FILE IS THE WHOLE CONTRACT. daemon/VERSION is what the plugin pins;
# ${GMCC_ROOT:-$HOME/gmcc}/bin/.gmcc_version is what is installed. Equal means
# there is nothing to do. That replaces the old `find -newer` mtime heuristic,
# which could never once say "up to date" after a plugin update — git stamps every
# checked-out file with the checkout time, so sources always looked newer than the
# binary and every `git pull` forced a full rebuild.
#
# A `+src.<sha>` suffix on the installed stamp means build_daemon.sh put it there
# and a developer owns that bin directory. This script will NOT overwrite it
# without --force: a download must never silently replace someone's local build.
#
# Usage:
#   install_daemon.sh             # install/upgrade to the pinned version if needed
#   install_daemon.sh --check     # report only; exit 1 if an install is needed
#   install_daemon.sh --force     # reinstall even if the stamp already matches
#   install_daemon.sh --build     # skip the download, build from source
#
# Env:
#   GMCC_ROOT                     # runtime root (sandbox-aware, as everywhere)
#   GMCC_DAEMON_RELEASE_REPO      # owner/name to fetch from (default: this repo)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DAEMON_PKG="$GMCC_PLUGIN_DIR/daemon"
RELEASE_REPO="${GMCC_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"

MODE="install"
case "$1" in
    --check) MODE="check" ;;
    --force) MODE="force" ;;
    --build) MODE="build" ;;
    "") ;;
    *) echo "[GMB] install_daemon.sh: unknown flag $1" >&2; exit 2 ;;
esac

if [ ! -f "$DAEMON_PKG/VERSION" ]; then
    echo "[GMB] ERROR: no daemon/VERSION at $DAEMON_PKG — cannot tell what to install" >&2
    exit 1
fi
PINNED="$(cat "$DAEMON_PKG/VERSION")"

# --- runtime root -----------------------------------------------------------
# Same resolution order every GMCC launcher uses: an explicit GMCC_ROOT wins,
# otherwise a repo carrying .gmcc_sandbox selects its snapshot runtime, otherwise
# $HOME/gmcc. Installing prod binaries into a sandbox's bin (or the reverse) is
# exactly what the marker exists to prevent, and an installer that ignored it
# would be the one tool in the set that crosses that line. PARSED as data, never
# sourced — a repo file must not get shell execution here either.
if [ -z "$GMCC_ROOT" ]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.gmcc_sandbox" ]; then
        _sb_root=$(sed -n 's/^export GMCC_ROOT="\(.*\)"$/\1/p' "$REPO_ROOT/.gmcc_sandbox" | head -1)
        [ -n "$_sb_root" ] && GMCC_ROOT="$_sb_root"
    fi
fi
GMCC_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin"
VERSION_STAMP="$GMCC_BIN/.gmcc_version"

INSTALLED="none"
[ -f "$VERSION_STAMP" ] && INSTALLED="$(cat "$VERSION_STAMP")"

have_all_binaries() {
    [ -x "$GMCC_BIN/gmcc_daemon" ] && [ -x "$GMCC_BIN/gmcc_mcp" ] && [ -x "$GMCC_BIN/gmcc_hook" ]
}

# --- delegate to the source build -------------------------------------------
build_from_source() {
    if ! command -v swift >/dev/null 2>&1; then
        cat >&2 <<EOF
[GMB] ERROR: cannot install the daemon.
      No release asset for daemon v$PINNED could be downloaded, and no swift
      toolchain is present to build from source.
      Fix either side:
        - install Xcode command line tools:  xcode-select --install
        - or check the release exists:       https://github.com/$RELEASE_REPO/releases/tag/daemon-v$PINNED
EOF
        exit 1
    fi
    echo "[GMB] building daemon v$PINNED from source..."
    exec bash "$SCRIPT_DIR/build_daemon.sh" --force
}

# --- up-to-date checks ------------------------------------------------------
if [ "$MODE" != "force" ] && [ "$MODE" != "build" ]; then
    case "$INSTALLED" in
        *+src.*)
            # Developer-owned bin. Never clobbered by a download.
            if have_all_binaries; then
                echo "[GMB] daemon $INSTALLED installed (local source build) — leaving it alone"
                echo "      rebuild: bash $SCRIPT_DIR/build_daemon.sh"
                echo "      replace with the released v$PINNED: bash $SCRIPT_DIR/install_daemon.sh --force"
                exit 0
            fi
            ;;
        "$PINNED")
            if have_all_binaries; then
                echo "[GMB] daemon v$PINNED already installed at $GMCC_BIN"
                exit 0
            fi
            ;;
    esac
fi

if [ "$MODE" = "check" ]; then
    if [ "$INSTALLED" = "none" ]; then
        echo "[GMB] daemon not installed — pinned v$PINNED"
    else
        echo "[GMB] daemon $INSTALLED installed, plugin pins v$PINNED"
    fi
    echo "      run: bash $SCRIPT_DIR/install_daemon.sh"
    exit 1
fi

[ "$MODE" = "build" ] && build_from_source

# --- download ---------------------------------------------------------------
ASSET="gmcc-daemon-$PINNED-macos-universal.tar.gz"
BASE="https://github.com/$RELEASE_REPO/releases/download/daemon-v$PINNED"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gmcc-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "[GMB] fetching daemon v$PINNED ($RELEASE_REPO)..."
if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$ASSET" "$BASE/$ASSET" \
   || ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$ASSET.sha256" "$BASE/$ASSET.sha256"; then
    echo "[GMB] download failed for $BASE/$ASSET — falling back to a source build" >&2
    build_from_source
fi

# Checksum before anything is unpacked. The .sha256 sidecar is written by the
# release workflow as `<hash>  <filename>`, so it is verified from the temp dir
# where that filename resolves.
if ! (cd "$TMP" && shasum -a 256 -c "$ASSET.sha256" >/dev/null 2>&1); then
    echo "[GMB] ERROR: checksum mismatch on $ASSET — refusing to install" >&2
    echo "       expected: $(cut -d' ' -f1 < "$TMP/$ASSET.sha256")" >&2
    echo "       actual:   $(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)" >&2
    exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"
for bin in gmcc_daemon gmcc_mcp gmcc_hook; do
    if [ ! -f "$TMP/$bin" ]; then
        echo "[GMB] ERROR: $ASSET does not contain $bin — refusing to install a partial set" >&2
        exit 1
    fi
done

# --- install ----------------------------------------------------------------
# rm before cp: overwriting a signed Mach-O in place leaves the kernel's
# code-signature cache pointing at the old inode contents, and the next exec
# of the binary dies with SIGKILL (exit 137, no output). Fresh inodes only.
# This is the same rule build_daemon.sh follows, and it matters MORE here —
# a download replaces binaries far more often than a developer rebuild does.
mkdir -p "$GMCC_BIN"
# The retired CLI is removed from the runtime bin too: a stale `gm` left on
# disk is a binary that still opens the socket and still writes.
rm -f "$GMCC_BIN/gm"
rm -f "$GMCC_BIN/gmcc_daemon" "$GMCC_BIN/gmcc_mcp" "$GMCC_BIN/gmcc_hook"
for bin in gmcc_daemon gmcc_mcp gmcc_hook; do
    cp "$TMP/$bin" "$GMCC_BIN/$bin"
    chmod +x "$GMCC_BIN/$bin"
done
# curl does not set com.apple.quarantine the way a browser download does, but a
# hand-placed tarball can carry it. Cheap to clear, and a quarantined binary
# fails at exec with a dialog no hook can surface.
xattr -dr com.apple.quarantine "$GMCC_BIN" 2>/dev/null || true

printf '%s\n' "$PINNED" > "$VERSION_STAMP"

echo "[GMB] installed daemon v$PINNED:"
echo "  $GMCC_BIN/gmcc_daemon"
echo "  $GMCC_BIN/gmcc_mcp"
echo "  $GMCC_BIN/gmcc_hook"
echo ""
echo "[GMB] a running daemon (if any) is now stale — retire it: gmcc_hook call SHUTDOWN --json '{}'"
echo "      (the next client autostarts the new one)"
