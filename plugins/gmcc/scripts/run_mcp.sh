#!/bin/bash

# GM MCP server launcher — the plugin's .mcp.json points here.
#
# THIS SCRIPT ONLY EVER CONNECTS. IT NEVER BUILDS.
#
# It used to run a build synchronously before exec, which put a cold
# `swift build -c release` — minutes, not seconds — directly on the MCP connect
# path. Exactly the sessions that follow a source edit would spend their whole
# handshake budget in bash and then build their first prompt with no pen in it.
# An agent in that session reads a correct frontmatter tool list and finds every
# pen call failing, which is indistinguishable from "the MCP is not registered".
#
# THIS REMAINS TRUE UNDER THE RELEASE STORE. Getting binaries onto disk is
# exclusively an explicit act — install_gm.sh (fetches the newest published
# release) or gmk/scripts/rebuild_local.sh (builds your working tree). Neither
# one is ever reached from here. Health is reported by check_gm_stale.sh at
# SessionStart, which already runs on every session and already stats all three
# binaries.
#
# A MISSING BINARY EXITS NON-ZERO, LOUDLY. That is the whole point of the exit
# code: with tool search enabled Claude Code names the server that failed and
# surfaces its connection error, so the failure arrives as "plugin:gmcc:pen
# failed to start" instead of the silent "No matching deferred tools found" that
# a dead-but-running server produces. Never exit 0 here to be polite — a server
# that stays up and fails every tool call is the silent mode this removes.
#
# Sandbox sessions honor GM_FS_ROOT exactly like every other launcher.

if [ -z "$GM_FS_ROOT" ]; then
    _repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$_repo" ] && [ -f "$_repo/.gmcc_sandbox" ]; then
        _sb=$(sed -n 's/^export GM_FS_ROOT="\(.*\)"$/\1/p' "$_repo/.gmcc_sandbox" | head -1)
        [ -n "$_sb" ] && GM_FS_ROOT="$_sb"
    fi
fi
GM_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin"

if [ ! -x "$GM_BIN/gm_mcp" ]; then
    echo "[GMB] gm_mcp missing at $GM_BIN/gm_mcp — run: bash \"$(cd "$(dirname "$0")" && pwd)/install_gm.sh\"" >&2
    exit 1
fi

exec "$GM_BIN/gm_mcp"
