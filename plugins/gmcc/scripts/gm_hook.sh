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
#   1. gm_hook is located from $HOME/gmfs, the ONE runtime root. Never PATH,
#      never `command -v`, never an inherited GM_* variable. A hook runs with
#      whatever environment the
#      harness hands it, which is NOT the environment `gm_hook context env`
#      provisioned the session with — a resolution that depends on either one
#      is a hook that stops firing without ever saying so.
#   2. A missing binary is a silent `exit 0`. A hook may never block a tool
#      call, wedge a spawn, or write to stderr.
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
# There is ONE runtime root, so this is one path with no discovery step. The
# upward marker walk that used to live here existed only to let a snapshot copy
# of this repo point its hooks at a second runtime; with that runtime gone, a
# walk could only ever find the same answer more slowly, and an env var could
# only ever disagree with it.
#
# Still resolved from the filesystem rather than PATH or an inherited GM_*
# variable, and that half of the contract has not changed: a hook runs with
# whatever environment the harness hands it, not the one the session was
# provisioned with.
HOOK_BIN="$HOME/gmfs/bin/gm_hook"
[ -x "$HOOK_BIN" ] || exit 0

# "$@" rather than "$1": the event is argv[1] and the harness passes nothing
# else, but forwarding the rest is what lets the documented verification path
# (--dry-run) run through THIS script instead of around it. A check that
# bypasses the shim does not check the shim.
exec "$HOOK_BIN" hook "$@"
