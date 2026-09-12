# gmcc-marketplace

Monorepo for the GM-CDE (Green Mountain Contextual Development
Environment). GMB identity and behavioral rules are NOT here — they live
plugin-globally in `plugins/gmcc/skills/gmcc/SKILL.md` so every
gmcc-booted repo gets them, not just this one.

## Layout

- `plugins/gmcc/` — the Claude Code plugin: skills, commands, prompts,
  hooks, scripts, and the daemon Swift package (`plugins/gmcc/daemon/` →
  the `GMCCDaemonKit` library plus three binaries: `gmcc_daemon`, the
  server that owns `~/gmcc/gmcc.db`; `gmcc_mcp`, the MCP pen Claude
  calls; and `gmcc_hook`, the shell-callable client — hooks, ops, and
  `gmcc_hook call <MESSAGE_TYPE> --json '{...}'`, the raw wire that
  reaches every verb the daemon serves).
- `gmvibes/` — the GMVibes macOS app (Swift/SwiftUI), building against the
  daemon package via a direct local package reference. Release via the
  `release-dmg` skill.
- `.gmcc/` — this repo's committed DOPE tree (Domain Optimized
  Project Essence); sessions boot-sync their dope scope from it.

## Build / test loop

From the repo root:

```bash
(cd plugins/gmcc/daemon && swift test)       # full suite; must stay green
bash plugins/gmcc/scripts/build_daemon.sh    # release build → ~/gmcc/bin/
gmcc_hook call SHUTDOWN --json '{}'          # retire the running daemon
gmcc_hook ping                               # the next client autostarts it
```

- `VerbRegistryTests` fails the build when a `MessageType` ships without
  a `VerbRegistry` row; `DocsContractTests` fails it when the plugin's
  docs regress (hardcoded binary paths, retired env names, retired DOPE
  acronym) or when `hooks.json` / `settings.json` / `.mcp.json` name a
  path that is not there.
- Wire protocol: bump `GMCCWireProtocol.version` only for a new message
  type or an incompatible change. Additive OPTIONAL fields on existing
  messages do NOT bump — they decode safely in both directions.
- Schema: migrations are append-only. The db at `~/gmcc/gmcc.db` is
  append-only history — NEVER wipe it. `gmcc_hook call BACKUP --json
  '{}'` takes the sanctioned online backup before risky work.

## Environment rules

- Sessions are provisioned by `gmcc_hook context env` at SessionStart;
  the only env vars are GMCC_BOOTED, GMCC_PLUGIN_ROOT, GMCC_CKFS_ROOT,
  PATH (+ GMCC_ROOT when sandboxed). Everything else:
  `gmcc_hook paths --json`.
- GMCC never writes the user's shell profile. The binaries reach a
  session through the PATH entry in that env block, and remediation lines
  are printed, not applied.
- env and db must always agree on the roots (mismatch = warning at boot).
  Sandbox snapshots keep them in agreement by construction — the staged
  db is retargeted to the snapshot's roots when it is written.

## Sandbox dev loop

A sandbox is a full snapshot at `{ckfs_root}/development/local_sandbox` —
db (`gmcc_hook call BACKUP --json '{}'` takes the sanctioned online copy),
repo clone, binaries, launchers. Sessions started inside the snapshot
auto-sandbox via the `.gmcc_sandbox` marker and set GMCC_ROOT to it; a
sandboxed daemon opens only the staged db and never touches prod. Nothing
in a sandbox should be pointed back at the prod runtime.

## Working-tree note

Uncommitted sandbox-feature edits in the working tree are usually
intentional — validate against the working tree, don't "fix" them back to
HEAD without asking.
