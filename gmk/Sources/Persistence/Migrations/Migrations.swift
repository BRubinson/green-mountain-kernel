import Foundation
import GRDB

/// Versioned schema migrations.
///
/// GRDB's private `grdb_migrations` table is the replay guard; the spec-visible
/// ledger is `schema_migrations`, the only table not wrapped in the BaseEntity
/// columns, which each migration appends its own row to.
///
/// Each migration is one `m00NN_<name>.swift` registering exactly one id; this
/// file only ORDERS them, and a file missing from `ladder` never runs.
enum Migrations {
    /// Bump alongside new registerMigration calls.
    ///
    /// Shipped migration bodies are frozen: the migrator keys on the migration id and silently skips a changed body on
    /// an existing db, so every schema change lands as a new registerMigration.
    static let currentSchemaVersion = 30

    /// The five BaseEntity columns wrapped into every domain table.
    /// `id` is the internal rowid; `uuid` is the external join key — all FKs
    /// reference uuid, never id.
    static let baseColumns = """
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        version INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
        """

    /// The order the migrator runs in.
    ///
    /// One entry per file in this directory; a step missing here never runs. Append, never reorder.
    private static let ladder: [@Sendable (inout DatabaseMigrator) -> Void] = [
        m0001_baseSchema,
        m0002_clarificationArchitectureLifecycleV2,
        m0003_searchIndexes,
        m0004_explorationReviewReports,
        m0005_purgeLegacyConcepts,
        m0006_dropDraftPlaceholderSummaries,
        m0007_dopeDomainModel,
        m0008_dopeBaseComposableEntities,
        m0009_dopePropertyBaseOrigin,
        m0010_diagramDomainModel,
        m0011_projectPrimaryBranch,
        m0012_dopePersistenceRenameAndSoftDelete,
        m0013_dopeScopeTierLadder,
        m0014_dopeCogElement,
        m0015_dopeSearchIndexes,
        m0016_diagramDopeScopeBinding,
        m0017_relationshipTargetAndDropMaskKind,
        m0018_diagramDopeScopePersistenceLayer,
        m0019_cogHullsAndPersistenceOwner,
        m0020_dopeElementProvenance,
        m0021_diagramVocabularyAndTierCollapse,
        m0022_promptQualifiedDiagram,
        m0023_agentBriefing,
        m0024_diagramStudio,
        m0025_dynamicWorkflows,
        m0026_claudeSessionAttribution,
        m0027_ckfsToGmfs,
        m0028_promptLifecycleCollapse,
        m0029_testRunLock,
        m0030_retiredRootConfigValues,
    ]

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        for step in ladder { step(&migrator) }
        return migrator
    }
}
