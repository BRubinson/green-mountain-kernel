#!/bin/bash

# GM-CDE SessionStart bootstrap. Four jobs only: confirm we're in a git repo,
# find the right gmcc_hook binary, and hand the hook payload on stdin to
# `gmcc_hook context ensure`. Everything else — identity, paths, env
# emission, the artifact home, dope boot sync, the pen sheet — is owned by
# that binary (`context ensure` + `context env`). This script computes
# NOTHING the daemon computes, and it does not read the payload: the session
# uuid inside it is sliced out in Swift, so no jq is on this path either.
#
# Anything outside a git repo: silent exit with no GMCC vars set.

# --- 0. Git-repo guard ------------------------------------------------------
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# --- 0b. The hook payload ---------------------------------------------------
# Held verbatim and piped into `gmcc_hook context ensure --hook-payload`, which pins
# its session_id to the ensured session in claude_session_binding. That
# binding is what every later hook write resolves its gmcc session through, so
# a SessionStart that drops the payload leaves the whole capture surface
# writing nothing. `[ -t 0 ]` keeps a hand-run of this script off a blocking
# read — under the harness stdin is always a pipe.
payload=""
[ -t 0 ] || payload="$(cat 2>/dev/null)"

# --- 1. Plugin root from this script's location -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- 2. Sandbox marker ------------------------------------------------------
# A snapshot repo copy carries .gmcc_sandbox at its root. PARSED as data,
# never sourced — a repo file must not get shell execution at SessionStart.
# GMCC_ROOT selects the runtime (binaries + db); GMCC_CKFS_ROOT is the
# daemon-down fallback claim `gmcc_hook context env` checks against the db.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.gmcc_sandbox" ]; then
    _sb_root=$(sed -n 's/^export GMCC_ROOT="\(.*\)"$/\1/p' "$REPO_ROOT/.gmcc_sandbox" | head -1)
    _sb_ckfs=$(sed -n 's/^export GMCC_CKFS_ROOT="\(.*\)"$/\1/p' "$REPO_ROOT/.gmcc_sandbox" | head -1)
    [ -n "$_sb_root" ] && export GMCC_ROOT="$_sb_root"
    [ -n "$_sb_ckfs" ] && export GMCC_CKFS_ROOT="$_sb_ckfs"
fi

# --- 3. Locate gmcc_hook ----------------------------------------------------
HOOK_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin/gmcc_hook"
if [ ! -x "$HOOK_BIN" ]; then
    echo "[GMB] gmcc_hook binary missing at $HOOK_BIN — run 'bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh' to build, then restart the session"
    exit 0
fi

# --- 4. Rows + binding + artifact home + dope boot sync (stderr = notices) --
warnings=$( (cd "$REPO_ROOT" && printf '%s' "$payload" \
    | "$HOOK_BIN" context ensure --hook-payload >/dev/null) 2>&1 )
if [ $? -ne 0 ]; then
    warnings="$warnings
[GMB] daemon unavailable — context not ensured (run 'bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh' or /gmcc_daemon, then 'gmcc_hook context ensure')"
fi

# --- 5. Cheatsheet into hook stdout (automatic; the agent never runs it) ----
"$HOOK_BIN" pen-sheet 2>/dev/null || true

# --- 6. Env contract → $CLAUDE_ENV_FILE (stdout), warnings → context --------
if [ -n "$CLAUDE_ENV_FILE" ]; then
    warnings="$warnings
$( (cd "$REPO_ROOT" && "$HOOK_BIN" context env --plugin-root "$GMCC_PLUGIN_DIR") 2>&1 >> "$CLAUDE_ENV_FILE" )"
fi

if [ -n "$(printf '%s' "$warnings" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$warnings"
fi

exit 0
