import Foundation

let GM_CONCEPT_KERNEL = """
    ## The Kernel: One Binary, Sole Writer, One Root

    **ONE Mach-O**, `gm_kernel` — the sole entity that touches `~/gmfs/gm.db` (the SQLite database). It dispatches on `basename(argv[0])` to answer as `gm_daemon` (persistent server), `gm_mcp` (the MCP server Claude records through), or `gm_hook` (shell-callable client). Those three names are symlinks in `~/gmfs/bin/`, not separate binaries.

    ### The Single Writer Guarantee
    `gm_daemon` is the **sole writer to the database**. Every other process — the app, Claude hooks, tools, the MCP server — is a socket client. The database is APPEND-ONLY history: never wipe it, never delete rows. A wrong row is corrected by writing again.

    ### The Filesystem Root
    `~/gmfs` (`$GM_FS_ROOT`) is the one filesystem root per environment: its own db, socket, pidfile, `flock`, release store and repo clone. Write containment is enforced, not advisory — `Paths.assertContained(_:)` throws unless a write lands under `$GM_FS_ROOT` or the working repo. The Endotherm's work lives inside this boundary.

    ### Which Door to Use
    - **MCP tools** (typed, versioned): wherever one exists. They thread `expected_version` and they are the write path.
    - **Passthrough**: `gm_hook call <MESSAGE_TYPE> --json '{...}'` for a verb with no MCP tool. Keys are snake_case; wire fields are the authority.
    - **Before risky work**: `gm_hook call BACKUP --json '{}'` takes the sanctioned online backup.

    ### Three Personalities, One Binary
    Argv[0] wins: `gm_hook call BACKUP` has `call` as argv[1], so subcommand-first dispatch would go wrong. The dispatcher reads argv[0] and only then a subcommand. A bare `gm_kernel` prints usage and exits 2 — the default that costs data is the one that deliberately does not write.
    """
