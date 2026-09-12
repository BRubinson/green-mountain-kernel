#!/bin/bash
#
# install_gm.sh — THE FRONT DOOR for everyone who is not editing the sources.
#
# Fetches the latest published `daemon-v*` release, verifies its checksum, stages
# it under the release store and activates it.
#
# ── WHY THIS LIVES IN THE PLUGIN AND NOT IN gmk/scripts ──────────────────────
#
# Because of who runs it. Somebody with a CHECKOUT builds: they have the sources
# and `rebuild_local.sh` is strictly better for them. Somebody with only the
# PLUGIN downloads — and the plugin cache is all they have.
#
# That is not a style preference, it is a hard constraint that was measured. A
# marketplace install materialises `plugins/gmcc/` alone, with no `gmk/` beside
# it and no git metadata of its own. An installer that tried to climb out of the
# cache to find the repo would run `git rev-parse --show-toplevel` and, on a
# machine whose $HOME is itself a git repository, get a confident WRONG answer
# pointing at the home directory. There is no reliable climb, so this script does
# not attempt one: it needs no repo, reads no VERSION file from disk, and asks
# GitHub what the newest release is.
#
# ── WHY "LATEST" RATHER THAN A PIN ───────────────────────────────────────────
#
# The plugin carries no runtime version. If it did, that number would be a second
# thing to bump on every release and it could silently disagree with gmk/VERSION.
# Asking for the newest `daemon-v*` release means the plugin cannot drift from
# what was actually published.
#
# TAG NAMESPACE MATTERS HERE. The monorepo ships two independently versioned
# artifacts, `daemon-v*` and `gmvibes-v*`, so GitHub's own "latest release" is
# the wrong question — it would happily hand back an app release. This filters
# by tag prefix.
#
# Usage:
#   install_gm.sh                   # install/upgrade to the newest daemon release
#   install_gm.sh --check           # report only; exit 1 if an install is needed
#   install_gm.sh --force           # reinstall even if that version is active
#   install_gm.sh --version 50.0.1  # install one specific version
#
# Env:
#   GM_FS_ROOT                      # the one filesystem root (default: $HOME/gmfs)
#   GM_DAEMON_RELEASE_REPO          # owner/name to fetch from

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_releases.sh
. "$SCRIPT_DIR/gm_releases.sh"

RELEASE_REPO="${GM_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"
API="https://api.github.com/repos/$RELEASE_REPO"

MODE="install"
WANT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check" ;;
        --force)   MODE="force" ;;
        --version) shift; WANT="$1"; [ -n "$WANT" ] || { echo "[GMB] --version needs a value" >&2; exit 2; } ;;
        "") ;;
        *) echo "[GMB] install_gm.sh: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done

gm_resolve_fs_root
INSTALLED="$(gm_installed_version)"

# ── Resolve which version to install ─────────────────────────────────────────
#
# Parsed with grep/sed rather than jq: jq is not a dependency anywhere else on
# this path and an installer that fails on a missing JSON parser is an installer
# that fails for the exact users it exists to serve. The releases list comes back
# newest-first, so the first daemon-v tag in it is the newest daemon release.
resolve_latest() {
    curl -fsSL --retry 2 --connect-timeout 15 "$API/releases?per_page=100" 2>/dev/null \
        | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"daemon-v[^"]*"' \
        | head -1 \
        | sed -e 's/.*"\(daemon-v[^"]*\)"/\1/' -e 's/^daemon-v//'
}

if [ -n "$WANT" ]; then
    VERSION="$WANT"
else
    echo "[GMB] asking $RELEASE_REPO for the newest daemon release..."
    VERSION="$(resolve_latest || true)"
    if [ -z "$VERSION" ]; then
        cat >&2 <<EOF
[GMB] ERROR: no published daemon-v* release found on $RELEASE_REPO.

      Nothing has been released yet, or the network is unreachable.

      If you have a checkout of the repository, build instead — it needs no
      release at all:

          bash gmk/scripts/rebuild_local.sh

      Otherwise check: https://github.com/$RELEASE_REPO/releases
EOF
        exit 1
    fi
fi

TAG="daemon-v$VERSION"
ASSET="gm-daemon-$VERSION-macos-universal.tar.gz"
BASE="https://github.com/$RELEASE_REPO/releases/download/$TAG"

# ── Up-to-date checks ────────────────────────────────────────────────────────
have_all() { for b in $GM_BINARIES; do [ -x "$GM_BIN/$b" ] || return 1; done; return 0; }

if [ "$MODE" != "force" ]; then
    case "$INSTALLED" in
        *-BETA)
            # A locally built, locally staged binary. A download must never
            # silently replace work someone is in the middle of testing.
            if have_all; then
                echo "[GMB] $INSTALLED is active (a local build) — leaving it alone"
                echo "      rebuild:            bash gmk/scripts/rebuild_local.sh"
                echo "      switch to v$VERSION: bash $SCRIPT_DIR/install_gm.sh --force"
                exit 0
            fi
            ;;
        "$VERSION")
            if have_all; then
                echo "[GMB] v$VERSION already active at $GM_BIN"
                exit 0
            fi
            ;;
    esac
fi

if [ "$MODE" = "check" ]; then
    if [ "$INSTALLED" = "none" ]; then
        echo "[GMB] not installed — newest published is v$VERSION"
    else
        echo "[GMB] $INSTALLED active, newest published is v$VERSION"
    fi
    echo "      run: bash $SCRIPT_DIR/install_gm.sh"
    exit 1
fi

# ── Already in the store? ────────────────────────────────────────────────────
# A version that was downloaded before is re-activated rather than re-fetched.
# This is what makes rolling between versions cheap and offline.
if [ -d "$GM_DOWNLOADS/$VERSION" ] && [ "$MODE" != "force" ] \
   && gm_verify_staged "$GM_DOWNLOADS/$VERSION" 2>/dev/null; then
    echo "[GMB] v$VERSION is already in the store — activating without a download"
    gm_activate downloads "$VERSION"
    gm_retire_daemon
    exit 0
fi

# ── Download ─────────────────────────────────────────────────────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gm-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "[GMB] fetching $TAG from $RELEASE_REPO..."
if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$ASSET" "$BASE/$ASSET" \
   || ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$ASSET.sha256" "$BASE/$ASSET.sha256"; then
    cat >&2 <<EOF
[GMB] ERROR: could not download $BASE/$ASSET

      The release exists but the asset does not, or the network is unreachable.
      With a checkout, build instead: bash gmk/scripts/rebuild_local.sh
EOF
    exit 1
fi

# Checksum BEFORE anything is unpacked. The sidecar is written as
# `<hash>  <filename>`, so it is verified from the directory where that
# filename resolves.
if ! ( cd "$TMP" && shasum -a 256 -c "$ASSET.sha256" >/dev/null 2>&1 ); then
    echo "[GMB] ERROR: checksum mismatch on $ASSET — refusing to install" >&2
    echo "       expected: $(cut -d' ' -f1 < "$TMP/$ASSET.sha256")" >&2
    echo "       actual:   $(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)" >&2
    exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"
for b in $GM_BINARIES; do
    [ -f "$TMP/$b" ] || {
        echo "[GMB] ERROR: $ASSET does not contain $b — refusing a partial install" >&2
        exit 1; }
done

# ── Stage + activate ─────────────────────────────────────────────────────────
DL="$(gm_stage_dir downloads "$VERSION")"
rm -rf "$DL"; DL="$(gm_stage_dir downloads "$VERSION")"
for b in $GM_BINARIES; do cp "$TMP/$b" "$DL/$b"; chmod +x "$DL/$b"; done
gm_write_manifest "$DL" "$VERSION" downloads "$TAG" "$(lipo -archs "$DL/gm_daemon" 2>/dev/null | tr ' ' ',')"

gm_activate downloads "$VERSION"
gm_retire_daemon

echo ""
echo "[GMB] installed v$VERSION"
echo "      $GM_BIN/gm_daemon -> releases/downloads/$VERSION/gm_daemon"
