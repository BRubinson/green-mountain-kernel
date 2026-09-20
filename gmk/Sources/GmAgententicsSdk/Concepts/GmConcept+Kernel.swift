import Foundation

/// COMPUTED, NOT A CONSTANT: the reference index at the bottom is built from
/// `GmBridgeResource.all`, so a document declared under this skill is cited
/// here automatically and one removed stops being cited. See `GM_CONCEPT_GMCC`.
var GM_CONCEPT_KERNEL: String {
    """
    ## The Kernel: One Binary, Sole Writer, One Root

    **ONE Mach-O**, `gm_kernel` — the sole entity that touches `~/gmfs/gm.db` (the SQLite database). It dispatches on `basename(argv[0])` to answer as `gm_daemon` (persistent server), `gm_mcp` (the MCP server Claude records through), or `gm_hook` (shell-callable client). Those three names are symlinks in `~/gmfs/bin/`, not separate binaries.

    ### The Single Writer Guarantee
    `gm_daemon` is the **sole writer to the database**. Every other process — the app, Claude hooks, tools, the MCP server — is a socket client. The database is APPEND-ONLY history: never wipe it, never delete rows. A wrong row is corrected by writing again.

    ### The Filesystem Root
    `~/gmfs` (`$GM_FS_ROOT`) is the one filesystem root per environment: its own db, socket, pidfile, `flock`, release store and repo clone. Write containment is enforced, not advisory — `Paths.assertContained(_:)` throws unless a write lands under `$GM_FS_ROOT` or the working repo. The Endotherm's work lives inside this boundary.

    ### The One Door
    The pen — `mcp__plugin_gmcc_cde__*`, served by `gm_mcp` — is the ONLY door an agent uses. Its tools are typed, they thread `expected_version`, and their output is budgeted. A verb with no pen tool is a missing door: REPORT it to the Endotherm. There is no shell door, and the PreToolUse hook DENIES a Bash command that reaches for one.

    `gm_hook` is the harness's client, not yours. The SessionStart, SubagentStart, PreToolUse and PostToolUse hooks call it on your behalf — identity, the pen sheet, the env block, file-change capture — and nothing an agent does is supposed to invoke it. Backups are the kernel's own act, taken automatically before any migration; anything irreversible is put to the Endotherm before it is taken.

    ### Three Personalities, One Binary
    Argv[0] wins: the hook launcher runs `gm_hook hook post-tool-use`, where `hook` is argv[1], so subcommand-first dispatch would go wrong. The dispatcher reads argv[0] and only then a subcommand. A bare `gm_kernel` prints usage and exits 2 — the default that costs data is the one that deliberately does not write.

    ### Reference
    Detail lives beside this file rather than in it — read it only when it names your situation:

    \(GmBridgeResource.index(for: "kernel"))
    """
}
