#!/bin/bash

# GM runtime health check.
#
# SessionStart hook: warn (never block) when the installed binaries are missing
# or unusable. Runtime root derived the same way every other launcher derives it.
#
# THIS IS THE ONLY RUNTIME CHECK ON THE PATH TO A SESSION. run_mcp.sh only
# connects, so a missing or broken gm_mcp surfaces HERE — once, at SessionStart,
# naming the binary and the exact command — rather than as a silent handshake
# failure later.
#
# ── WHY IT NEVER ASKS GITHUB ─────────────────────────────────────────────────
#
# This runs on EVERY session start. A network round trip here would add latency
# to every session to answer a question nobody asked, and would fail in exactly
# the offline case where a working local install matters most. So the check is
# purely local: are the binaries there and do they resolve.
#
# Checking for a NEWER published release is therefore an explicit act:
#
#     bash <plugin>/scripts/install_gm.sh --check
#
# ── WHY THERE IS NO VERSION COMPARISON ───────────────────────────────────────
#
# The plugin deliberately carries no runtime version pin (see install_gm.sh), so
# there is no local number to compare against. The old check compared the
# plugin's bundled `daemon/VERSION` against the install stamp; that package left
# the plugin for gmk/, and a plugin-side copy of the pin would be a second number
# to bump on every release that could silently disagree with gmk/VERSION.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Same root resolution as every other launcher: explicit GM_FS_ROOT wins, else a
# sandbox marker at the repo root, else $HOME/gmfs. Parsed as data, never sourced.
if [ -z "$GM_FS_ROOT" ]; then
    _repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$_repo" ] && [ -f "$_repo/.gmcc_sandbox" ]; then
        _sb=$(sed -n 's/^export GM_FS_ROOT="\(.*\)"$/\1/p' "$_repo/.gmcc_sandbox" | head -1)
        [ -n "$_sb" ] && GM_FS_ROOT="$_sb"
    fi
fi
GM_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin"
VERSION_STAMP="$GM_BIN/.gm_version"

for bin in gm_daemon gm_mcp gm_hook; do
    if [ ! -x "$GM_BIN/$bin" ]; then
        # -e is false for a DANGLING symlink, which is the failure mode the
        # release store can produce: an `active` link pointing at a version
        # directory that was deleted. Naming it is the difference between a
        # five-second fix and a confusing "the file is right there" hunt.
        if [ -L "$GM_BIN/$bin" ]; then
            echo "[GMB] $bin is a broken link ($GM_BIN/$bin -> $(readlink "$GM_BIN/$bin")) — run: bash $SCRIPT_DIR/install_gm.sh"
        else
            echo "[GMB] $bin not installed at $GM_BIN/$bin — run: bash $SCRIPT_DIR/install_gm.sh"
        fi
        exit 0
    fi
done

# Binaries with no stamp: installed before the release store existed. Not an
# error, but the version is unknowable, so say so once and offer the install
# that makes it knowable.
if [ ! -f "$VERSION_STAMP" ]; then
    echo "[GMB] gm binaries carry no version stamp — run: bash $SCRIPT_DIR/install_gm.sh"
fi

exit 0
