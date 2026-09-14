import Foundation

/// The hook surface's ORCHESTRATION, owned by the kit rather than by a
/// front-end binary.
///
/// Every front-end that fronts a Claude Code hook calls these two functions and
/// adds nothing of its own. That is the whole point: the hook contract — never
/// block a tool call, never wedge a spawn, never write to stderr, always exit 0
/// — is a property of THIS code, not of whichever binary the shim happened to
/// exec. When the CLI front-end goes away, the contract does not move with it.
///
/// NEITHER FUNCTION THROWS. A hook that throws prints and exits non-zero, which
/// is exactly the noise a hook may not produce. Every failure path returns
/// quietly.
public enum HookRunner {

    /// Record the file changes one tool call made.
    ///
    /// The path set is decided by a NAMED ALLOWLIST of tools, so a hook manifest
    /// that fires this for something else records nothing rather than inventing
    /// a change from a `file_path` that was only ever read.
    ///
    /// - Returns: the dry-run report when `dryRun` is set, otherwise nil.
    /// - Parameter caller: how to reach the daemon. `nil` opens a short-lived
    ///   socket client, which is what the shell-form hook front-end does. The
    ///   kernel passes its own in-process caller instead, so a `HOOK_EVENT`
    ///   served in-process does not dial the daemon it is already inside — that
    ///   would be a self-connection queued behind the very call that must
    ///   service it, which is a deadlock rather than a slow path.
    public static func postToolUse(
        stdin: Data, dryRun: Bool, caller: (any GmVerbCaller)? = nil
    ) -> String? {
        guard let payload = HookPayload.decode(stdin), let cwd = payload.cwd else {
            return nil
        }
        // BEFORE ANY OTHER WORK: Paths.root resolves GM_FS_ROOT once per process,
        // and DaemonClient resolves the socket through it.

        // CHEAPEST QUESTION FIRST. The manifest fires this hook on every Bash
        // call, and most Bash traffic writes nothing — `ls`, `cat`, `grep`,
        // `git log`. Deciding whether a payload NAMES a write is pure string
        // work, while GitContext.detect costs two subprocess forks.
        guard HookWriteTargets.mayHaveTargets(payload: payload) else { return nil }

        // Identity comes from the PAYLOAD's cwd. The hook process's own working
        // directory is not the tool call's, and resolving against it files the
        // change under whatever repo the hook happened to be launched in.
        guard let git = try? GitContext.detect(in: cwd) else { return nil }
        let targets = HookWriteTargets.resolve(payload: payload, repoRoot: git.repoRoot)
        guard !targets.isEmpty else { return nil }

        let context = ContextBuilder.ensureRequest(for: git)
        let changes = targets.map { target in
            FileChangeAdd(
                project: context.project,
                instance: context.instance,
                session: context.session,
                relativePath: target.relativePath,
                changeKind: target.changeKind,
                ranges: target.ranges,
                // The daemon resolves the prompt from the binding this payload's
                // session_id names. There is no clientKey to send: the field does
                // not exist, which is what makes the split from the activation
                // ladder structural.
                autoAttribute: true,
                agentId: payload.agentId,
                origin: target.origin,
                claudeSessionId: payload.sessionId,
                claudeTurnId: payload.claudeTurnId,
                toolUseId: payload.toolUseId,
                toolName: payload.toolName,
                agentType: payload.agentType,
                permissionMode: payload.permissionMode,
                durationMs: payload.durationMs,
                transcriptPath: payload.transcriptPath)
        }

        if dryRun {
            return encodeJSON(HookDryRun(
                event: payload.hookEventName ?? "PostToolUse",
                repoRoot: git.repoRoot,
                gmFsRoot: Paths.root.path,
                changes: changes))
        }
        // Per-change `try?`: one refused path must not cost the others their
        // row, and a refusal is already durable daemon-side. A dead daemon loses
        // the write — with one capture method there is no net under it.
        _ = try? withKitClient(caller) { client in
            for change in changes { _ = try? client.addFileChange(change) }
        }
        return nil
    }

    /// Register the spawned agent's IDENTITY half and hand it its context.
    ///
    /// Registration here is what makes agent_id mean something: every spawn
    /// shape fires SubagentStart carrying agent_id, so this beats the agent to
    /// any write it could make.
    ///
    /// - Parameter sheetText: the context block handed to the spawning agent.
    ///   Injected rather than reached for, so the kit does not depend on whose
    ///   sheet it is — the generated pen sheet, today, and nothing else once the
    ///   CLI's is gone.
    /// - Returns: the JSON line to print on stdout (the dry-run report under
    ///   `dryRun`, otherwise the SubagentStart `additionalContext` response).
    /// - Parameter caller: see `postToolUse(stdin:dryRun:caller:)`.
    public static func subagentStart(
        stdin: Data, dryRun: Bool, sheetText: String, caller: (any GmVerbCaller)? = nil
    ) -> String? {
        // The cwd is still REQUIRED even though nothing here reads it: a payload
        // without one is a payload this hook cannot trust, and returning nil is
        // the silent no-op the contract asks for. It used to be consumed by the
        // snapshot-marker walk, which is gone with the sandbox — but the guard
        // outlived its consumer on purpose, because "no cwd" still means "not a
        // hook firing in a repo we can identify".
        guard let payload = HookPayload.decode(stdin), payload.cwd != nil else {
            return nil
        }

        // The gmcc session and prompt are NOT resolved here. The daemon derives
        // both from claude_session_id through the binding, so a registration and
        // a file_change can never disagree about which session a conversation
        // belongs to.
        let registration = payload.agentId.map { agentId in
            AgentRegisterRequest(
                agentId: agentId,
                agentType: payload.agentType,
                claudeSessionId: payload.sessionId,
                claudeTurnId: payload.claudeTurnId)
        }
        if dryRun {
            return encodeJSON(SubagentStartDryRun(
                event: payload.hookEventName ?? "SubagentStart",
                gmFsRoot: Paths.root.path,
                registration: registration))
        }

        // REGISTRATION FAILURE IS ANNOUNCED, NOT SWALLOWED. An agent whose
        // registration never landed writes rows nothing can attribute, and the
        // old silent `try?` meant it learned that never. It is told at birth, in
        // the one channel it is guaranteed to read.
        var warning = ""
        var stub = ""
        if registration == nil {
            warning = "[GMB] WARNING: this spawn carried no agent_id, so no agent_registration row exists for you. Your file changes cannot be attributed to you — report this rather than working around it."
        }
        _ = try? withKitClient(caller) { client in
            if let registration {
                if (try? client.agentRegister(registration)) == nil {
                    warning = "[GMB] WARNING: your agent registration did not land. Your file changes will not be attributed to you — report this rather than working around it."
                }
            }
            // cwd → session resolution is client-side; no session is a silent
            // empty stub, never an error.
            if let sessionUuid = try? ContextBuilder.resolveSessionUuid(client) {
                stub = (try? client.briefingStub(BriefingStubRequest(
                    agentType: payload.agentType,
                    sessionUuid: sessionUuid,
                    clientKey: ClientKey.resolve())).stub) ?? ""
            }
        }

        var context = sheetText
        if !warning.isEmpty { context += "\n\n" + warning }
        if !stub.isEmpty { context += "\n\n" + stub }
        return additionalContextLine(context)
    }

    // MARK: - Front-end helpers

    /// Read the whole raw payload from stdin. Front-ends call this rather than
    /// each rolling their own read loop.
    public static func readStdin() -> Data {
        FileHandle.standardInput.readDataToEndOfFile()
    }

    /// Claude Code's hook response shape, whose keys are camelCase — so it is
    /// built with JSONSerialization rather than through WireCodec, which
    /// snake_cases everything it touches.
    private static func additionalContextLine(_ context: String) -> String? {
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "SubagentStart",
                "additionalContext": context,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        // WireCodec, not a bare JSONEncoder: DTOs carry no CodingKeys, so only
        // the shared snake_case strategy keeps this output matching the wire
        // keys that skills and bot docs grep for.
        guard let data = try? WireCodec.prettyEncoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Open a client, run one body, always close. The hook's own variant: unlike a
/// front-end's, it maps NO error onto an exit code, because a hook has no exit
/// code to map onto — every failure here is swallowed by the caller's `try?`
/// and the hook returns quietly.
/// Runs `body` against a verb caller, opening a short-lived socket client only
/// when one was not supplied.
///
/// THE INJECTED CASE IS NOT AN OPTIMISATION. When the kernel serves `HOOK_EVENT`
/// it passes its own in-process caller; opening a `DaemonClient` there would
/// connect the kernel to itself, on the serial queue that would have to answer
/// — a deadlock. The `nil` default keeps every existing shell-form front-end
/// reading exactly as it did.
///
/// Only the socket case is closed, because only the socket case was opened here.
private func withKitClient<T>(
    _ caller: (any GmVerbCaller)?,
    _ body: (any GmVerbCaller) throws -> T
) throws -> T {
    if let caller { return try body(caller) }
    let client = DaemonClient()
    defer { client.close() }
    return try body(client)
}
