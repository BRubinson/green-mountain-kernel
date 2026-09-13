import Foundation
import GmDaemonSdk

// gm_hook — the shell-callable client.
//
// WHY THIS BINARY EXISTS AT ALL, given the pen is Claude's only door: a Claude
// Code hook is a SHELL process. It cannot open an MCP session, and the hook
// contract forbids depending on jq, so it cannot hand-roll JSON over a socket
// either. Something executable has to speak the wire on its behalf. That is the
// whole justification, and it is why this binary carries the hook events, the
// session's context provisioning, daemon lifecycle, and nothing else shaped like
// a workflow verb.
//
// ARGV IS PARSED BY HAND. ArgumentParser is the single dependency the retired
// CLI pulled, and it dies with it — 123 verbs' worth of declarative parsing was
// its justification, and roughly a dozen ops verbs plus a passthrough is not.
//
// THE PASSTHROUGH IS THE POINT. `gm_hook call <MESSAGE_TYPE> --json '{...}'`
// reaches every verb the daemon serves in ~80 lines, so deleting the typed CLI
// costs a person at a terminal no capability whatsoever. What it costs is
// discoverability, which is exactly the pressure that should exist: Claude uses
// typed pen tools, and the raw wire is for a human who already knows what they
// want.
//
// WAS `main.swift`. The sources moved into a LIBRARY target so the one
// multi-call `gm_kernel` Mach-O can carry this personality alongside the MCP
// server and the kernel host; the `gm_hook` executable is now a four-line shim
// over `GmHookCli.main()`. Top-level code is legal only in an executable
// target's `main.swift`, which is the only reason this is a function rather
// than the statements it used to be — the argv contract is byte-identical.

public enum GmHookCli {

    /// The `gm_hook` personality. Takes argv WITHOUT the program name, so the
    /// multi-call dispatcher can hand through exactly what the shell passed —
    /// `gm_hook call BACKUP` has to arrive as `["call", "BACKUP"]` whether it
    /// came through the `gm_hook` symlink or `gm_kernel hook`.
    ///
    /// Never returns: every arm exits, and that is part of the hook contract —
    /// a hook must not fall through to a caller that might print something.
    public static func main(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Never {
        let argv = arguments

        guard let command = argv.first else {
            FileHandle.standardError.write(Data(usage.utf8))
            exit(2)
        }

        switch command {
        case "hook":
            // NEVER blocks, NEVER writes to stderr, ALWAYS exits 0. A hook that
            // fails loudly wedges the tool call that triggered it.
            let event = argv.count > 1 ? argv[1] : ""
            let dryRun = argv.contains("--dry-run")
            let stdin = HookRunner.readStdin()
            switch event {
            case "post-tool-use":
                if let line = HookRunner.postToolUse(stdin: stdin, dryRun: dryRun) { print(line) }
            case "subagent-start":
                if let line = HookRunner.subagentStart(
                    stdin: stdin, dryRun: dryRun, sheetText: PenSheet.text) {
                    print(line)
                }
            default:
                break  // an unknown event is silence, not an error
            }
            exit(0)

        case "call":
            exit(runCall(Array(argv.dropFirst())))

        case "help", "--help", "-h":
            print(usage)
            exit(0)

        default:
            exit(runOps(argv))
        }
    }
}
