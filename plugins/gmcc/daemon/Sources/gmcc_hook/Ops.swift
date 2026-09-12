import Foundation
import GMCCDaemonKit

let usage = """
gmcc_hook — the shell-callable GMCC client.

Claude records through the pen (the MCP server). This binary exists for the two
callers that cannot: a shell hook, and a person at a terminal.

  hook post-tool-use [--dry-run]     record what one tool call wrote
  hook subagent-start [--dry-run]    register a spawned agent, emit its context

  context ensure [--hook-payload]    provision project/instance/session from $PWD + branch
  context env [--plugin-root P]      emit the session env block
  daemon start|stop|restart|status   lifecycle. THE ONLY THING THAT BUILDS is
                                     scripts/build_daemon.sh — never a connect path.
  paths [--json]                     resolved runtime roots
  status | ping | doctor | backup    health and safety
  verbs [--json] [--writes-only]     the verb catalogue: MessageType, pen tool, read/write
  sandbox refresh|status             snapshot dev environment

  call <MESSAGE_TYPE> [--json '<payload>' | --json-file <path>]
                                     the raw wire. Every verb the daemon serves,
                                     including those with no named command here.

"""

private func emit<T: Encodable>(_ value: T) {
    guard let data = try? WireCodec.prettyEncoder.encode(value),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}

private func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("[GMB] \(message)\n".utf8))
    return 1
}

/// The named ops verbs. Deliberately a short list: anything shaped like a
/// workflow verb belongs on the pen, and anything rarer than these is reachable
/// through `call` without needing a name here.
func runOps(_ argv: [String]) -> Int32 {
    let command = argv[0]
    let rest = Array(argv.dropFirst())

    switch command {
    case "context":
        return runContext(rest)

    case "daemon":
        let action = rest.first ?? "status"
        switch action {
        case "status", "ping":
            // Deliberately does NOT autostart: "is it up" must not be a
            // question that starts it.
            let client = DaemonClient(autostart: false)
            defer { client.close() }
            do { emit(try client.ping()); return 0 } catch { return fail("daemon unreachable: \(error)") }
        default:
            return fail("""
                daemon \(action) is not served here. Lifecycle is scripts/build_daemon.sh \
                (build + install) and the launchd job; this binary never builds.
                """)
        }

    case "paths":
        let client = DaemonClient()
        defer { client.close() }
        do { emit(try client.pathsGet()); return 0 } catch { return fail("\(error)") }

    case "status":
        let client = DaemonClient()
        defer { client.close() }
        do { emit(try client.status()); return 0 } catch { return fail("\(error)") }

    case "ping":
        let client = DaemonClient()
        defer { client.close() }
        do { emit(try client.ping()); return 0 } catch { return fail("\(error)") }

    case "verbs":
        // PURELY LOCAL, and it must stay that way: the PreToolUse write guard
        // shells out to this on the Bash hot path, and a guard that needed a
        // live daemon would fail closed exactly when the daemon is down.
        let writesOnly = argv.contains("--writes-only")
        emit(VerbLedger.build(writesOnly: writesOnly))
        return 0

    case "pen-sheet":
        // The generated agent sheet, for inspection. Same text SubagentStart
        // hands a spawning agent.
        print(PenSheet.text)
        return 0

    default:
        FileHandle.standardError.write(Data("[GMB] unknown command '\(command)'\n\n\(usage)".utf8))
        return 2
    }
}

private func runContext(_ argv: [String]) -> Int32 {
    let action = argv.first ?? ""
    switch action {
    case "ensure":
        // --hook-payload: SessionStart pipes its raw hook JSON in, and the
        // claude_session_id is read out of it HERE rather than sliced out in
        // shell, so the hook never needs jq and the decode is covered by the
        // same tolerant reader every other hook uses.
        var claudeSessionId: String?
        if argv.contains("--hook-payload") {
            claudeSessionId = HookPayload.decode(HookRunner.readStdin())?.sessionId
        }
        let client = DaemonClient()
        defer { client.close() }
        do {
            let request = try ContextBuilder.ensureRequest(claudeSessionId: claudeSessionId)
            emit(try client.ensureContext(request))
            return 0
        } catch {
            return fail("\(error)")
        }

    case "env":
        var pluginRoot: String?
        if let index = argv.firstIndex(of: "--plugin-root"), index + 1 < argv.count {
            pluginRoot = argv[index + 1]
        }
        return emitSessionEnv(pluginRoot: pluginRoot)

    default:
        return fail("context takes `ensure` or `env`")
    }
}
