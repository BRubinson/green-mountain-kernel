import Foundation
import GmDaemonSdk
import GmHookCli
import GmKernelHost
import GmMcpServer

// gm_kernel — the multi-call dispatcher.
//
// ── DISPATCH ORDER: argv[0] WINS, AND THAT IS NOT A PREFERENCE ──────────────
//
// `gm_hook call BACKUP --json '{...}'` arrives with argv[1] == "call". A
// subcommand-first rule would try to dispatch `call` as a personality, fail, and
// break the one caller that fires on every tool use. So the binary looks at the
// NAME it was invoked under first, and only consults a subcommand when that name
// carries no meaning.
//
// The `~/gmfs/bin` symlinks (`gm_daemon`, `gm_mcp`, `gm_hook`) are what make
// argv[0] meaningful, which is why they are part of the release-store contract
// rather than a convenience.
//
// ── A BARE INVOCATION IS NOT A WRITER ───────────────────────────────────────
//
// `gm_kernel` with no personality prints usage and exits 2. It deliberately does
// NOT default to the daemon. Of every possible dispatch default this is the one
// that could cost data: a stray invocation — a typo, a script losing an argument,
// a launchd plist with an empty ProgramArguments — must not quietly become a
// process that opens the database.
//
// The GUI kernel is not reachable from here either. The app bundle is its own
// executable; this binary is the CLI half, and it has no AppKit linked.

// `usage` IS DECLARED BEFORE THE DISPATCH ON PURPOSE. Top-level code in
// `main.swift` executes sequentially, so a `let` referenced above its own
// declaration is read before it is initialized — which is a SIGSEGV at runtime,
// not a compile error. This file crashed exactly that way with the string at the
// bottom, and only on the paths that printed it, so `--version` looked fine.

let usage = """
    gm_kernel — the GM kernel binary. One Mach-O, three personalities.

    USAGE
      gm_kernel <personality> [args...]
      <personality>                     (via the ~/gmfs/bin symlinks)

    PERSONALITIES
      daemon     the headless single-writer host. Also reached as `gm_daemon`.
                 The app bundle hosts the same server; this is the fallback that
                 `DaemonClient.autostart()` spawns from hooks, SSH and CI, where
                 LaunchServices cannot launch an application.
      mcp        the pen server: JSON-RPC 2.0 over stdio, spawned per Claude
                 session by the harness. Also reached as `gm_mcp`.
      hook       the shell-callable client and raw-wire passthrough. Also reached
                 as `gm_hook`.

      --version  protocol version
      --help     this text

    WHY argv[0] TAKES PRECEDENCE
      `gm_hook call BACKUP` has "call" as its first argument. Dispatching on the
      subcommand first would try to run `call` as a personality and break the
      hook path, so the invoked NAME is consulted before any argument.

    A BARE `gm_kernel` EXITS 2 AND OPENS NOTHING
      Defaulting to the daemon would let a typo or a script that lost an argument
      silently become a process holding the database.
    """

let arguments = CommandLine.arguments
let invokedAs = URL(fileURLWithPath: arguments.first ?? "gm_kernel").lastPathComponent
let rest = Array(arguments.dropFirst())

/// Personalities, keyed by the name the binary was invoked under.
///
/// The subcommand spellings are the same words without the `gm_` prefix. They
/// exist for discoverability — argv[0] dispatch is invisible to anyone reading
/// `--help` — and they collide with none of `gm_hook`'s own first arguments
/// (`call`, `context`, `paths`, `verbs`, `pen-sheet`, `help`).
switch invokedAs {
case "gm_daemon":
    KernelHost.bootHeadlessAndRun()

case "gm_mcp":
    GmMcpServer.main()
    exit(0)

case "gm_hook":
    // argv passed through UNTOUCHED: the hook contract is byte-identical
    // whichever door it came through.
    GmHookCli.main(rest)

default:
    // Invoked as `gm_kernel` (or anything else) — consult a subcommand.
    switch rest.first {
    case "daemon":
        KernelHost.bootHeadlessAndRun()

    case "mcp":
        GmMcpServer.main()
        exit(0)

    case "hook":
        GmHookCli.main(Array(rest.dropFirst()))

    case "--version", "version":
        // So `.gm_version` stops being the only thing that can answer "what is
        // actually installed here".
        print("gm_kernel protocol v\(GmWireProtocol.version)")
        exit(0)

    case "--help", "-h", "help":
        print(usage)
        exit(0)

    default:
        FileHandle.standardError.write(Data(usage.utf8))
        exit(2)
    }
}
