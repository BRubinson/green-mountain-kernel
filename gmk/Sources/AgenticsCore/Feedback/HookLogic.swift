import Foundation

// The HARNESS-FACING half of the hook surface: Claude Code's hook payload as a
// Swift type, the dry-run reports, and the write targets a payload resolves to.
// Everything here is shaped by Claude Code's hook contract. The shell scanner
// that answers "what would this command write?" is generic and lives in
// Util/BashWritePaths.swift. Types stay INTERNAL; the GmHook handlers are the
// only callers that need them.

// MARK: - Dry-run reports

/// What `--dry-run` prints: the resolved roots plus the exact payloads the
/// live path would send.
///
/// The flag is load-bearing rather than a convenience — capture is proven
/// through it before a hook script points at any of this.
struct HookDryRun: Encodable {
    let event: String
    let repoRoot: String
    /// The runtime this write would land in.
    ///
    /// Exactly one value is legitimate, so anything unexpected here means
    /// a misconfigured environment.
    let gmFsRoot: String
    let changes: [FileChangeAdd]
}

struct SubagentStartDryRun: Encodable {
    let event: String
    let gmFsRoot: String
    let registration: AgentRegisterRequest?
}

// MARK: - The payload

/// One Claude Code hook payload, decoded from the raw JSON on stdin.
///
/// EVERY FIELD IS OPTIONAL AND EVERY DECODE IS TOLERANT. The shape varies by
/// event and by tool, so a strict decode would throw on a sibling field and
/// lose a recordable change: a missing field means "not recorded", never
/// "fail". Keys are spelled literally rather than via a key strategy, because
/// the top level is snake_case and `structuredPatch` is camelCase and no
/// single strategy reads both.
struct HookPayload: Equatable {
    let sessionId: String?
    let hookEventName: String?
    let cwd: String?
    let transcriptPath: String?
    let permissionMode: String?
    let toolName: String?
    let toolUseId: String?
    let durationMs: Int?
    /// THE TRAP.
    ///
    /// The payload field is named `prompt_id` and it is Claude Code's TURN
    /// id — it has nothing to do with a gmcc prompt uuid. It carries the
    /// distinct name from the moment it is decoded, so the confusion has
    /// nowhere to start.
    let claudeTurnId: String?
    /// PRESENT for every spawned agent, ABSENT for the primary.
    ///
    /// That absence is the discriminator — there is no heuristic anywhere
    /// in this path.
    let agentId: String?
    /// A LABEL, never a role: it is the subagent_type for a plain subagent,
    /// the literal `workflow-subagent` for a bare workflow agent, and the
    /// NAME for a named teammate.
    ///
    /// Authority comes from AGENT_REGISTER.
    let agentType: String?
    let filePath: String?
    let notebookPath: String?
    let command: String?
    let structuredPatch: [StructuredPatchHunk]

    /// Decodes a hook payload from JSON data.
    /// - Parameter data: The JSON data to decode.
    /// - Returns: The decoded hook payload, or `nil` if parsing fails.
    static func decode(_ data: Data) -> HookPayload? {
        guard !data.isEmpty,
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let input = root["tool_input"] as? [String: Any] ?? [:]
        let response = root["tool_response"] as? [String: Any] ?? [:]
        return HookPayload(
            sessionId: string(root["session_id"]),
            hookEventName: string(root["hook_event_name"]),
            cwd: string(root["cwd"]),
            transcriptPath: string(root["transcript_path"]),
            permissionMode: string(root["permission_mode"]),
            toolName: string(root["tool_name"]),
            toolUseId: string(root["tool_use_id"]),
            durationMs: (root["duration_ms"] as? NSNumber)?.intValue,
            claudeTurnId: string(root["prompt_id"]),
            agentId: string(root["agent_id"]),
            agentType: string(root["agent_type"]),
            filePath: string(input["file_path"]),
            notebookPath: string(input["notebook_path"]),
            command: string(input["command"]),
            structuredPatch: hunks(response["structuredPatch"])
        )
    }

    /// Extracts a non-empty string value.
    ///
    /// Empty strings are treated as absences. Claude Code omits a field it
    /// has no value for, but a shim that re-serialises a payload can turn
    /// the omission into `""`, and an empty session_id must not look like
    /// a conversation.
    /// - Parameter value: The value to extract.
    /// - Returns: The string, or `nil` if empty or not a string.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// Decodes structured patch hunks from JSON.
    ///
    /// Decoded through the plain-JSON path that camelCase keys require.
    /// A malformed or absent patch is no ranges, never a failure.
    /// - Parameter value: The JSON array value to decode.
    /// - Returns: The decoded hunks, or empty array on failure.
    private static func hunks(_ value: Any?) -> [StructuredPatchHunk] {
        guard let array = value as? [Any],
            let data = try? JSONSerialization.data(withJSONObject: array),
            let decoded = try? JSONDecoder().decode([StructuredPatchHunk].self, from: data)
        else { return [] }
        return decoded
    }
}

// MARK: - What a tool call wrote

/// One recordable change: a repo-relative path, the kind it landed as, and
/// how honestly it was derived.
struct HookWriteTarget: Equatable {
    let relativePath: String
    let changeKind: ChangeKind
    /// `hook` for an exact payload-named path, `command` for one inferred
    /// from a Bash command line.
    ///
    /// The distinction is kept all the way to the column so an inference
    /// is never indistinguishable from an exact row.
    let origin: String
    let ranges: [ChangeRange]
}

enum HookWriteTargets {
    /// Checks if a payload may name a write target.
    ///
    /// The tool allowlist: only these tools produce rows, by name. A
    /// permissive rule would record a change for a tool that only reads the
    /// file. Nothing here costs a subprocess; `true` is not a promise that
    /// a row lands — git may still classify the path away.
    /// - Parameter payload: The hook payload.
    /// - Returns: `true` if the tool may have write targets.
    static func mayHaveTargets(payload: HookPayload) -> Bool {
        switch payload.toolName {
        case "Edit", "Write", "NotebookEdit":
            return (payload.filePath ?? payload.notebookPath) != nil
        case "Bash":
            guard let command = payload.command, let cwd = payload.cwd else { return false }
            return !BashWritePaths.extract(command: command, cwd: cwd).isEmpty
        default:
            return false
        }
    }

    /// Resolves hook payload to write targets.
    /// - Parameters:
    ///   - payload: The hook payload.
    ///   - repoRoot: The repository root path.
    /// - Returns: The write targets resolved from the payload.
    static func resolve(payload: HookPayload, repoRoot: String) -> [HookWriteTarget] {
        switch payload.toolName {
        case "Edit", "Write", "NotebookEdit":
            return declaredPath(payload: payload, repoRoot: repoRoot)
        case "Bash":
            return commandPaths(payload: payload, repoRoot: repoRoot)
        default:
            return []
        }
    }

    /// Resolves write targets from explicitly declared file paths.
    ///
    /// The tool named its file and the payload carries the hunks it wrote,
    /// so both the path and line ranges are facts rather than inferences.
    /// - Parameters:
    ///   - payload: The hook payload.
    ///   - repoRoot: The repository root path.
    /// - Returns: The write targets with line ranges.
    private static func declaredPath(
        payload: HookPayload,
        repoRoot: String
    ) -> [HookWriteTarget] {
        guard let absolute = payload.filePath ?? payload.notebookPath,
            let relativePath = GitPathClassifier.repoRelative(absolute, repoRoot: repoRoot)
        else { return [] }
        // Edit and NotebookEdit cannot bring a file into existence, so their
        // kind is settled without asking git. Write can, and git is the only
        // thing that knows whether this path is new.
        let changeKind: ChangeKind =
            payload.toolName == "Write"
            ? GitPathClassifier.classify(
                relativePath: relativePath,
                repoRoot: repoRoot,
                declared: .write
            ) ?? .create
            : .edit
        return [
            HookWriteTarget(
                relativePath: relativePath,
                changeKind: changeKind,
                origin: FileChangeOrigin.hook,
                ranges: StructuredPatchExpander.expand(payload.structuredPatch)
            )
        ]
    }

    /// Resolves write targets inferred from command lines.
    ///
    /// Paths the command named, classified by git. No ranges — a command
    /// line says nothing about line numbers.
    /// - Parameters:
    ///   - payload: The hook payload.
    ///   - repoRoot: The repository root path.
    /// - Returns: The write targets without line ranges.
    private static func commandPaths(
        payload: HookPayload,
        repoRoot: String
    ) -> [HookWriteTarget] {
        guard let command = payload.command, let cwd = payload.cwd else { return [] }
        return BashWritePaths.extract(command: command, cwd: cwd)
            .compactMap { target in
                guard
                    let relativePath = GitPathClassifier.repoRelative(
                        target.path,
                        repoRoot: repoRoot
                    ),
                    let changeKind = GitPathClassifier.classify(
                        relativePath: relativePath,
                        repoRoot: repoRoot,
                        declared: target.intent
                    )
                else { return nil }
                return HookWriteTarget(
                    relativePath: relativePath,
                    changeKind: changeKind,
                    origin: FileChangeOrigin.command,
                    ranges: []
                )
            }
    }
}
