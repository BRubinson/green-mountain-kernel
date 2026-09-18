import Foundation
import GRDB
import GmDaemonSdk

/// Versioned schema migrations.
///
/// GRDB's DatabaseMigrator keeps its own private `grdb_migrations` replay
/// guard; the spec-visible ledger is the separate `schema_migrations` table
/// (the only table not wrapped in the BaseEntity columns), which each
/// migration appends its own row to.
///
/// Each migration lives in its own `m00NN_<name>.swift` beside this file, as
/// `extension Migrations { static func m00NN_<name>(_:) }` registering exactly
/// one id. This file only ORDERS them: `ladder` is the run order, because
/// Swift cannot enumerate extensions and a directory listing is not a
/// registration. Adding a migration is a new file AND a new ladder entry.
public enum Migrations {
    /// Bump alongside new registerMigration calls.
    /// The re-baseline era ended at m0002: the db is append-only now. m0001's
    /// body is FROZEN — the migrator keys on the migration id and silently
    /// skips a changed body on an existing db, so any schema change lands as a
    /// new registerMigration and existing databases upgrade in place. Never
    /// instruct anyone to wipe the database file again.
    public static let currentSchemaVersion = 30

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

    /// The ladder, in the order the migrator runs it. A step missing here is a
    /// step that never runs, and `testTheLedgerIsDenseAndUnique` is what
    /// catches it. One entry per file in this directory; append, never reorder.
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

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        for step in ladder { step(&migrator) }
        return migrator
    }
}
