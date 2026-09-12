#!/bin/bash

# GMCC daemon staleness check
#
# SessionStart hook: warn (never block) when the installed daemon binaries are
# missing or older than the daemon package sources. Plugin root derived from
# this script's location (dirname trick), same as gmcc_session_startup.sh.
#
# THIS IS THE ONLY STALENESS CHECK ON THE PATH TO A SESSION. run_mcp.sh used to
# carry a second one and rebuild inline; it now only connects, so a stale or
# missing gmcc_mcp surfaces HERE — once, at SessionStart, naming the binary and
# the exact command — rather than as a silent handshake failure later.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DAEMON_PKG="$GMCC_PLUGIN_DIR/daemon"
GMCC_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin"

# No daemon package in this plugin build — nothing to check.
[ -f "$DAEMON_PKG/Package.swift" ] || exit 0

for bin in gmcc_daemon gmcc_mcp gmcc_hook; do
    if [ ! -x "$GMCC_BIN/$bin" ]; then
        echo "[GMB] $bin not installed at $GMCC_BIN/$bin — run: bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh"
        exit 0
    fi
done

# Named per-binary rather than "the daemon": gmcc_mcp going stale is the one a
# session feels as a pen that will not answer, and the old shared message never
# said which binary to look at.
for bin in gmcc_daemon gmcc_mcp gmcc_hook; do
    if [ -n "$(find "$DAEMON_PKG/Sources" "$DAEMON_PKG/Package.swift" -newer "$GMCC_BIN/$bin" -print -quit 2>/dev/null)" ]; then
        echo "[GMB] $bin stale (sources newer than $GMCC_BIN/$bin) — run: bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh"
    fi
done

exit 0
