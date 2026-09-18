import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0013 — dope_scope widened from two tiers to four:
    // BASE_PROJECT / PROJECT_ITEM / SESSION_INSTANCE / SESSION_INSTANCE_ITEM.
    //
    // SQLite cannot ALTER a CHECK or a column's NOT NULL-ness, so this is
    // a full rebuild in the m0002/m0008 grammar. Registered .deferred
    // with NO PRAGMA in the body: the five dope_persistence* tables
    // CASCADE-reference this one.
    //
    // Ownership is m0010's chain-non-null tier ladder, ported verbatim:
    // each tier fills its own FK and every ancestor's, one CHECK per
    // tier, one PARTIAL unique index per tier (four, replacing the two
    // session_uuid-keyed indexes, which do not generalize past two
    // tiers). project_uuid is ALWAYS NOT NULL.
    //
    // The two existing scope types are pure VALUE renames:
    //   SESSION_BASE -> SESSION_INSTANCE
    //   PROMPT       -> SESSION_INSTANCE_ITEM
    // which is what makes this drop-in rather than a rewrite —
    // dopeScopeCandidates, dopeGet, dopeList, DopeBootSync and the
    // diagram binding ladder all keep working on a renamed constant.
    //
    // The prompt_uuid CHECK stays a BICONDITIONAL, exactly as m0007's
    // was. A nullable slot there would re-stamp m0007's NULLs-are-
    // distinct trap: UNIQUE(session_uuid, prompt_uuid, code) silently
    // constrains NOTHING for a prompt-free row. A session-level personal
    // overlay, if ever wanted, is a FIFTH tier — never a nullable slot.
    //
    // promoted_from_* is the BASE_PROJECT promotion high-water mark
    // (CHECK-restricted to that tier). It is deliberately separate from
    // the row's own `revision`: keying promotion on "did THIS scope
    // promote before" lets two instances on one branch overwrite each
    // other at every alternating boot, and without a recorded high-water
    // the same session re-promotes identical content at every
    // SessionStart. Keeping them separate also lets BASE_PROJECT.revision
    // stay its own forward-only counter that a lower-revision winner can
    // never drag backward.
    //
    // The copy uses LEFT JOINs plus a pre-flight refusal, NOT inner
    // joins: an inner join would silently DROP any scope whose
    // session/instance lineage is broken — project_uuid NOT NULL would
    // never fire, because the row simply would not be selected. On an
    // append-only db a migration fails loudly; it never deletes a row.
    static func m0013_dopeScopeTierLadder(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0013_dopeScopeTierLadder") { db in
            let orphans =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM dope_scope ds
                        LEFT JOIN session  s ON s.uuid = ds.session_uuid
                        LEFT JOIN instance i ON i.uuid = s.instance_uuid
                        WHERE i.project_uuid IS NULL
                        """) ?? -1
            guard orphans == 0 else {
                throw StoreError.corruptState(
                    entity: "dope_scope",
                    detail: "m0013: \(orphans) scope(s) have no resolvable project "
                        + "through session->instance; refusing to drop them")
            }
            let before = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_scope") ?? -1

            try db.execute(
                sql: """
                    CREATE TABLE dope_scope_new (
                        \(baseColumns),
                        project_uuid  TEXT NOT NULL REFERENCES project(uuid)  ON DELETE CASCADE,
                        instance_uuid TEXT          REFERENCES instance(uuid) ON DELETE CASCADE,
                        session_uuid  TEXT          REFERENCES session(uuid)  ON DELETE CASCADE,
                        prompt_uuid   TEXT          REFERENCES prompt(uuid)   ON DELETE CASCADE,
                        scope_type TEXT NOT NULL
                            CHECK (scope_type IN ('BASE_PROJECT', 'PROJECT_ITEM',
                                                  'SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM')),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                        deleted_on TEXT,
                        promoted_from_scope_uuid TEXT,
                        promoted_from_revision INTEGER,
                        promoted_from_updated_at TEXT,
                        CHECK ((instance_uuid IS NOT NULL)
                               = (scope_type IN ('SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM'))),
                        CHECK ((session_uuid IS NOT NULL)
                               = (scope_type IN ('SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM'))),
                        CHECK ((prompt_uuid IS NOT NULL) = (scope_type = 'SESSION_INSTANCE_ITEM')),
                        CHECK (promoted_from_scope_uuid IS NULL OR scope_type = 'BASE_PROJECT'),
                        CHECK (promoted_from_revision IS NULL OR scope_type = 'BASE_PROJECT'),
                        CHECK (promoted_from_updated_at IS NULL OR scope_type = 'BASE_PROJECT')
                    );

                    INSERT INTO dope_scope_new
                        (id, uuid, version, created_at, updated_at,
                         project_uuid, instance_uuid, session_uuid, prompt_uuid,
                         scope_type, code, name, description, revision)
                    SELECT ds.id, ds.uuid, ds.version, ds.created_at, ds.updated_at,
                           i.project_uuid, s.instance_uuid, ds.session_uuid, ds.prompt_uuid,
                           CASE ds.scope_type
                                WHEN 'SESSION_BASE' THEN 'SESSION_INSTANCE'
                                ELSE 'SESSION_INSTANCE_ITEM'
                           END,
                           ds.code, ds.name, ds.description, ds.revision
                      FROM dope_scope ds
                      LEFT JOIN session  s ON s.uuid = ds.session_uuid
                      LEFT JOIN instance i ON i.uuid = s.instance_uuid;

                    DROP TABLE dope_scope;
                    ALTER TABLE dope_scope_new RENAME TO dope_scope;

                    CREATE UNIQUE INDEX idx_dope_scope_base_project_code
                        ON dope_scope(project_uuid, code)
                        WHERE scope_type = 'BASE_PROJECT' AND deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_scope_project_item_code
                        ON dope_scope(project_uuid, code)
                        WHERE scope_type = 'PROJECT_ITEM' AND deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_scope_session_instance_code
                        ON dope_scope(session_uuid, code)
                        WHERE scope_type = 'SESSION_INSTANCE' AND deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_scope_session_instance_item_code
                        ON dope_scope(session_uuid, prompt_uuid, code)
                        WHERE scope_type = 'SESSION_INSTANCE_ITEM' AND deleted_on IS NULL;

                    CREATE INDEX idx_dope_scope_project_fk  ON dope_scope(project_uuid);
                    CREATE INDEX idx_dope_scope_instance_fk ON dope_scope(instance_uuid);
                    CREATE INDEX idx_dope_scope_session_fk  ON dope_scope(session_uuid);
                    CREATE INDEX idx_dope_scope_prompt_fk   ON dope_scope(prompt_uuid);
                    """)

            let after = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_scope") ?? -1
            guard before == after else {
                throw StoreError.corruptState(
                    entity: "dope_scope",
                    detail: "m0013 row-count mismatch: before \(before) after \(after)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [13, Store.isoNow()]
            )
        }
    }
}
