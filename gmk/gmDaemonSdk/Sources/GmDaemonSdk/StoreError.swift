import Foundation

/// Typed domain failures. Handlers never hand-build error payloads — this is
/// the ONE mapping point from Store outcomes to wire error codes.
///
/// LIVES IN THE BASE LAYER, not beside the Store that throws most of it. This
/// was the ONLY upward dependency in the whole kit and the one thing that had
/// to move for the package split to compile at all: it sat in `Database/` (now
/// gmDaemon, the middle layer) while base-layer code threw it —
/// `Protocol/Rows.swift`, `Diagram/DiagramStorage.swift`,
/// `Diagram/DiagramStrokeCodec.swift`, `Dope/DopeCogElement.swift`. That is
/// base-depending-on-middle, which is a cycle the moment the modules separate.
///
/// It is Foundation-only, so the move costs nothing. The rule it is the
/// archetype of: a symbol a test or a lower layer cannot reach gets MOVED to
/// where it belongs, never made `public` to paper over a misfiling.
public enum StoreError: Error, Sendable {
    case notFound(entity: String, key: String)
    case versionConflict(entity: String, uuid: String, expected: Int64, actual: Int64)
    case invalidTransition(from: PromptStatus, to: PromptStatus, reason: String?)
    case contentLocked(status: PromptStatus)
    /// The prompt EXISTS but has no summary of this kind yet — kept distinct
    /// from notFound because the caller's branch differs materially: open a
    /// summary, rather than "the uuid is unknown".
    case summaryAbsent(entity: String, promptUuid: String)
    /// A guarded update with no fields set — rejected instead of burning the
    /// version other editors hold and emitting an empty audit event.
    case emptyUpdate(entity: String)
    /// A row holds a value the schema CHECKs should have made impossible.
    case corruptState(entity: String, detail: String)
    /// A request whose payload decoded fine but is semantically unusable
    /// (e.g. a whitespace-only search query).
    case badRequest(detail: String)
    /// Generic status-machine violation for the non-prompt entities
    /// (clarification_summary, architecture_summary). Maps onto the SAME wire
    /// code as the prompt-typed case — no new ErrorCode needed.
    case invalidEntityTransition(entity: String, from: String, to: String, reason: String?)
    /// Dope whole-tree revision gate failure. Maps onto the SAME wire code as
    /// versionConflict (the invalidEntityTransition precedent) so a pinned-Kit
    /// GMVibes always decodes it.
    case revisionConflict(scopeUuid: String, expected: Int64, actual: Int64)
    /// The dope target EXISTS (session, and prompt when one was named) but no
    /// dope scope was ever initialized for it. summaryAbsent is prompt-shaped
    /// and cannot name a SESSION_INSTANCE target, so dope gets its own case —
    /// mapped onto the SAME wire code (the revisionConflict precedent), so
    /// the four prompt-shaped call sites stay untouched.
    case dopeScopeAbsent(sessionUuid: String, promptUuid: String?, code: String?)
    /// The PROJECT exists but carries no dope scope on its own ladder
    /// (PROJECT_ITEM, then the BASE_PROJECT scope DOPE_PROMOTE maintains). A
    /// separate case from `dopeScopeAbsent` because the remediation differs —
    /// a project scope arrives by PROMOTION, not by DOPE_INIT, and telling
    /// someone to init one would be wrong
    /// advice. Same `.summaryAbsent` wire code, so no new ErrorCode and a
    /// pinned-Kit GMVibes still decodes it.
    case dopeProjectScopeAbsent(projectUuid: String, code: String?)
    /// The diagram owner EXISTS (project/instance/session/prompt row) but no
    /// diagram was ever initialized for it (or none with the given code).
    /// Same wire code as summaryAbsent (the dopeScopeAbsent precedent) so a
    /// pinned-Kit GMVibes always decodes it; the remediation hint differs.
    case diagramAbsent(ownerKind: String, ownerUuid: String, code: String?)
    /// A repo verb (read-repo / write-repo / ingest) was pointed at a scope
    /// that is not the session's base tier. `requireSessionUuid()` alone
    /// admits SESSION_INSTANCE_ITEM as well, so without this guard a
    /// prompt-scoped tree writes straight into the shared
    /// {instance_root}/.gmcc — and an overlay's soft-delete tombstones would
    /// reach committed files, which the format explicitly forbids. Mapped onto
    /// the badRequest wire code (no new ErrorCode), so a pinned-Kit GMVibes
    /// still decodes it.
    case dopeScopeNotRepoWritable(scopeUuid: String, scopeType: String, verb: String)
    /// A write naming a Claude conversation arrived with no
    /// claude_session_binding row to resolve it, so NOTHING was written. This
    /// is the server-side no-op contract: a hook cannot record into a repo
    /// whose SessionStart never pinned the conversation, which is strictly
    /// stronger than any env variable surviving a subprocess.
    ///
    /// `booted` says whether the daemon knows the repo. It does NOT change
    /// the refusal — only whether a HOOK_UNBOUND event marks it, which
    /// `Store.addFileChange` appends in its own transaction. Mapped onto the
    /// badRequest wire code (no new ErrorCode), so a pinned-Kit GMVibes still
    /// decodes it.
    case hookUnbound(claudeSessionId: String, booted: Bool)
    /// A verb that CANNOT run inside a caller-opened transaction was called
    /// inside one. Two families qualify, both for reasons SQLite enforces
    /// rather than reasons we chose:
    ///
    /// - The four-phase repo verbs (dope / diagram write-repo and ingest) run
    ///   db read → pure projection → filesystem work → db write, and the
    ///   filesystem phase deliberately holds NO lock. Composing one would pin
    ///   the single writer across file I/O, so every other writer in the
    ///   machine — including every hook — would block on someone else's disk.
    /// - `checkpointTruncate`, because a WAL checkpoint inside a transaction is
    ///   illegal.
    ///
    /// A loud refusal in two files beats an enrolment table listing which of
    /// ~230 verbs are composable, which nobody would keep accurate. Mapped onto
    /// the badRequest wire code, so no new ErrorCode and no stale-client
    /// decode problem.
    case notComposable(verb: String)

    public var errorPayload: ErrorPayload {
        switch self {
        case .notFound(let entity, let key):
            return ErrorPayload(code: .notFound, message: "\(entity) not found: \(key)")
        case .versionConflict(let entity, let uuid, let expected, let actual):
            return ErrorPayload(
                code: .versionConflict,
                message: "\(entity) \(uuid): expected version \(expected), actual \(actual)")
        case .invalidTransition(let from, let to, let reason):
            let suffix = reason.map { " (\($0))" } ?? ""
            return ErrorPayload(
                code: .invalidTransition,
                message: "illegal prompt transition \(from.rawValue) → \(to.rawValue)\(suffix)")
        case .summaryAbsent(let entity, let uuid):
            // The open hint is entity-derived, and names the pen tool wherever
            // one covers the open; the rest go through the raw verb.
            func rawOpen(_ type: String) -> String {
                "gm_hook call \(type) --json '{\"prompt_uuid\":\"\(uuid)\"}'"
            }
            let hint: String
            switch entity {
            case "exploration": hint = "mcp__plugin_gmcc_pen__bot_summary"
            case "briefing": hint = "mcp__plugin_gmcc_pen__init_briefing"
            case "review": hint = rawOpen("REVIEW_OPEN")
            case "architecture": hint = rawOpen("ARCH_OPEN")
            case "clarification": hint = rawOpen("CLARIFY_OPEN")
            default: hint = rawOpen("CLARIFY_OPEN (or ARCH_OPEN)")
            }
            return ErrorPayload(
                code: .summaryAbsent,
                message: "prompt \(uuid) has no \(entity) yet — open one (\(hint))")
        case .contentLocked(let status):
            return ErrorPayload(
                code: .contentLocked,
                message: "prompt content is editable only in draft (status: \(status.rawValue))")
        case .emptyUpdate(let entity):
            return ErrorPayload(
                code: .badRequest,
                message: "\(entity) update carried no fields — nothing to change")
        case .corruptState(let entity, let detail):
            return ErrorPayload(
                code: .internalError,
                message: "\(entity) holds an impossible value: \(detail)")
        case .badRequest(let detail):
            return ErrorPayload(code: .badRequest, message: detail)
        case .invalidEntityTransition(let entity, let from, let to, let reason):
            let suffix = reason.map { " (\($0))" } ?? ""
            return ErrorPayload(
                code: .invalidTransition,
                message: "illegal \(entity) transition \(from) → \(to)\(suffix)")
        case .revisionConflict(let scopeUuid, let expected, let actual):
            return ErrorPayload(
                code: .versionConflict,
                message: "dope_scope \(scopeUuid): expected revision \(expected), actual \(actual)")
        case .dopeScopeAbsent(let sessionUuid, let promptUuid, let code):
            var target = "session \(sessionUuid)"
            if let promptUuid { target += " / prompt \(promptUuid)" }
            if let code { target += " code '\(code)'" }
            let initHint = "gm_hook call DOPE_INIT --json '{\"session_uuid\":\"\(sessionUuid)\""
                + (promptUuid.map { ",\"prompt_uuid\":\"\($0)\"" } ?? "")
                + ",\"code\":\"\(code ?? "<code>")\",\"name\":\"<name>\"}'"
            return ErrorPayload(
                code: .summaryAbsent,
                message: "\(target) has no dope scope yet — initialize one (\(initHint))")
        case .dopeProjectScopeAbsent(let projectUuid, let code):
            var target = "project \(projectUuid)"
            if let code { target += " code '\(code)'" }
            return ErrorPayload(
                code: .summaryAbsent,
                message: "\(target) has no project-tier dope scope yet — a project scope "
                       + "arrives by promotion from a primary-branch session "
                       + "(gm_hook call DOPE_PROMOTE --json '{\"session_uuid\":\"<U>\"}'), "
                       + "not by DOPE_INIT")
        case .diagramAbsent(let ownerKind, let ownerUuid, let code):
            var target = "\(ownerKind) \(ownerUuid)"
            if let code { target += " code '\(code)'" }
            let initHint = "gm_hook call DIAGRAM_INIT --json "
                + "'{\"\(ownerKind)_uuid\":\"\(ownerUuid)\",\"code\":\"\(code ?? "<code>")\","
                + "\"name\":\"<name>\"}'"
            return ErrorPayload(
                code: .summaryAbsent,
                message: "\(target) has no diagram yet — initialize one (\(initHint))")
        case .dopeScopeNotRepoWritable(let scopeUuid, let scopeType, let verb):
            return ErrorPayload(
                code: .badRequest,
                message: "dope \(verb) is session-base only: scope \(scopeUuid) is "
                    + "\(scopeType). Only a SESSION_INSTANCE tree is read from or "
                    + "written to {instance_root}/.gmcc")
        case .hookUnbound(let claudeSessionId, let booted):
            let repo = booted
                ? "the daemon knows this repo, so this is dead capture"
                : "the daemon knows no such repo"
            return ErrorPayload(
                code: .badRequest,
                message: "claude session \(claudeSessionId) is not bound to a gmcc "
                    + "session — nothing was recorded (\(repo))")
        case .notComposable(let verb):
            return ErrorPayload(
                code: .badRequest,
                message: "\(verb) cannot run inside a caller-opened transaction — "
                    + "it performs work that must not hold the single writer lock. "
                    + "Call it outside inTransaction / TX_BATCH.")
        }
    }
}
