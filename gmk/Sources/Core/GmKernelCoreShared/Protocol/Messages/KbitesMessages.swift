import Foundation

// Kbite wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from WireCodec's key strategies — types declare NO CodingKeys
// (the two intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

// MARK: - KBITE_LIST / KBITE_ADD / KBITE_REMOVE

/// Registered kbites at a scope, resolved through the inheritance chain at
/// READ time (owner's own junction plus every ancestor's) — correct even for
/// kbites added after the child row was created. `all: true` ignores scope
/// and returns every kbite row in the db (the cleanup drift-check listing).
struct KbiteListRequest: Codable, Hashable, Sendable {
    let scope: KbiteScope
    let ownerUuid: String
    let all: Bool?

    /// Creates a KBITE_LIST request.
    /// - Parameters:
    ///   - scope: The scope level (project, instance, session, prompt).
    ///   - ownerUuid: The owner uuid.
    ///   - all: True to list all kbites in the db; nil defaults to false.
    init(scope: KbiteScope, ownerUuid: String, all: Bool? = nil) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.all = all
    }
}

struct KbiteListResponse: Codable, Hashable, Sendable {
    let kbites: [KbiteRef]

    /// Creates a KBITE_LIST response.
    /// - Parameter kbites: The list of kbite references.
    init(kbites: [KbiteRef]) {
        self.kbites = kbites
    }
}

/// Explicit-only registration (inheritance model — never auto-added).
///
/// Db-only — the db is the sole kbite registry.
/// Idempotent; `added` is false when the junction already existed.
struct KbiteAddRequest: Codable, Hashable, Sendable {
    let scope: KbiteScope
    let ownerUuid: String
    let code: String

    /// Creates a KBITE_ADD request to register a kbite at a scope.
    /// - Parameters:
    ///   - scope: The scope level (project, instance, session, prompt).
    ///   - ownerUuid: The owner uuid.
    ///   - code: The kbite code.
    init(scope: KbiteScope, ownerUuid: String, code: String) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.code = code
    }
}

struct KbiteAddResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let code: String
    let added: Bool

    /// Creates a KBITE_ADD response.
    /// - Parameters:
    ///   - kbiteUuid: The kbite uuid.
    ///   - code: The kbite code.
    ///   - added: True if the junction was newly created; false if it already existed.
    init(kbiteUuid: String, code: String, added: Bool) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.added = added
    }
}

struct KbiteRemoveRequest: Codable, Hashable, Sendable {
    let scope: KbiteScope
    let ownerUuid: String
    let code: String

    /// Creates a KBITE_REMOVE request to unregister a kbite.
    /// - Parameters:
    ///   - scope: The scope level (project, instance, session, prompt).
    ///   - ownerUuid: The owner uuid.
    ///   - code: The kbite code.
    init(scope: KbiteScope, ownerUuid: String, code: String) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.code = code
    }
}

struct KbiteRemoveResponse: Codable, Hashable, Sendable {
    let removed: Bool

    /// Creates a KBITE_REMOVE response.
    /// - Parameter removed: True if the junction was removed; false if it didn't exist.
    init(removed: Bool) {
        self.removed = removed
    }
}

// MARK: - KBITE_MAW_OPEN

/// Filesystem skeleton only — no db rows (maws are not tracked in the db).
///
/// The client resolves $GMCC_KBITE_OPEN and passes the absolute maw path; the
/// daemon never reads gmfs environment variables.
struct KbiteMawOpenRequest: Codable, Hashable, Sendable {
    let kbiteName: String
    let mawPath: String

    /// Creates a KBITE_MAW_OPEN request to initialize a maw filesystem.
    /// - Parameters:
    ///   - kbiteName: The kbite name.
    ///   - mawPath: The absolute path to the maw directory.
    init(kbiteName: String, mawPath: String) {
        self.kbiteName = kbiteName
        self.mawPath = mawPath
    }
}

struct KbiteMawOpenResponse: Codable, Hashable, Sendable {
    let mawPath: String
    let createdDirs: [String]
    let createdIndex: Bool

    /// Creates a KBITE_MAW_OPEN response.
    /// - Parameters:
    ///   - mawPath: The absolute path to the maw directory.
    ///   - createdDirs: The directories that were created.
    ///   - createdIndex: True if the index file was created.
    init(mawPath: String, createdDirs: [String], createdIndex: Bool) {
        self.mawPath = mawPath
        self.createdDirs = createdDirs
        self.createdIndex = createdIndex
    }
}

// MARK: - KBITE_DIGEST

/// The one-step import: parse chewed artifacts under the open maw, write
/// kbite_resource / kbite_resource_file / keyword rows (db becomes canonical
/// for digested text), then delete the temporary chewed files — raw sources
/// stay on disk for re-chewing.
struct KbiteDigestRequest: Codable, Hashable, Sendable {
    let code: String
    let kbiteOpenPath: String

    /// Creates a KBITE_DIGEST request to import and digest a kbite.
    /// - Parameters:
    ///   - code: The kbite code.
    ///   - kbiteOpenPath: The absolute path to the open maw.
    init(code: String, kbiteOpenPath: String) {
        self.code = code
        self.kbiteOpenPath = kbiteOpenPath
    }
}

struct KbiteDigestResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let resourceCount: Int
    let fileCount: Int
    let keywordCount: Int
    let deletedChewedFiles: [String]
    /// Where the maw's raw sources went (`{digested}/{code}/`); nil when
    /// nothing was digested or the archive move failed.
    let archivedTo: String?
    /// The archive failure, when there was one.
    ///
    /// The db commit stands regardless — the maw is simply still on disk.
    let archiveError: String?

    /// Creates a KBITE_DIGEST response with import summary and status.
    /// - Parameters:
    ///   - kbiteUuid: The kbite uuid.
    ///   - resourceCount: The number of resources created.
    ///   - fileCount: The number of resource files created.
    ///   - keywordCount: The number of keywords created.
    ///   - deletedChewedFiles: The chewed files that were deleted.
    ///   - archivedTo: The path where raw sources were archived; nil if none or failed.
    ///   - archiveError: The archive failure message if one occurred.
    init(
        kbiteUuid: String,
        resourceCount: Int,
        fileCount: Int,
        keywordCount: Int,
        deletedChewedFiles: [String],
        archivedTo: String? = nil,
        archiveError: String? = nil
    ) {
        self.kbiteUuid = kbiteUuid
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.keywordCount = keywordCount
        self.deletedChewedFiles = deletedChewedFiles
        self.archivedTo = archivedTo
        self.archiveError = archiveError
    }
}

// MARK: - KBITE_GET / KBITE_FILE_GET

struct KbiteGetRequest: Codable, Hashable, Sendable {
    let code: String

    /// Creates a KBITE_GET request.
    /// - Parameter code: The kbite code.
    init(code: String) {
        self.code = code
    }
}

/// One kbite with its resources, file STUBS (names + summaries, never
/// content), and kbite-level keywords.
///
/// Content loads go through KBITE_FILE_GET one file at a time.
struct KbiteGetResponse: Codable, Hashable, Sendable {
    let kbite: KbiteRow
    let resources: [KbiteResourceRow]
    let keywords: [String]

    /// Creates a KBITE_GET response with the kbite and its resources.
    /// - Parameters:
    ///   - kbite: The kbite row.
    ///   - resources: The resource rows with file stubs.
    ///   - keywords: The kbite-level keywords.
    init(kbite: KbiteRow, resources: [KbiteResourceRow], keywords: [String]) {
        self.kbite = kbite
        self.resources = resources
        self.keywords = keywords
    }
}

struct KbiteFileGetRequest: Codable, Hashable, Sendable {
    let fileUuid: String

    /// Creates a KBITE_FILE_GET request.
    /// - Parameter fileUuid: The resource file uuid.
    init(fileUuid: String) {
        self.fileUuid = fileUuid
    }
}

struct KbiteFileGetResponse: Codable, Hashable, Sendable {
    let file: KbiteResourceFileRow

    /// Creates a KBITE_FILE_GET response.
    /// - Parameter file: The resource file row with content.
    init(file: KbiteResourceFileRow) {
        self.file = file
    }
}

// MARK: - KBITE_SEARCH

/// FTS5 full-text query across kbite resource files; ranked stubs, never
/// content.
///
/// Empty/nil kbite_uuids searches everything.
struct KbiteSearchRequest: Codable, Hashable, Sendable {
    let query: String
    let kbiteUuids: [String]?
    let limit: Int?

    /// Creates a KBITE_SEARCH request for full-text search.
    /// - Parameters:
    ///   - query: The FTS5 search query.
    ///   - kbiteUuids: The kbites to search; nil or empty searches everything.
    ///   - limit: The maximum number of results; nil for default.
    init(query: String, kbiteUuids: [String]? = nil, limit: Int? = nil) {
        self.query = query
        self.kbiteUuids = kbiteUuids
        self.limit = limit
    }
}

struct KbiteSearchResponse: Codable, Hashable, Sendable {
    let hits: [KbiteSearchHit]

    /// Creates a KBITE_SEARCH response.
    /// - Parameter hits: The ranked search result stubs.
    init(hits: [KbiteSearchHit]) {
        self.hits = hits
    }
}

// MARK: - SEARCH

/// The searchable row kinds.
///
/// Raw values match the source table names.
enum SearchKind: String, Codable, Hashable, CaseIterable, Sendable {
    case prompt
    /// m0025: the clarification split's searchable rows. clarification /
    /// clarification_summary / exploration_key_file are RETIRED with their
    /// tables (the summary lost its text columns; key files are
    /// kind='key_file' rows inside exploration_finding).
    case clarificationQuestion = "clarification_question"
    case clarificationNote = "clarification_note"
    case architectureSummary = "architecture_summary"
    case architectureGeneralChange = "architecture_general_change"
    case architecturePersistenceChange = "architecture_persistence_change"
    case explorationSummary = "exploration_summary"
    case explorationFinding = "exploration_finding"
    case reviewSummary = "review_summary"
    case reviewFinding = "review_finding"
}

/// FTS5 full-text search over prompt/clarification/architecture text —
/// ranked stubs with prompt lineage, never full content (the SEARCH
/// counterpart of KBITE_SEARCH). nil sessionUuid = whole db; a
/// supplied-but-unknown uuid is NOT_FOUND, never a silent empty list.
///
/// A query with no searchable tokens is BAD_REQUEST.
struct SearchRequest: Codable, Hashable, Sendable {
    let query: String
    let sessionUuid: String?
    /// nil/empty = every kind.
    let kinds: [SearchKind]?
    /// Clamped 1…500, default 50.
    let limit: Int?

    /// Creates a SEARCH request for full-text search across prompts and reports.
    /// - Parameters:
    ///   - query: The FTS5 search query.
    ///   - sessionUuid: The session to search; nil searches the whole db.
    ///   - kinds: The kinds of rows to include; nil or empty includes every kind.
    ///   - limit: The maximum number of results, clamped 1…500; nil defaults to 50.
    init(query: String, sessionUuid: String? = nil, kinds: [SearchKind]? = nil, limit: Int? = nil) {
        self.query = query
        self.sessionUuid = sessionUuid
        self.kinds = kinds
        self.limit = limit
    }
}

struct SearchResponse: Codable, Hashable, Sendable {
    let hits: [SearchHit]

    /// Creates a SEARCH response.
    /// - Parameter hits: The ranked search result stubs with prompt lineage.
    init(hits: [SearchHit]) {
        self.hits = hits
    }
}

// MARK: - CATALOG_SEARCH

/// Tokenized OR name/code search across instances + sessions, optionally
/// scoped to one project.
///
/// Returns matched sessions plus every parent instance needed to group them;
/// the client orders by created/updated.
struct CatalogSearchRequest: Codable, Hashable, Sendable {
    let query: String
    let projectUuid: String?
    let limit: Int?
    /// ADDITIVE OPTIONAL: byte mode (see `CdePager`); sessions are the paged
    /// region and instances are recomputed as the parents of the page.
    let pageBytes: Int?
    let pageCursor: String?

    /// Creates a CATALOG_SEARCH request for name/code search across instances.
    /// - Parameters:
    ///   - query: The search query, tokenized with OR logic.
    ///   - projectUuid: The project to scope by; nil searches all projects.
    ///   - limit: The maximum results to return; nil for no limit.
    ///   - pageBytes: The byte-mode page budget; nil for no pagination.
    ///   - pageCursor: The pagination cursor from a prior result; nil to start.
    init(
        query: String,
        projectUuid: String? = nil,
        limit: Int? = nil,
        pageBytes: Int? = nil,
        pageCursor: String? = nil
    ) {
        self.query = query
        self.projectUuid = projectUuid
        self.limit = limit
        self.pageBytes = pageBytes
        self.pageCursor = pageCursor
    }
}

struct CatalogSearchResponse: Codable, Hashable, Sendable {
    let instances: [InstanceRow]
    let sessions: [SessionStub]
    /// ADDITIVE OPTIONAL, byte mode only.
    let page: CdePage?

    /// Creates a CATALOG_SEARCH response with matched instances and sessions.
    /// - Parameters:
    ///   - instances: The instances containing matched sessions.
    ///   - sessions: The matched session stubs.
    ///   - page: The pagination metadata; nil when not in byte-mode paging.
    init(instances: [InstanceRow], sessions: [SessionStub], page: CdePage? = nil) {
        self.instances = instances
        self.sessions = sessions
        self.page = page
    }
}

// MARK: - KBITE_KEYWORD_TAG

/// Attach or detach normalized keywords at kbite level or resource-file
/// level.
///
/// Keywords are upserted into the shared vocabulary on attach.
struct KbiteKeywordTagRequest: Codable, Hashable, Sendable {
    let level: KeywordTagLevel
    let targetUuid: String
    let keywords: [String]
    let detach: Bool

    /// Creates a KBITE_KEYWORD_TAG request to attach or detach keywords.
    /// - Parameters:
    ///   - level: The scope level (kbite or resource-file).
    ///   - targetUuid: The target kbite or resource-file uuid.
    ///   - keywords: The normalized keywords to attach or detach.
    ///   - detach: True to detach; false to attach.
    init(level: KeywordTagLevel, targetUuid: String, keywords: [String], detach: Bool = false) {
        self.level = level
        self.targetUuid = targetUuid
        self.keywords = keywords
        self.detach = detach
    }
}

struct KbiteKeywordTagResponse: Codable, Hashable, Sendable {
    let attached: Int
    let detached: Int

    /// Creates a KBITE_KEYWORD_TAG response with counts of changes.
    /// - Parameters:
    ///   - attached: The number of keywords newly attached.
    ///   - detached: The number of keywords detached.
    init(attached: Int, detached: Int) {
        self.attached = attached
        self.detached = detached
    }
}

// MARK: - KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE

// The portable-kbite family. Bulk data NEVER rides the wire — the 10MB
// inbound line cap forbids it. The gm CLI resolves absolute staging paths
// client-side and the daemon reads/writes db_export.json at those paths
// (the KBITE_DIGEST idiom); zip assembly, source-tree copies, and
// cold-storage moves are all CLI-side.

/// Daemon writes the scrubbed db_export.json at `dbExportPath`. `anonymize`
/// carries the CLI-resolved machine roots as prefix→placeholder rules — the
/// daemon never learns gmcc env vars exist.
struct KbiteExportRequest: Codable, Hashable, Sendable {
    let code: String
    let dbExportPath: String
    let anonymize: [KbitePrefixRule]

    /// Creates a KBITE_EXPORT request to export a kbite to a JSON file.
    /// - Parameters:
    ///   - code: The kbite code.
    ///   - dbExportPath: The absolute path where the daemon writes db_export.json.
    ///   - anonymize: Prefix-to-placeholder rules for path anonymization.
    init(code: String, dbExportPath: String, anonymize: [KbitePrefixRule]) {
        self.code = code
        self.dbExportPath = dbExportPath
        self.anonymize = anonymize
    }
}

struct KbiteExportResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let code: String
    let resourceCount: Int
    let fileCount: Int
    let kbiteKeywordCount: Int
    let fileKeywordCount: Int
    let dbExportPath: String

    /// Creates a KBITE_EXPORT response with export summary and counts.
    /// - Parameters:
    ///   - kbiteUuid: The kbite uuid.
    ///   - code: The kbite code.
    ///   - resourceCount: The number of resources exported.
    ///   - fileCount: The number of resource files exported.
    ///   - kbiteKeywordCount: The number of kbite-level keywords.
    ///   - fileKeywordCount: The number of file-level keywords.
    ///   - dbExportPath: The path to the written db_export.json file.
    init(
        kbiteUuid: String,
        code: String,
        resourceCount: Int,
        fileCount: Int,
        kbiteKeywordCount: Int,
        fileKeywordCount: Int,
        dbExportPath: String
    ) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.kbiteKeywordCount = kbiteKeywordCount
        self.fileKeywordCount = fileKeywordCount
        self.dbExportPath = dbExportPath
    }
}

/// Collision policy when the archive's code already exists in the db.
/// `skip` (the CLI default) leaves the existing kbite untouched; `overwrite`
/// replaces content under the EXISTING kbite uuid so every `*_active_kbite`
/// registration survives.
enum KbiteImportCollision: String, Codable, Hashable, CaseIterable, Sendable {
    case skip
    case overwrite
}

/// Daemon reads db_export.json at `dbExportPath`, rehydrates placeholder
/// paths via `rehydrate`, and writes rows in one transaction.
///
/// Never creates registration rows — `gm kbite add` stays the only
/// registration door.
struct KbiteImportRequest: Codable, Hashable, Sendable {
    let dbExportPath: String
    let onCollision: KbiteImportCollision
    let rehydrate: [KbitePrefixRule]

    /// Creates a KBITE_IMPORT request to import a kbite from a JSON file.
    /// - Parameters:
    ///   - dbExportPath: The path to the db_export.json file to import.
    ///   - onCollision: The collision policy (skip or overwrite).
    ///   - rehydrate: Placeholder-to-prefix rules for path restoration.
    init(dbExportPath: String, onCollision: KbiteImportCollision, rehydrate: [KbitePrefixRule]) {
        self.dbExportPath = dbExportPath
        self.onCollision = onCollision
        self.rehydrate = rehydrate
    }
}

struct KbiteImportResponse: Codable, Hashable, Sendable {
    /// Never nil — the skip branch reports the existing kbite's uuid, the
    /// import branch the ensured one.
    ///
    /// Kept non-optional from birth: loosening a v22 field later is free,
    /// tightening never is.
    let kbiteUuid: String
    let code: String
    let imported: Bool
    let skippedExisting: Bool
    let resourceCount: Int
    let fileCount: Int
    let keywordCount: Int

    /// Creates a KBITE_IMPORT response with the kbite and import status.
    /// - Parameters:
    ///   - kbiteUuid: The imported or existing kbite uuid.
    ///   - code: The kbite code.
    ///   - imported: True if the kbite was newly imported; false if it existed.
    ///   - skippedExisting: True if an existing kbite was skipped due to collision.
    ///   - resourceCount: The number of resources in the kbite.
    ///   - fileCount: The number of resource files in the kbite.
    ///   - keywordCount: The number of keywords in the kbite.
    init(
        kbiteUuid: String,
        code: String,
        imported: Bool,
        skippedExisting: Bool,
        resourceCount: Int,
        fileCount: Int,
        keywordCount: Int
    ) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.imported = imported
        self.skippedExisting = skippedExisting
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.keywordCount = keywordCount
    }
}

/// One cascading delete: resources, files, junctions, and every scope
/// registration go with the kbite row (that unregistration is the desired
/// behavior here, unlike overwrite).
///
/// Orphaned shared-vocabulary keywords are garbage-collected in the same transaction. daemon_event history survives.
struct KbiteDeleteRequest: Codable, Hashable, Sendable {
    let code: String

    /// Creates a KBITE_DELETE request.
    /// - Parameter code: The kbite code.
    init(code: String) {
        self.code = code
    }
}

struct KbiteDeleteResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let code: String
    let deletedResources: Int
    let deletedFiles: Int
    let deletedRegistrations: Int
    let gcKeywordCount: Int

    /// Creates a KBITE_DELETE response with deletion counts.
    /// - Parameters:
    ///   - kbiteUuid: The deleted kbite uuid.
    ///   - code: The kbite code.
    ///   - deletedResources: The number of deleted resources.
    ///   - deletedFiles: The number of deleted resource files.
    ///   - deletedRegistrations: The number of deleted scope registrations.
    ///   - gcKeywordCount: The number of garbage-collected shared keywords.
    init(
        kbiteUuid: String,
        code: String,
        deletedResources: Int,
        deletedFiles: Int,
        deletedRegistrations: Int,
        gcKeywordCount: Int
    ) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.deletedResources = deletedResources
        self.deletedFiles = deletedFiles
        self.deletedRegistrations = deletedRegistrations
        self.gcKeywordCount = gcKeywordCount
    }
}
