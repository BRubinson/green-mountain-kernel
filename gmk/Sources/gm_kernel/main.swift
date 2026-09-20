import Foundation
import SwiftUI

// gm_kernel — the multi-call dispatcher. One Mach-O: the CLI in ~/gmfs/bin and
// the executable inside gm_kernel.app are the same file.
//
// argv[0] WINS over argv[1]: `gm_hook call BACKUP` arrives with argv[1] == "call",
// so a subcommand-first rule would dispatch `call` as a personality. A bare
// `gm_kernel` OUTSIDE an app bundle prints usage and exits 2 rather than
// defaulting to the daemon: a stray invocation must not quietly open the
// database. Inside gm_kernel.app a bare launch is LaunchServices; it runs the app.

// `usage` IS DECLARED BEFORE THE DISPATCH ON PURPOSE. Top-level code in
// `main.swift` executes sequentially, so a `let` referenced above its own
// declaration is read before initialization — a SIGSEGV at runtime rather than a
// compile error, and only on the paths that print it.

let usage = """
    gm_kernel — the GM kernel binary. One Mach-O, five personalities.

    USAGE
      gm_kernel <personality> [args...]
      <personality>                     (via the ~/gmfs/bin symlinks)

    PERSONALITIES
      daemon     the headless single-writer host. Also reached as `gm_daemon`.
                 The app hosts the same server; this is the fallback that
                 `DaemonClient.autostart()` spawns from hooks, SSH and CI, where
                 LaunchServices cannot launch an application.
      mcp        the pen server: JSON-RPC 2.0 over stdio, spawned per Claude
                 session by the harness. Also reached as `gm_mcp`.
      hook       the shell-callable client and raw-wire passthrough. Also reached
                 as `gm_hook`.
      bridge     the plugin generator: `gm_kernel bridge [--check] <plugin-dir>`
                 emits the Claude Code plugin from the bridge values.
      app        the GM Vibes app. This is what a launch from inside
                 gm_kernel.app runs with no arguments at all.

      --version  protocol version
      --help     this text

    WHY argv[0] TAKES PRECEDENCE
      `gm_hook call BACKUP` has "call" as its first argument. Dispatching on the
      subcommand first would try to run `call` as a personality and break the
      hook path, so the invoked NAME is consulted before any argument.

    A BARE `gm_kernel` OUTSIDE AN APP BUNDLE EXITS 2 AND OPENS NOTHING
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
    MainActor.assumeIsolated { GmMcpServer.main() }
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
        MainActor.assumeIsolated { GmMcpServer.main() }
        exit(0)

    case "hook":
        GmHookCli.main(Array(rest.dropFirst()))

    case "bridge":
        GmBridgeCli.main(Array(rest.dropFirst()))

    case "app":
        MainActor.assumeIsolated { GMVibesApp.main() }

    case nil where Bundle.main.bundleURL.pathExtension == "app":
        // LaunchServices passes no arguments; the bundle is what says "app".
        MainActor.assumeIsolated { GMVibesApp.main() }

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
