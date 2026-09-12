#!/bin/bash
# Every non-SessionStart GMCC hook, fronted by ONE script. The event name
# arrives as argv; the raw payload rides stdin straight through to
# `gmcc_hook hook <event>`, which owns every decision past this point.
#
# ONE shim rather than one prelude per event. N near-identical preludes drift
# apart: a fix applied to three of them and missed on the fourth is invisible
# until that event's hook has been quietly dead for weeks. One cannot drift
# from itself.
#
# THE NO-OP CONTRACT — none of these three lines is negotiable:
#
#   1. gmcc_hook is located from THIS SCRIPT'S OWN LOCATION plus an upward
#      `.gmcc_sandbox` walk. Never PATH, never `command -v`, never an
#      inherited GMCC_* variable. A hook runs with whatever environment the
#      harness hands it, which is NOT the environment `gmcc_hook context env`
#      provisioned the session with — a resolution that depends on either one
#      is a hook that stops firing without ever saying so.
#   2. A missing binary is a silent `exit 0`. A hook may never block a tool
#      call, wedge a spawn, or write to stderr.
#   3. No jq and no git. Parsing the payload, deciding which paths a call
#      wrote and building the row all happen in Swift, where `swift test`
#      reaches them.
#
# Refusing to write in a repo GMCC does not own is enforced daemon-side, not
# here: a write is refused unless the payload's session_id has a row in the
# claude-session binding, and an unbooted repo never ran SessionStart in that
# Claude session to create one.

[ -n "$1" ] || exit 0

# ── Locate gmcc_hook from the filesystem ──────────────────────────────────────────
# A snapshot repo copy carries `.gmcc_sandbox` at its root and this script
# ships INSIDE that copy, so climbing from the script's own directory finds
# the snapshot's runtime whenever the hook belongs to one — without which a
# sandbox session's hooks would write the prod db. The marker is PARSED as
# data, never sourced: a repo file must not get shell execution out of a hook.
d="$(cd "$(dirname "$0")" && pwd)" || exit 0
sandbox_root=""
while [ "$d" != "/" ]; do
  if [ -f "$d/.gmcc_sandbox" ]; then
    sandbox_root="$(sed -n 's/^export GMCC_ROOT="\(.*\)"$/\1/p' "$d/.gmcc_sandbox" | head -1)"
    break
  fi
  d="$(dirname "$d")"
done

HOOK_BIN="${sandbox_root:-$HOME/gmcc}/bin/gmcc_hook"
[ -x "$HOOK_BIN" ] || exit 0

# "$@" rather than "$1": the event is argv[1] and the harness passes nothing
# else, but forwarding the rest is what lets the documented verification path
# (--dry-run) run through THIS script instead of around it. A check that
# bypasses the shim does not check the shim.
exec "$HOOK_BIN" hook "$@"
