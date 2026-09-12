#!/bin/bash

# gmk installer — THE FRONT DOOR for everyone who is not editing the sources.
#
# *** WRITTEN, NOT EXERCISED (this prompt). ***
# Installing is out of scope for the reorg prompt that created this file, and it
# is also the only way to exercise the locator rewrite below. CI syntax-checks
# this with `bash -n` and never runs it.
#
# *** THE KNOWN RISK, STATED RATHER THAN HIDDEN. ***
# ${CLAUDE_PLUGIN_ROOT} is the only anchor the Claude Code plugin contract gives
# a hook or a launcher, and it resolves to plugins/gmcc — which now sits BESIDE
# the package tree instead of containing it. Reaching gmk/ therefore means
# climbing ABOVE the plugin root. A marketplace install does clone the whole
# repository, so `git rev-parse --show-toplevel` (and the sibling walk beneath
# it) should resolve — but that is an assumption about install layout, not a
# documented guarantee of the plugin contract. THE LOCATOR REWRITE SHIPS HERE;
# PROVING IT AGAINST A REAL MARKETPLACE INSTALL IS AN EXPLICIT CUTOVER GATE, not
# a gate on the prompt that wrote it. If the climb ever fails, the fix is a
# release download (which needs no repo layout at all), not a deeper walk.
#
# THIS IS A NEW FILE, NOT AN EDIT of plugins/gmcc/scripts/install_daemon.sh.
# That script is FROZEN: it installs the stack that is currently running this
# machine, and it must keep doing so until cutover.
#
# WHY A DOWNLOAD AT ALL. The repo ships ~44k lines of Swift plus GRDB. Compiling
# that is a reasonable thing to ask of the person editing it and an unreasonable
# thing to ask of the person installing a Claude Code plugin, so CI builds the
# universal binaries once per gmk/VERSION, attaches them to a `daemon-v<version>`
# release, and this script fetches and verifies them.
#
# THE VERSION FILE IS THE WHOLE CONTRACT. gmk/VERSION is what the repo pins;
# ${GM_FS_ROOT:-$HOME/gmfs}/bin/.gm_version is what is installed. Equal means
# there is nothing to do. A `+src.<sha>` suffix means build_gm.sh put it there
# and a developer owns that bin directory — a download must never silently
# replace someone's local build, so this script refuses without --force.
#
# Usage:
#   install_gm.sh             # install/upgrade to the pinned version if needed
#   install_gm.sh --check     # report only; exit 1 if an install is needed
#   install_gm.sh --force     # reinstall even if the stamp already matches
#   install_gm.sh --build     # skip the download, build from source
#
# Env:
#   GM_FS_ROOT                # the one filesystem root (default: $HOME/gmfs)
#   GM_DAEMON_RELEASE_REPO    # owner/name to fetch from (default: this repo)

set -e

# --- locate the repo ---------------------------------------------------------
# Same resolution order as build_gm.sh, and for the same reason: gmk/ is above
# the plugin root, so the plugin root cannot be the anchor.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"   # gmk/scripts -> gmk -> repo root
fi
GMK="$REPO_ROOT/gmk"
RELEASE_REPO="${GM_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"
BINARIES="gm_daemon gm_mcp gm_hook"

MODE="install"
case "$1" in
    --check) MODE="check" ;;
    --force) MODE="force" ;;
    --build) MODE="build" ;;
    "") ;;
    *) echo "[GMB] install_gm.sh: unknown flag $1" >&2; exit 2 ;;
esac

if [ ! -f "$GMK/VERSION" ]; then
    echo "[GMB] ERROR: no gmk/VERSION at $GMK — cannot tell what to install" >&2
    exit 1
fi
PINNED="$(cat "$GMK/VERSION")"

# --- runtime root -----------------------------------------------------------
# ONE root variable, which is what makes this a single prefix test rather than a
# two-root reconciliation: an explicit GM_FS_ROOT wins, otherwise a repo
# carrying .gm_sandbox selects its snapshot runtime, otherwise $HOME/gmfs. A
# sandbox is now just a different VALUE of the one variable. The marker is
# PARSED as data, never sourced — a repo file must not get shell execution here.
if [ -z "$GM_FS_ROOT" ]; then
    _repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$_repo" ] && [ -f "$_repo/.gm_sandbox" ]; then
        _sb_root=$(sed -n 's/^export GM_FS_ROOT="\(.*\)"$/\1/p' "$_repo/.gm_sandbox" | head -1)
        [ -n "$_sb_root" ] && GM_FS_ROOT="$_sb_root"
    fi
fi
GM_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin"
VERSION_STAMP="$GM_BIN/.gm_version"

INSTALLED="none"
[ -f "$VERSION_STAMP" ] && INSTALLED="$(cat "$VERSION_STAMP")"

have_all_binaries() {
    for b in $BINARIES; do
        [ -x "$GM_BIN/$b" ] || return 1
    done
    return 0
}

# --- delegate to the source build -------------------------------------------
build_from_source() {
    if ! command -v swift >/dev/null 2>&1; then
        cat >&2 <<EOF
[GMB] ERROR: cannot install.
      No release asset for v$PINNED could be downloaded, and no swift toolchain
      is present to build from source.
      Fix either side:
        - install Xcode command line tools:  xcode-select --install
        - or check the release exists:       https://github.com/$RELEASE_REPO/releases/tag/daemon-v$PINNED
EOF
        exit 1
    fi
    echo "[GMB] building v$PINNED from source..."
    exec bash "$SCRIPT_DIR/build_gm.sh" --force
}

# --- up-to-date checks ------------------------------------------------------
if [ "$MODE" != "force" ] && [ "$MODE" != "build" ]; then
    case "$INSTALLED" in
        *+src.*)
            # Developer-owned bin. Never clobbered by a download.
            if have_all_binaries; then
                echo "[GMB] $INSTALLED installed (local source build) — leaving it alone"
                echo "      rebuild: bash $SCRIPT_DIR/build_gm.sh"
                echo "      replace with the released v$PINNED: bash $SCRIPT_DIR/install_gm.sh --force"
                exit 0
            fi
            ;;
        "$PINNED")
            if have_all_binaries; then
                echo "[GMB] v$PINNED already installed at $GM_BIN"
                exit 0
            fi
            ;;
    esac
fi

if [ "$MODE" = "check" ]; then
    if [ "$INSTALLED" = "none" ]; then
        echo "[GMB] not installed — pinned v$PINNED"
    else
        echo "[GMB] $INSTALLED installed, repo pins v$PINNED"
    fi
    echo "      run: bash $SCRIPT_DIR/install_gm.sh"
    exit 1
fi

[ "$MODE" = "build" ] && build_from_source

# --- download ---------------------------------------------------------------
ASSET="gm-daemon-$PINNED-macos-universal.tar.gz"
BASE="https://github.com/$RELEASE_REPO/releases/download/daemon-v$PINNED"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gm-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "[GMB] fetching v$PINNED ($RELEASE_REPO)..."
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
for b in $BINARIES; do
    if [ ! -f "$TMP/$b" ]; then
        echo "[GMB] ERROR: $ASSET does not contain $b — refusing to install a partial set" >&2
        exit 1
    fi
done

# --- install ----------------------------------------------------------------
# rm before cp: overwriting a signed Mach-O in place leaves the kernel's
# code-signature cache pointing at the old inode contents, and the next exec of
# the binary dies with SIGKILL (exit 137, no output). Fresh inodes only. This
# matters MORE here than on the developer path — a download replaces binaries
# far more often than a rebuild does.
mkdir -p "$GM_BIN"
for b in $BINARIES; do
    rm -f "$GM_BIN/$b"
    cp "$TMP/$b" "$GM_BIN/$b"
    chmod +x "$GM_BIN/$b"
done
# curl does not set com.apple.quarantine the way a browser download does, but a
# hand-placed tarball can carry it. Cheap to clear, and a quarantined binary
# fails at exec with a dialog no hook can surface.
xattr -dr com.apple.quarantine "$GM_BIN" 2>/dev/null || true

printf '%s\n' "$PINNED" > "$VERSION_STAMP"

echo "[GMB] installed v$PINNED:"
for b in $BINARIES; do
    echo "  $GM_BIN/$b"
done
echo ""
echo "[GMB] a running gm_daemon (if any) is now stale — retire it and let the next client autostart it"
