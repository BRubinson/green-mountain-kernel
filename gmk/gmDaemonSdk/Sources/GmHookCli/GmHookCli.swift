import Foundation
import GmDaemonSdk

// gm_hook — the shell-callable client.
//
// A Claude Code hook is a SHELL process: it cannot open an MCP session, and the
// hook contract forbids depending on jq, so something executable has to speak
// the wire on its behalf. That is why this binary carries the hook events, the
// session's context provisioning and daemon lifecycle, and nothing shaped like
// a workflow verb. ARGV IS PARSED BY HAND, since a dozen ops verbs plus a
// passthrough does not justify a parsing dependency.

// THE PASSTHROUGH IS THE POINT: `gm_hook call <MESSAGE_TYPE> --json '{...}'`
// reaches every verb the daemon serves, so a person at a terminal loses no
// capability. What it costs is discoverability, which is the pressure that
// should exist — Claude uses typed pen tools, and the raw wire is for a human
// who already knows what they want.

// A LIBRARY target, so the multi-call `gm_kernel` Mach-O can carry this
// personality alongside the MCP server and the kernel host. Top-level code is
// legal only in an executable target's `main.swift`, which is why this is a
// function rather than statements.

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
            case "pre-tool-use":
                if let line = HookRunner.preToolUse(stdin: stdin) { print(line) }
            case "post-tool-use":
                if let line = HookRunner.postToolUse(stdin: stdin, dryRun: dryRun) { print(line) }
            case "subagent-start":
                if let line = HookRunner.subagentStart(
                    stdin: stdin,
                    dryRun: dryRun,
                    sheetText: CdeSheet.text
                ) {
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
