import Foundation

// gm_hook — the shell-callable client.
//
// The SessionStart script cannot open an MCP session and may not depend on jq,
// so this binary speaks the wire on its behalf: context provisioning, daemon
// lifecycle, nothing shaped like a workflow verb. The hook EVENTS are not here;
// each is a generated executable under the plugin's hooks/bin (GmHookEvent).
// ARGV IS PARSED BY HAND: a dozen ops verbs do not justify a parsing dependency.

// THE PASSTHROUGH IS THE POINT: `gm_hook call <MESSAGE_TYPE> --json '{...}'`
// reaches every verb the daemon serves, so a person at a terminal loses no
// capability. What it costs is discoverability, which is the pressure that
// should exist — Claude uses typed pen tools, and the raw wire is for a human
// who already knows what they want.

// Reached three ways, all through `main(_:)`: the plugin's own `bin/gm_hook`
// executable (compiled with the client closure), `gm_kernel hook …`, and the
// in-app `GmPersonality.hook` arm. A function rather than top-level code, so
// every door hands in the same argv.

enum HookCli {

    /// The `gm_hook` personality. Takes argv WITHOUT the program name, so the
    /// multi-call dispatcher can hand through exactly what the shell passed —
    /// `gm_hook call BACKUP` has to arrive as `["call", "BACKUP"]` whether it
    /// came through the `gm_hook` symlink or `gm_kernel hook`.
    ///
    /// Never returns: every arm exits, and that is part of the hook contract —
    /// a hook must not fall through to a caller that might print something.
    static func main(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Never {
        let argv = arguments

        guard let command = argv.first else {
            FileHandle.standardError.write(Data(hookUsage.utf8))
            exit(2)
        }

        switch command {
        case "hook":
            // RETIRED SPELLING, kept silent on purpose. A plugin cache older
            // than this binary still runs `gm_hook hook <event>`, and the hook
            // contract is exit 0 with no output — falling through to "unknown
            // command" would exit 2 and BLOCK every tool call on that machine.
            exit(0)

        case "call":
            exit(runCall(Array(argv.dropFirst())))

        case "help", "--help", "-h":
            FileHandle.standardOutput.write(Data(hookUsage.utf8))
            exit(0)

        default:
            exit(runOps(argv))
        }
    }
}
