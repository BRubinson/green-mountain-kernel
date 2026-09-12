import Foundation
import GMCCDaemonKit

// gmcc_hook — the shell-callable client.
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
// THE PASSTHROUGH IS THE POINT. `gmcc_hook call <MESSAGE_TYPE> --json '{...}'`
// reaches every verb the daemon serves in ~80 lines, so deleting the typed CLI
// costs a person at a terminal no capability whatsoever. What it costs is
// discoverability, which is exactly the pressure that should exist: Claude uses
// typed pen tools, and the raw wire is for a human who already knows what they
// want.

let argv = Array(CommandLine.arguments.dropFirst())

guard let command = argv.first else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

switch command {
case "hook":
    // NEVER blocks, NEVER writes to stderr, ALWAYS exits 0. A hook that fails
    // loudly wedges the tool call that triggered it.
    let event = argv.count > 1 ? argv[1] : ""
    let dryRun = argv.contains("--dry-run")
    let stdin = HookRunner.readStdin()
    switch event {
    case "post-tool-use":
        if let line = HookRunner.postToolUse(stdin: stdin, dryRun: dryRun) { print(line) }
    case "subagent-start":
        if let line = HookRunner.subagentStart(stdin: stdin, dryRun: dryRun, sheetText: PenSheet.text) {
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
