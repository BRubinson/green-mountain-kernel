#!/bin/bash

# GM-CDE SessionStart bootstrap. Four jobs only: confirm we're in a git repo,
# find the right gm_hook binary, and hand the hook payload on stdin to
# `gm_hook context ensure`. Everything else — identity, paths, env
# emission, the artifact home, dope boot sync, the pen sheet — is owned by
# that binary (`context ensure` + `context env`). This script computes
# NOTHING the daemon computes, and it does not read the payload: the session
# uuid inside it is sliced out in Swift, so no jq is on this path either.
#
# Anything outside a git repo: silent exit with no GM vars set.

# --- 0. Git-repo guard ------------------------------------------------------
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# --- 0b. The hook payload ---------------------------------------------------
# Held verbatim and piped into `gm_hook context ensure --hook-payload`, which pins
# its session_id to the ensured session in claude_session_binding. That
# binding is what every later hook write resolves its gm session through, so
# a SessionStart that drops the payload leaves the whole capture surface
# writing nothing. `[ -t 0 ]` keeps a hand-run of this script off a blocking
# read — under the harness stdin is always a pipe.
payload=""
[ -t 0 ] || payload="$(cat 2>/dev/null)"

# --- 1. Plugin root from this script's location -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GM_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- 2. Sandbox marker ------------------------------------------------------
# A snapshot repo copy carries .gmcc_sandbox at its root. PARSED as data,
# never sourced — a repo file must not get shell execution at SessionStart.
#
# ONE root variable now. The marker used to name two (a runtime root and a
# separate content root) which had to be kept in agreement by hand; there is no
# longer a combination of marker contents describing a half-sandboxed session.
#
# The FILENAME is deliberately not renamed: HookLogic.SandboxMarker.fileName in
# gmDaemonSdk is the authority, and a marker only one side recognises is a
# sandbox session writing the prod database.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.gmcc_sandbox" ]; then
    _sb_root=$(sed -n 's/^export GM_FS_ROOT="\(.*\)"$/\1/p' "$REPO_ROOT/.gmcc_sandbox" | head -1)
    [ -n "$_sb_root" ] && export GM_FS_ROOT="$_sb_root"
fi

# --- 3. Locate gm_hook ------------------------------------------------------
HOOK_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook"
if [ ! -x "$HOOK_BIN" ]; then
    echo "[GMB] gm_hook binary missing at $HOOK_BIN — run 'bash $GM_PLUGIN_DIR/scripts/install_gm.sh', then restart the session"
    exit 0
fi

# --- 4. Rows + binding + artifact home + dope boot sync (stderr = notices) --
warnings=$( (cd "$REPO_ROOT" && printf '%s' "$payload" \
    | "$HOOK_BIN" context ensure --hook-payload >/dev/null) 2>&1 )
if [ $? -ne 0 ]; then
    warnings="$warnings
[GMB] daemon unavailable — context not ensured (run 'bash $GM_PLUGIN_DIR/scripts/install_gm.sh' or /gm_daemon, then 'gm_hook context ensure')"
fi

# --- 5. Cheatsheet into hook stdout (automatic; the agent never runs it) ----
"$HOOK_BIN" pen-sheet 2>/dev/null || true

# --- 6. Env contract → $CLAUDE_ENV_FILE (stdout), warnings → context --------
if [ -n "$CLAUDE_ENV_FILE" ]; then
    warnings="$warnings
$( (cd "$REPO_ROOT" && "$HOOK_BIN" context env --plugin-root "$GM_PLUGIN_DIR") 2>&1 >> "$CLAUDE_ENV_FILE" )"
fi

if [ -n "$(printf '%s' "$warnings" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$warnings"
fi

exit 0
