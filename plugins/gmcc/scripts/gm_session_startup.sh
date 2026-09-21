#!/bin/bash

# GM-CDE SessionStart bootstrap. Four jobs only: confirm we're in a git repo,
# find the plugin's own gm_hook executable, and hand the hook payload on stdin
# to `gm_hook context ensure`. Everything else — identity, paths, env
# emission, the artifact home, dope boot sync, the pen sheet — is owned by
# that binary (`context ensure` + `context env`). This script computes
# NOTHING the daemon computes, and it does not read the payload: the session
# uuid inside it is sliced out in Swift, so no jq is on this path either.
#
# Anything outside a git repo: silent exit with no GM vars set.

# --- 0. Git-repo guard, and the repo root ------------------------------------
#
# REPO_ROOT is REQUIRED, not a convenience. Both `gm_hook` invocations below run
# inside `(cd "$REPO_ROOT" && …)`, and the binary derives the project, instance
# and session from its own working directory. An empty value makes that `cd ""`,
# which SILENTLY SUCCEEDS and leaves the hook in whatever directory the harness
# happened to hand it — so a session would be filed under the wrong repo, or none,
# with no error anywhere.
#
# It is assigned HERE, beside the guard that proves a repo exists, rather than
# further down: it previously lived inside the snapshot-marker block, and deleting
# that block took the assignment with it while leaving both uses behind.
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || exit 0

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

# --- 2. Locate gm_hook: it ships INSIDE the plugin ----------------------------
# Compiled with the client closure by gmk/scripts/build_plugin_binaries.sh and
# committed beside this script. The KERNEL it dials still comes from
# $GM_FS_ROOT/bin/gm_daemon (install_gm.sh); a missing kernel surfaces as the
# "daemon unavailable" notice below, never as a missing gm_hook.
HOOK_BIN="$GM_PLUGIN_DIR/bin/gm_hook"
if [ ! -x "$HOOK_BIN" ]; then
    echo "[GMB] gm_hook missing at $HOOK_BIN — this plugin tree was written without build_plugin_binaries.sh"
    exit 0
fi

# --- 3. Rows + binding + artifact home + dope boot sync (stderr = notices) --
warnings=$( (cd "$REPO_ROOT" && printf '%s' "$payload" \
    | "$HOOK_BIN" context ensure --hook-payload >/dev/null) 2>&1 )
if [ $? -ne 0 ]; then
    warnings="$warnings
[GMB] daemon unavailable — context not ensured (run 'bash $GM_PLUGIN_DIR/scripts/install_gm.sh' or /gm_daemon, then 'gm_hook context ensure')"
fi

# --- 3b. Version drift: the plugin names one kernel version; a different
# non-BETA kernel on disk is a downloaded release that fell behind or ran ahead.
PLUGIN_V="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$GM_PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
KERNEL_V="$(cat "${GM_FS_ROOT:-$HOME/gmfs}/bin/.gm_version" 2>/dev/null || true)"
case "$KERNEL_V" in
    ""|none|*-BETA) ;;
    "$PLUGIN_V") ;;
    *) warnings="$warnings
[GMB] kernel $KERNEL_V active but plugin is v$PLUGIN_V — run /gmcc:gm_install (or 'bash $GM_PLUGIN_DIR/scripts/install_gm.sh')" ;;
esac

# --- 4. Cheatsheet into hook stdout (automatic; the agent never runs it) ----
"$HOOK_BIN" pen-sheet 2>/dev/null || true

# --- 5. Env contract → $CLAUDE_ENV_FILE (stdout), warnings → context --------
if [ -n "$CLAUDE_ENV_FILE" ]; then
    warnings="$warnings
$( (cd "$REPO_ROOT" && "$HOOK_BIN" context env --plugin-root "$GM_PLUGIN_DIR") 2>&1 >> "$CLAUDE_ENV_FILE" )"
fi

if [ -n "$(printf '%s' "$warnings" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$warnings"
fi

exit 0
