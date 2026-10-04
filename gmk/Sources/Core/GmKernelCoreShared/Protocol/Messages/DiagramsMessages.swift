import Foundation

// Diagram wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from WireCodec's key strategies — types declare NO CodingKeys
// (the two intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

// MARK: - PROMPT_DIAGRAM_QUALIFY / _GET / _LIST

/// A prompt's standing reading of one rendered diagram.
///
/// The three render columns are the staleness evidence. `renderFingerprint`
/// is a serialized `DiagramRenderFingerprint` carried as opaque JSON text:
/// the wire never re-shapes it, so a reader compares it against the sidecar
/// beside a current PNG byte-for-byte and learns whether this qualification
/// still describes the picture it was written about.
struct PromptQualifiedDiagramRow: Codable, Hashable, Sendable {
    let uuid: String
    let promptUuid: String
    let diagramUuid: String
    let renderedPath: String
    let renderedRevision: Int64
    let renderFingerprint: String
    let qualification: String
    let version: Int64
    let createdAt: String
    let updatedAt: String

    /// Creates a prompt-diagram qualification record with render metadata.
    /// - Parameters:
    ///   - uuid: The qualification row uuid.
    ///   - promptUuid: The parent prompt uuid.
    ///   - diagramUuid: The diagram uuid.
    ///   - renderedPath: The path to the rendered diagram.
    ///   - renderedRevision: The render revision number.
    ///   - renderFingerprint: The serialized render fingerprint as JSON text.
    ///   - qualification: The qualification text.
    ///   - version: The row version for optimistic concurrency.
    ///   - createdAt: The row creation timestamp.
    ///   - updatedAt: The row last-write timestamp.
    init(
        uuid: String,
        promptUuid: String,
        diagramUuid: String,
        renderedPath: String,
        renderedRevision: Int64,
        renderFingerprint: String,
        qualification: String,
        version: Int64,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
        self.renderedPath = renderedPath
        self.renderedRevision = renderedRevision
        self.renderFingerprint = renderFingerprint
        self.qualification = qualification
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Record (or replace) what this prompt makes of this diagram.
///
/// UPSERT on (prompt, diagram): no expected_version, because the pair is the
/// identity and the newer reading is by definition the one that stands.
struct PromptDiagramQualifyRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let diagramUuid: String
    let renderedPath: String
    let renderedRevision: Int64
    let renderFingerprint: String
    let qualification: String

    /// Creates a PROMPT_DIAGRAM_QUALIFY request to record a diagram qualification.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - diagramUuid: The diagram uuid.
    ///   - renderedPath: The path to the rendered diagram.
    ///   - renderedRevision: The render revision number.
    ///   - renderFingerprint: The serialized render fingerprint as JSON text.
    ///   - qualification: The qualification text.
    init(
        promptUuid: String,
        diagramUuid: String,
        renderedPath: String,
        renderedRevision: Int64,
        renderFingerprint: String,
        qualification: String
    ) {
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
        self.renderedPath = renderedPath
        self.renderedRevision = renderedRevision
        self.renderFingerprint = renderFingerprint
        self.qualification = qualification
    }
}

/// One qualification.
///
/// With `diagramUuid` it is the pair; without, it is the prompt's only
/// qualification — and an ambiguous ask (several exist) is a badRequest
/// pointing at the list verb rather than an arbitrary pick.
struct PromptDiagramGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let diagramUuid: String?

    /// Creates a PROMPT_DIAGRAM_GET request.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - diagramUuid: The diagram uuid; nil to get the only qualification.
    init(promptUuid: String, diagramUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
    }
}

struct PromptDiagramListRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates a PROMPT_DIAGRAM_LIST request.
    /// - Parameter promptUuid: The prompt to list qualifications for.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct PromptDiagramListResponse: Codable, Hashable, Sendable {
    let qualifications: [PromptQualifiedDiagramRow]

    /// Creates a PROMPT_DIAGRAM_LIST response.
    /// - Parameter qualifications: The list of qualified diagram rows.
    init(qualifications: [PromptQualifiedDiagramRow]) {
        self.qualifications = qualifications
    }
}

// MARK: - DIAGRAM_*

/// Create-or-return a diagram (idempotent per (tier owner, code) — the
/// dopeInit precedent).
///
/// Exactly ONE owner uuid picks the tier; the store derives and persists the full ancestor chain by joins
/// (chain-non-null ladder). gmccDiagramPath is refused at PROJECT tier (no instance root to resolve it against).
struct DiagramInitRequest: Codable, Hashable, Sendable {
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    let code: String
    let name: String
    let description: String?
    let gmccDiagramPath: String?
    /// The dope scope this whole diagram reads/writes through.
    ///
    /// Restricted to the masking tiers (PROJECT_ITEM / SESSION_INSTANCE_ITEM) so a canvas always edits a personal
    /// overlay rather than shared truth.
    let dopeScopeCode: String?

    /// Creates a DIAGRAM_INIT request to create or retrieve a diagram.
    /// - Parameters:
    ///   - code: The diagram code identifier.
    ///   - name: The diagram name.
    ///   - projectUuid: Project tier owner; nil if not at project tier.
    ///   - instanceUuid: Instance tier owner; nil if not at instance tier.
    ///   - sessionUuid: Session tier owner; nil if not at session tier.
    ///   - promptUuid: Prompt tier owner; nil if not at prompt tier.
    ///   - description: The diagram description; nil if none.
    ///   - gmccDiagramPath: GMK diagram path; nil at project tier or if none.
    ///   - dopeScopeCode: Dope scope for editing (masking tiers only); nil for default.
    init(
        code: String,
        name: String,
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        description: String? = nil,
        gmccDiagramPath: String? = nil,
        dopeScopeCode: String? = nil
    ) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.name = name
        self.description = description
        self.gmccDiagramPath = gmccDiagramPath
        self.dopeScopeCode = dopeScopeCode
    }
}

struct DiagramResponse: Codable, Hashable, Sendable {
    let diagram: DiagramRow
    let created: Bool

    /// Creates a DIAGRAM_INIT response with the created or retrieved diagram.
    /// - Parameters:
    ///   - diagram: The diagram row.
    ///   - created: True if INIT created the diagram; false if it existed.
    init(diagram: DiagramRow, created: Bool) {
        self.diagram = diagram
        self.created = created
    }
}

/// Picker enumeration — the v12 dopeList contract verbatim: exactly one
/// owner uuid, exactly that tier's rows for that owner, never a union or a
/// cross-tier ladder, ORDER BY code.
///
/// Unknown owner is NOT_FOUND; a real owner with no diagrams is a normal empty list.
struct DiagramListRequest: Codable, Hashable, Sendable {
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    /// v23, additive: server-side visibility filter (PRIVATE|PUBLIC).
    ///
    /// Absent = both. Still single-owner single-tier — never a union.
    let visibility: String?

    /// Creates a DIAGRAM_LIST request to fetch diagrams for a tier owner.
    /// - Parameters:
    ///   - projectUuid: Project tier owner; nil if not querying project tier.
    ///   - instanceUuid: Instance tier owner; nil if not querying instance tier.
    ///   - sessionUuid: Session tier owner; nil if not querying session tier.
    ///   - promptUuid: Prompt tier owner; nil if not querying prompt tier.
    ///   - visibility: Filter by visibility (PRIVATE or PUBLIC); nil for both.
    init(
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        visibility: String? = nil
    ) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.visibility = visibility
    }

}

struct DiagramListResponse: Codable, Hashable, Sendable {
    let diagrams: [DiagramRow]

    /// Creates a DIAGRAM_LIST response with the diagrams for the requested tier owner.
    /// - Parameter diagrams: The diagram rows from the tier.
    init(diagrams: [DiagramRow]) {
        self.diagrams = diagrams
    }
}

/// Full-tree read: by diagramUuid, or by exactly one owner uuid + optional
/// code.
///
/// Deliberately NO cross-tier fallback ladder (tiers are explicit workspaces — the ladder belongs to dope binding
/// resolution INSIDE the diagram). Several owner matches without a code → BAD_REQUEST naming the candidate codes; a
/// real owner with none → SUMMARY_ABSENT (diagramAbsent). The response does NOT embed dope trees — clients pair it with
/// DOPE_GET.
struct DiagramGetRequest: Codable, Hashable, Sendable {
    let diagramUuid: String?
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    let code: String?

    /// Creates a DIAGRAM_GET request to fetch a diagram's full tree.
    /// - Parameters:
    ///   - diagramUuid: Fetch by diagram uuid; nil to use owner+code.
    ///   - projectUuid: Project tier owner; nil if not querying project tier.
    ///   - instanceUuid: Instance tier owner; nil if not querying instance tier.
    ///   - sessionUuid: Session tier owner; nil if not querying session tier.
    ///   - promptUuid: Prompt tier owner; nil if not querying prompt tier.
    ///   - code: Filter to one diagram by code; nil to use first match.
    init(
        diagramUuid: String? = nil,
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        code: String? = nil
    ) {
        self.diagramUuid = diagramUuid
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
    }
}

struct DiagramGetResponse: Codable, Hashable, Sendable {
    let tree: DiagramTree
    /// One row per dope_scope binding element (resolvedVia nil = ghost).
    let bindings: [DiagramBindingResolution]
    /// The OWNER's `gmfs_relative_storage_path` — the root a rendered
    /// screenshot lands under, whichever tier owns the diagram.
    ///
    /// An additive optional, so an older peer ignores it. It rides this
    /// response rather than being fetched separately because the alternative is
    /// three round trips for something the daemon already held while resolving
    /// the owner.
    let ownerStoragePath: String?

    /// Creates a DIAGRAM_GET response with the full diagram tree and bindings.
    /// - Parameters:
    ///   - tree: The diagram tree with all nodes and relationships.
    ///   - bindings: Resolved dope scope bindings for diagram elements.
    ///   - ownerStoragePath: The owner's storage path for screenshots; nil if unavailable.
    init(
        tree: DiagramTree,
        bindings: [DiagramBindingResolution],
        ownerStoragePath: String? = nil
    ) {
        self.tree = tree
        self.bindings = bindings
        self.ownerStoragePath = ownerStoragePath
    }

    private enum CodingKeys: String, CodingKey {
        case tree, bindings, ownerStoragePath
    }

    /// Decodes a diagram response, handling the additive optional `ownerStoragePath`.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Decoding errors from the container.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tree = try c.decode(DiagramTree.self, forKey: .tree)
        bindings = try c.decode([DiagramBindingResolution].self, forKey: .bindings)
        // decodeIfPresent: a peer built before this field existed omits it.
        ownerStoragePath = try c.decodeIfPresent(String.self, forKey: .ownerStoragePath)
    }
}

/// Granular element verbs — each is a one-mutation batch over the SAME
/// store body as DIAGRAM_BATCH_APPLY, so granular and batch semantics
/// cannot drift.
///
/// Diagram-row updates (rename/promotion) ride batch-apply's diagramUpdate mutation.
struct DiagramNodeAddRequest: Codable, Hashable, Sendable {
    let diagramUuid: String
    let add: DiagramElementAdd

    /// Creates a DIAGRAM_NODE_ADD request.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - add: The element addition specification.
    init(diagramUuid: String, add: DiagramElementAdd) {
        self.diagramUuid = diagramUuid
        self.add = add
    }
}

struct DiagramNodeUpdateRequest: Codable, Hashable, Sendable {
    let update: DiagramElementUpdate

    /// Creates a DIAGRAM_NODE_UPDATE request.
    /// - Parameter update: The element update specification.
    init(update: DiagramElementUpdate) {
        self.update = update
    }
}

struct DiagramNodeDeleteRequest: Codable, Hashable, Sendable {
    let delete: DiagramElementDelete

    /// Creates a DIAGRAM_NODE_DELETE request.
    /// - Parameter delete: The element deletion specification.
    init(delete: DiagramElementDelete) {
        self.delete = delete
    }
}

/// Every mutation response carries diagramUuid + revision so clients update
/// without a refetch (the DopeNodeResponse contract).
struct DiagramNodeResponse: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let diagramUuid: String
    let revision: Int64

    /// Creates a DIAGRAM_NODE response.
    /// - Parameters:
    ///   - uuid: The element's unique identifier.
    ///   - version: The element's version number.
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - revision: The diagram's revision number after the mutation.
    init(uuid: String, version: Int64, diagramUuid: String, revision: Int64) {
        self.uuid = uuid
        self.version = version
        self.diagramUuid = diagramUuid
        self.revision = revision
    }
}

struct DiagramNodeDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    /// Element rows removed, including the target itself.
    let cascadedElements: Int
    let diagramUuid: String
    let revision: Int64

    /// Creates a DIAGRAM_NODE_DELETE response.
    /// - Parameters:
    ///   - deletedUuid: The unique identifier of the deleted element.
    ///   - cascadedElements: The count of elements removed by cascading.
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - revision: The diagram's revision number after the deletion.
    init(deletedUuid: String, cascadedElements: Int, diagramUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid
        self.cascadedElements = cascadedElements
        self.diagramUuid = diagramUuid
        self.revision = revision
    }
}

/// THE interactive write: many typed mutations, one transaction, ONE
/// revision bump, ONE DIAGRAM_CHANGE event.
///
/// Mutations apply strictly in array order; elementAdd clientRefs are resolvable by later mutations in the same batch.
/// expectedRevision non-nil is a whole-diagram CAS gate (VERSION_CONFLICT on mismatch — gesture-end concurrency for
/// GMVibes).
struct DiagramBatchApplyRequest: Codable, Hashable, Sendable {
    let diagramUuid: String
    let expectedRevision: Int64?
    let mutations: [DiagramMutation]

    /// Creates a DIAGRAM_BATCH_APPLY request.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - mutations: The list of mutations to apply in order.
    ///   - expectedRevision: The expected diagram revision for CAS gating; nil skips the gate.
    init(diagramUuid: String, mutations: [DiagramMutation], expectedRevision: Int64? = nil) {
        self.diagramUuid = diagramUuid
        self.expectedRevision = expectedRevision
        self.mutations = mutations
    }
}

struct DiagramBatchApplyResponse: Codable, Hashable, Sendable {
    let diagramUuid: String
    let revision: Int64
    /// Index-aligned with the request's mutations array.
    let results: [DiagramMutationResult]

    /// Creates a DIAGRAM_BATCH_APPLY response.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - revision: The diagram's new revision after applying mutations.
    ///   - results: The results of each mutation, aligned with the request's mutations array.
    init(diagramUuid: String, revision: Int64, results: [DiagramMutationResult]) {
        self.diagramUuid = diagramUuid
        self.revision = revision
        self.results = results
    }
}

// MARK: - Diagram Studio

/// DIAGRAM_SEARCH — the cross-tier browse AND search surface backing the
/// GMVibes galleries.
///
/// A SEPARATE message from DIAGRAM_LIST, whose single-owner no-union picker contract it must not disturb. Two modes in
/// one message: a nil/empty `query` is a plain filtered SELECT of the project's diagrams across tiers ordered by
/// updated_at DESC (the gallery grid); a non-empty query is a bm25-ranked FTS5 MATCH over diagram_fts (the gallery
/// search box). `sessionUuid` narrows to one session's SESSION+PROMPT rows; `visibility` filters the axis.
struct DiagramSearchRequest: Codable, Hashable, Sendable {
    let projectUuid: String
    let sessionUuid: String?
    let query: String?
    let visibility: String?
    let limit: Int?

    /// Creates a DIAGRAM_SEARCH request.
    /// - Parameters:
    ///   - projectUuid: The project's unique identifier.
    ///   - sessionUuid: The session to narrow to; nil searches all sessions.
    ///   - query: The search query; nil or empty shows all diagrams sorted by updated_at DESC.
    ///   - visibility: Filter by visibility axis; nil shows all.
    ///   - limit: Maximum diagrams to return; nil uses default.
    init(
        projectUuid: String,
        sessionUuid: String? = nil,
        query: String? = nil,
        visibility: String? = nil,
        limit: Int? = nil
    ) {
        self.projectUuid = projectUuid
        self.sessionUuid = sessionUuid
        self.query = query
        self.visibility = visibility
        self.limit = limit
    }
}

/// Rows in rank order (bm25 when a query ran, updated_at DESC otherwise).
///
/// DiagramRow already carries tier/visibility/owner uuids/revision — the whole card surface — so hits are plain rows,
/// not a parallel shape.
struct DiagramSearchResponse: Codable, Hashable, Sendable {
    let diagrams: [DiagramRow]

    /// Creates a DIAGRAM_SEARCH response.
    /// - Parameter diagrams: The diagram rows matching the search, in rank order.
    init(diagrams: [DiagramRow]) {
        self.diagrams = diagrams
    }
}

/// DIAGRAM_DELETE — row delete with an optional whole-diagram CAS gate.
///
/// Elements and subtype rows cascade via FKs, the FTS mirror via its delete trigger, and prompt-qualified readings via
/// m0022's CASCADE. A durable DIAGRAM_CHANGE (action "deleted") is recorded BEFORE the row drops so live
/// galleries/editors close cleanly. Screenshot cleanup is the CLIENT's (gmfs is gm territory, exactly like rendering).
struct DiagramDeleteRequest: Codable, Hashable, Sendable {
    let diagramUuid: String
    let expectedRevision: Int64?

    /// Creates a DIAGRAM_DELETE request.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - expectedRevision: The expected diagram revision for CAS gating; nil skips the gate.
    init(diagramUuid: String, expectedRevision: Int64? = nil) {
        self.diagramUuid = diagramUuid
        self.expectedRevision = expectedRevision
    }
}

struct DiagramDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    let code: String
    /// Element rows removed with the diagram.
    let cascadedElements: Int
    /// The owner storage path a screenshot may exist under (client cleanup).
    let ownerStoragePath: String?
    /// The row's screenshot directory override — the client must clean the
    /// SAME path gm render wrote, not a guessed default.
    let gmccDiagramPath: String?

    /// Creates a DIAGRAM_DELETE response.
    /// - Parameters:
    ///   - deletedUuid: The unique identifier of the deleted diagram.
    ///   - code: The deletion response code.
    ///   - cascadedElements: The count of element rows removed with the diagram.
    ///   - ownerStoragePath: The owner storage path for client screenshot cleanup; nil if not applicable.
    ///   - gmccDiagramPath: The diagram path override for client screenshot cleanup; nil if not applicable.
    init(
        deletedUuid: String,
        code: String,
        cascadedElements: Int,
        ownerStoragePath: String? = nil,
        gmccDiagramPath: String? = nil
    ) {
        self.deletedUuid = deletedUuid
        self.code = code
        self.cascadedElements = cascadedElements
        self.ownerStoragePath = ownerStoragePath
        self.gmccDiagramPath = gmccDiagramPath
    }
}

/// DIAGRAM_WRITE_REPO — serialize the session's PUBLIC SESSION-tier
/// diagrams into the repo's committed .gmcc tree, through the session's
/// instance root (the dope write-repo gate and 4-phase orchestration,
/// applied verbatim).
///
/// Explicit only: setting PUBLIC never writes files.
struct DiagramWriteRepoRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    /// Overwrite files stamped AHEAD of the db (the dope --force contract).
    let force: Bool

    /// Creates a DIAGRAM_WRITE_REPO request.
    /// - Parameters:
    ///   - sessionUuid: The session's unique identifier.
    ///   - force: Whether to overwrite files stamped ahead of the db; defaults to false.
    init(sessionUuid: String, force: Bool = false) {
        self.sessionUuid = sessionUuid
        self.force = force
    }
}

struct DiagramWriteRepoResponse: Codable, Hashable, Sendable {
    /// Diagram codes written this pass.
    let written: [String]
    /// Files pruned because their diagram was demoted or deleted.
    let pruned: [String]
    /// The absolute .gmcc/diagrams directory written under.
    let root: String

    /// Creates a DIAGRAM_WRITE_REPO response.
    /// - Parameters:
    ///   - written: The diagram codes written this pass.
    ///   - pruned: The diagram codes pruned due to demotion or deletion.
    ///   - root: The absolute .gmcc/diagrams directory written under.
    init(written: [String], pruned: [String], root: String) {
        self.written = written
        self.pruned = pruned
        self.root = root
    }
}

/// DIAGRAM_INGEST — files→db, strictly forward-only (the dope ingest gate):
/// a file version must be STRICTLY greater than the db revision to land.
///
/// Code-keyed upsert into the calling session's SESSION tier as PUBLIC; connector code-path targets re-resolve,
/// unresolvable → ghost.
struct DiagramIngestRequest: Codable, Hashable, Sendable {
    let sessionUuid: String

    /// Creates a DIAGRAM_INGEST request.
    /// - Parameter sessionUuid: The session's unique identifier.
    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

struct DiagramIngestResponse: Codable, Hashable, Sendable {
    /// Codes created or updated from files.
    let ingested: [String]
    /// Codes skipped (db at or ahead of the file, or a PRIVATE collision).
    let skipped: [String]
    /// Per-file problems (corrupt JSON, name/code mismatch, refused
    /// content).
    ///
    /// One bad file must never abort the family's sync — and the boot path must have something to PRINT, or the failure
    /// is silent.
    let warnings: [String]
    /// The absolute .gmcc/diagrams directory read from.
    let root: String

    /// Creates a DIAGRAM_INGEST response.
    /// - Parameters:
    ///   - ingested: The diagram codes created or updated from files.
    ///   - skipped: The diagram codes skipped (db ahead of file or collision).
    ///   - root: The absolute .gmcc/diagrams directory read from.
    ///   - warnings: Per-file problems encountered during ingest; defaults to empty.
    init(
        ingested: [String],
        skipped: [String],
        root: String,
        warnings: [String] = []
    ) {
        self.ingested = ingested
        self.skipped = skipped
        self.warnings = warnings
        self.root = root
    }
}
