#!/bin/bash

# GMCC MCP server launcher (m0025) — the plugin's .mcp.json points here.
#
# THIS SCRIPT ONLY EVER CONNECTS. IT NEVER BUILDS.
#
# It used to run build_daemon.sh synchronously before exec, which put a cold
# `swift build -c release` — minutes, not seconds — directly on the MCP connect
# path. Exactly the sessions that follow a source edit would spend their whole
# handshake budget in bash and then build their first prompt with no pen in it.
# An agent in that session reads a correct frontmatter tool list and finds every
# pen call failing, which is indistinguishable from "the MCP is not registered".
#
# Building is now exclusively an explicit act: build_daemon.sh, or
# `gmcc_daemon build` / a daemon restart. Staleness is reported by
# check_daemon_stale.sh at SessionStart, which already runs on every session and
# already stats all three binaries.
#
# A MISSING BINARY EXITS NON-ZERO, LOUDLY. That is the whole point of the exit
# code: with tool search enabled Claude Code names the server that failed and
# surfaces its connection error, so the failure arrives as "plugin:gmcc:pen
# failed to start" instead of the silent "No matching deferred tools found" that
# a dead-but-running server produces. Never exit 0 here to be polite — a server
# that stays up and fails every tool call is the silent mode this removes.
#
# Sandbox sessions honor GMCC_ROOT exactly like every other launcher.

GMCC_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin"

if [ ! -x "$GMCC_BIN/gmcc_mcp" ]; then
    echo "[GMB] gmcc_mcp missing at $GMCC_BIN/gmcc_mcp — run: bash \"$(cd "$(dirname "$0")" && pwd)/build_daemon.sh\"" >&2
    exit 1
fi

exec "$GMCC_BIN/gmcc_mcp"
