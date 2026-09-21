---
name: kernel
description: One binary, sole writer, one filesystem root
user-invocable: false
---

## The Kernel: One Binary, Sole Writer, One Root

**ONE Mach-O**, `gm_kernel` — the sole entity that touches `~/gmfs/gm.db` (the SQLite database). `GmPersonality` resolves `basename(argv[0])` to answer as `gm_daemon` (the persistent server; a symlink in `~/gmfs/bin/`), and the same code compiled with the client closure ships in the plugin as `bin/gm_mcp` (the MCP server Claude records through) and `bin/gm_hook` (the shell-callable client).

### The Single Writer Guarantee
`gm_daemon` is the **sole writer to the database**. Every other process — the app, Claude hooks, tools, the MCP server — is a socket client. The database is APPEND-ONLY history: never wipe it, never delete rows. A wrong row is corrected by writing again.

### The Filesystem Root
`~/gmfs` (`$GM_FS_ROOT`) is the one filesystem root per environment: its own db, socket, pidfile, `flock`, release store and repo clone. Write containment is enforced, not advisory — `Paths.assertContained(_:)` throws unless a write lands under `$GM_FS_ROOT` or the working repo. The Endotherm's work lives inside this boundary.

### The One Door
The pen — `mcp__plugin_gmcc_cde__*`, served by `gm_mcp` — is the ONLY door an agent uses. Its tools are typed, each takes an `op`, they thread `expected_version`, and their output is budgeted. A verb with no pen tool is a missing door: REPORT it to the Endotherm. There is no shell door, and the PreToolUse hook DENIES a Bash command that reaches for one.

`gm_hook` is the harness's client, not yours. The SessionStart, SubagentStart, PreToolUse and PostToolUse hooks call it on your behalf — identity, the pen sheet, the env block, file-change capture — and nothing an agent does is supposed to invoke it. Backups are the kernel's own act, taken automatically before any migration; anything irreversible is put to the Endotherm before it is taken.

### One Kernel, Typed Personalities
`GmPersonality` is the registry: an enum whose raw values are the invoked names, resolved from argv[0] first and `gm_` + argv[1] second, with an exhaustive `run`. Argv[0] wins because `gm_hook call BACKUP` has `call` as argv[1]. `gm_daemon` is the only release-store symlink at the kernel; `gm_mcp` and `gm_hook` are compiled executables shipped in the plugin's `bin/`, and the hook events are in `hooks/bin/`. A bare `gm_kernel` outside an app bundle prints usage and exits 2 — the default that costs data is the one that deliberately does not write.

### Reference
Detail lives beside this file rather than in it — read it only when it names your situation:

- `ref/gmfs_details.md` — The gmfs filesystem layout, the three environments, and how paths and roots resolve. Read before touching anything under $GM_FS_ROOT.
