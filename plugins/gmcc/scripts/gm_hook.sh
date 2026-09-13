#!/bin/bash
# Every non-SessionStart GM hook, fronted by ONE script. The event name
# arrives as argv; the raw payload rides stdin straight through to
# `gm_hook hook <event>`, which owns every decision past this point.
#
# ONE shim rather than one prelude per event. N near-identical preludes drift
# apart: a fix applied to three of them and missed on the fourth is invisible
# until that event's hook has been quietly dead for weeks. One cannot drift
# from itself.
#
# THE NO-OP CONTRACT — none of these three lines is negotiable:
#
#   1. gm_hook is located from ${GM_FS_ROOT:-$HOME/gmfs}. Never PATH, never
#      `command -v`. A hook runs with whatever environment the harness hands
#      it, so the FALLBACK must be a filesystem constant — but the override is
#      now honoured. SEE THE REVERSAL NOTE BELOW: this line used to forbid
#      GM_FS_ROOT outright.
#   2. A missing binary is a silent `exit 0`. A hook may never block a tool
#      call, wedge a spawn, or write to stderr. NOTE THE COST of that silence
#      once more than one environment exists — see the warning below.
#   3. No jq and no git. Parsing the payload, deciding which paths a call
#      wrote and building the row all happen in Swift, where `swift test`
#      reaches them.
#
# Refusing to write in a repo GM does not own is enforced daemon-side, not
# here: a write is refused unless the payload's session_id has a row in the
# claude-session binding, and an unbooted repo never ran SessionStart in that
# Claude session to create one.

[ -n "$1" ] || exit 0

# ── Locate gm_hook from the filesystem ───────────────────────────────────────
#
# A RECORDED REVERSAL. This line used to read `HOOK_BIN="$HOME/gmfs/bin/gm_hook"`
# and the contract above forbade consulting GM_FS_ROOT at all. That was correct
# while exactly one runtime root existed. It is wrong now, and wrong in the
# worst available direction.
#
# This shim fronts SubagentStart and EVERY PostToolUse. Its three siblings —
# run_mcp.sh, gm_session_startup.sh and check_gm_stale.sh — already honour
# ${GM_FS_ROOT:-$HOME/gmfs}. So a session pointed at a non-production
# environment got its SessionStart and its pen/MCP writes into that
# environment's database, and every tool-call hook write into PRODUCTION. One
# session, two databases, no error, no signal. The asymmetry WAS the bug.
#
# The fallback is unchanged and still a filesystem constant, so a hook running
# with no environment at all behaves exactly as before. The failure direction is
# benign: an unset variable still lands on production.
#
# WARNING, AND IT IS THE REASON `gm_env create` STAGES BINARIES: the `-x` test
# below exits 0 SILENTLY. An environment whose bin/ is unpopulated does not
# report a problem — it records nothing at all. Fixing this line without also
# staging a full release store per root trades a wrong-database write for a
# silent no-write, which is harder to notice, not easier.
HOOK_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook"
[ -x "$HOOK_BIN" ] || exit 0

# "$@" rather than "$1": the event is argv[1] and the harness passes nothing
# else, but forwarding the rest is what lets the documented verification path
# (--dry-run) run through THIS script instead of around it. A check that
# bypasses the shim does not check the shim.
exec "$HOOK_BIN" hook "$@"
