import Foundation

/// DENY a Bash command that invokes `gm_hook` or a generated hook executable.
///
/// Those binaries are the HARNESS'S clients: the hooks call them without
/// passing through the Bash tool, so this guard cannot fire on them. Blocking
/// every invocation also subsumes capture forgery, since a capture row can only
/// be hand-written through a binary this denies. Pure string work, no socket,
/// so the deny holds with no kernel installed.
enum PreToolUseHook: GmHook {

    static let event: GmHookEvent = .preToolUse

    static let matcher: String? = "Bash"

    static let timeout: Int? = 5

    /// - Returns: the deny response line when the command invokes a hook
    ///   binary, otherwise nil for silence. Exit is 0 either way — the
    ///   DECISION rides the JSON.
    static func run(_ context: GmHookContext) -> String? {
        guard let payload = HookPayload.decode(context.stdin),
            payload.toolName == "Bash",
            let command = payload.command, !command.isEmpty,
            GmHookSupport.invokesGmHook(command)
        else { return nil }
        let reason =
            "[GMB] denied: `gm_hook` and the `gm_hook_*` executables are the harness's own "
            + "clients — the SessionStart, SubagentStart, PreToolUse and PostToolUse hooks call "
            + "them; an agent never does. Every agent-facing verb is a pen tool "
            + "(\(CdeToolSpec.qualifiedName("*"))). A verb with no pen tool is a missing door to "
            + "REPORT to "
            + "the Endotherm, not a shell to reach for. File-change capture belongs to the "
            + "PostToolUse hook alone."
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": event.rawValue,
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            ],
            "systemMessage": reason,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Record the file changes one tool call made.
///
/// The path set is decided by a NAMED ALLOWLIST of tools, so a hook manifest
/// that fires this for something else records nothing rather than inventing a
/// change from a `file_path` that was only ever read. The matcher below is the
/// same set, spelled for the harness.
enum PostToolUseHook: GmHook {

    static let event: GmHookEvent = .postToolUse

    static let matcher: String? = "Edit|Write|NotebookEdit|Bash"

    /// PostToolUse is the hottest hook in the system; synchronous would put a
    /// socket round trip on every Bash call.
    static let isAsync = true

    /// - Returns: the dry-run report when `dryRun` is set, otherwise nil.
    static func run(_ context: GmHookContext) -> String? {
        guard let payload = HookPayload.decode(context.stdin), let cwd = payload.cwd else {
            return nil
        }
        // CHEAPEST QUESTION FIRST. Most Bash traffic writes nothing, and deciding
        // whether a payload NAMES a write is pure string work, while
        // GitContext.detect costs two subprocess forks.
        guard HookWriteTargets.mayHaveTargets(payload: payload) else { return nil }

        // Identity comes from the PAYLOAD's cwd. The hook process's own working
        // directory is not the tool call's.
        guard let git = try? GitContext.detect(in: cwd) else { return nil }
        let targets = HookWriteTargets.resolve(payload: payload, repoRoot: git.repoRoot)
        guard !targets.isEmpty else { return nil }

        let gmContext = ContextBuilder.ensureRequest(for: git)
        let changes = targets.map { target in
            FileChangeAdd(
                project: gmContext.project,
                instance: gmContext.instance,
                session: gmContext.session,
                relativePath: target.relativePath,
                changeKind: target.changeKind,
                ranges: target.ranges,
                // The daemon resolves the prompt from the binding this payload's
                // session_id names; there is no clientKey to send.
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
                transcriptPath: payload.transcriptPath
            )
        }

        if context.dryRun {
            return GmHookSupport.encodeJSON(
                HookDryRun(
                    event: payload.hookEventName ?? event.rawValue,
                    repoRoot: git.repoRoot,
                    gmFsRoot: Paths.root.path,
                    changes: changes
                )
            )
        }
        // Per-change `try?`: one refused path must not cost the others their
        // row. A dead daemon loses the write — there is no net under it.
        _ = try? GmHookSupport.withKitClient(context.caller) { client in
            for change in changes { _ = try? client.addFileChange(change) }
        }
        return nil
    }
}

/// Register the spawned agent's IDENTITY half and hand it its context.
///
/// Every spawn shape fires SubagentStart carrying agent_id, so this beats the
/// agent to any write it could make.
enum SubagentStartHook: GmHook {

    static let event: GmHookEvent = .subagentStart

    static let timeout: Int? = 5

    /// The fuller sheet: `CdeSheet.text` is what a spawning agent receives,
    /// on both transports.
    static var sheetText: String { CdeSheet.text }

    /// - Returns: the dry-run report under `dryRun`, otherwise the
    ///   `additionalContext` response line.
    static func run(_ context: GmHookContext) -> String? {
        // The cwd is REQUIRED even though nothing here reads it: "no cwd" means
        // a hook not firing in a repo we can identify, so the payload cannot be
        // trusted, and nil is the silent no-op the contract asks for.
        guard let payload = HookPayload.decode(context.stdin), payload.cwd != nil else {
            return nil
        }

        // The gmcc session and prompt are NOT resolved here. The daemon derives
        // both from claude_session_id through the binding.
        let registration = payload.agentId.map { agentId in
            AgentRegisterRequest(
                agentId: agentId,
                agentType: payload.agentType,
                claudeSessionId: payload.sessionId,
                claudeTurnId: payload.claudeTurnId
            )
        }
        if context.dryRun {
            return GmHookSupport.encodeJSON(
                SubagentStartDryRun(
                    event: payload.hookEventName ?? event.rawValue,
                    gmFsRoot: Paths.root.path,
                    registration: registration
                )
            )
        }

        // REGISTRATION FAILURE IS ANNOUNCED, NOT SWALLOWED. It is told at
        // birth, in the one channel the agent is guaranteed to read.
        var warning = ""
        var stub = ""
        if registration == nil {
            warning =
                "[GMB] WARNING: this spawn carried no agent_id, so no agent_registration row exists for you. Your file changes cannot be attributed to you — report this rather than working around it."
        }
        _ = try? GmHookSupport.withKitClient(context.caller) { client in
            if let registration {
                if (try? client.agentRegister(registration)) == nil {
                    warning =
                        "[GMB] WARNING: your agent registration did not land. Your file changes will not be attributed to you — report this rather than working around it."
                }
            }
            // cwd → session resolution is client-side; no session is a silent
            // empty stub, never an error.
            if let sessionUuid = try? ContextBuilder.resolveSessionUuid(client) {
                stub =
                    (try? client.briefingStub(
                        BriefingStubRequest(
                            agentType: payload.agentType,
                            sessionUuid: sessionUuid,
                            clientKey: ClientKey.resolve()
                        )
                    )
                    .stub) ?? ""
            }
        }

        var text = sheetText
        if !warning.isEmpty { text += "\n\n" + warning }
        if !stub.isEmpty { text += "\n\n" + stub }
        return GmHookSupport.additionalContextLine(event: event, text)
    }
}
