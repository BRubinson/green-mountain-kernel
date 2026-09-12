#!/bin/bash

# GMCC daemon staleness check
#
# SessionStart hook: warn (never block) when the installed daemon binaries are
# missing or do not match what this plugin pins. Plugin root derived from this
# script's location (dirname trick), same as gmcc_session_startup.sh.
#
# THIS IS THE ONLY STALENESS CHECK ON THE PATH TO A SESSION. run_mcp.sh used to
# carry a second one and rebuild inline; it now only connects, so a stale or
# missing gmcc_mcp surfaces HERE — once, at SessionStart, naming the binary and
# the exact command — rather than as a silent handshake failure later.
#
# TWO CHECKS, BECAUSE THERE ARE TWO KINDS OF USER.
#
#   Installed from a release → compare daemon/VERSION against the runtime's
#   .gmcc_version stamp. An exact equality, and the remediation is a download.
#   The old `find -newer` mtime test could not serve this case at all: git
#   stamps every checked-out file with the checkout time, so after any plugin
#   update the sources ALWAYS look newer than the binary and the check fired
#   unconditionally, demanding a full rebuild for a docs-only change.
#
#   Building from source (a `+src.<sha>` stamp) → keep the mtime test. While
#   sources are being edited, "is any source newer than the binary" is exactly
#   the right question, and the version file cannot answer it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DAEMON_PKG="$GMCC_PLUGIN_DIR/daemon"
GMCC_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin"
VERSION_STAMP="$GMCC_BIN/.gmcc_version"

# No daemon package in this plugin build — nothing to check.
[ -f "$DAEMON_PKG/Package.swift" ] || exit 0

PINNED="$(cat "$DAEMON_PKG/VERSION" 2>/dev/null || echo unknown)"

for bin in gmcc_daemon gmcc_mcp gmcc_hook; do
    if [ ! -x "$GMCC_BIN/$bin" ]; then
        echo "[GMB] $bin not installed at $GMCC_BIN/$bin — run: bash $SCRIPT_DIR/install_daemon.sh"
        exit 0
    fi
done

INSTALLED="unknown"
[ -f "$VERSION_STAMP" ] && INSTALLED="$(cat "$VERSION_STAMP")"

case "$INSTALLED" in
    *+src.*)
        # Developer build — mtime is the honest test. Named per-binary rather
        # than "the daemon": gmcc_mcp going stale is the one a session feels as
        # a pen that will not answer, and a shared message never said which
        # binary to look at.
        for bin in gmcc_daemon gmcc_mcp gmcc_hook; do
            if [ -n "$(find "$DAEMON_PKG/Sources" "$DAEMON_PKG/Package.swift" -newer "$GMCC_BIN/$bin" -print -quit 2>/dev/null)" ]; then
                echo "[GMB] $bin stale (sources newer than $GMCC_BIN/$bin) — run: bash $SCRIPT_DIR/build_daemon.sh"
            fi
        done
        ;;
    "$PINNED")
        : # exactly what this plugin pins — nothing to say
        ;;
    unknown)
        # Binaries with no stamp: installed before versioning existed. Not an
        # error, but the version is unknowable, so say so once and offer the
        # install that makes it knowable.
        echo "[GMB] daemon binaries carry no version stamp (pre-versioning install) — run: bash $SCRIPT_DIR/install_daemon.sh"
        ;;
    *)
        echo "[GMB] daemon v$INSTALLED installed, this plugin pins v$PINNED — run: bash $SCRIPT_DIR/install_daemon.sh"
        ;;
esac

exit 0
