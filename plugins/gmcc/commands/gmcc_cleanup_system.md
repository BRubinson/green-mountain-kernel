---
name: gmcc_cleanup_system
description: Audit and repair GM-CDE host wiring — retired ~/.zshrc gmcc block, terminal PATH, env-vs-db root agreement, permission grants.
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC System Cleanup

If `$GMCC_BOOTED` is not set, stop with `[GMB] ERROR: GMCC not booted`
(run /gmcc_boot for diagnostics).

Invoke the `gmcc_cleanup_system` skill and follow it. The env-vs-db root
audit is `gmcc_hook context env --plugin-root "$GMCC_PLUGIN_ROOT"`: it
prints the session env block on stdout and any root disagreement between the
env and the db as `[GMB] WARN:` lines on stderr — read the stderr. Compare
against `gmcc_hook paths --json` (the db's answer), then check `~/.zshrc`
and `~/.claude/settings.json` directly. Resolve each finding interactively
(the retired `~/.zshrc` gmcc env block's default remedy is DELETE), and
verify with a clean re-run.

The ckfs/db data audit (artifact drift, archive hygiene, kbite provenance)
is `/gmcc_cleanup`.
