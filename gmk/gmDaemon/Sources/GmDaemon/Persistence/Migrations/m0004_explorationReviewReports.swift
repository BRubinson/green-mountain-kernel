import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0004 — db-native exploration + review reports. Pure ADD: five BaseEntity
    // tables plus five external-content FTS5 mirrors, no data motion.
    // finding_rating is deliberately nullable: NULL marks unranked, and the
    // complete transition refuses while any NULL remains. The FtsSpec loop is a
    // private copy of m0003's — never share helpers across migration bodies.
    // The `_ad` triggers ride the global recursive_triggers pragma so FK cascade
    // deletes stay FTS-synced. No PRAGMA in this body.
    static func m0004_explorationReviewReports(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0004_explorationReviewReports") { db in
            try db.execute(
                sql: """
                    CREATE TABLE exploration_summary (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        status TEXT NOT NULL DEFAULT 'exploring'
                            CHECK (status IN ('exploring', 'complete')),
                        overview TEXT NOT NULL DEFAULT '',
                        UNIQUE(prompt_uuid)
                    );

                    CREATE TABLE exploration_key_file (
                        \(baseColumns),
                        exploration_summary_uuid TEXT NOT NULL
                            REFERENCES exploration_summary(uuid) ON DELETE CASCADE,
                        file_path TEXT NOT NULL,
                        UNIQUE(exploration_summary_uuid, file_path)
                    );

                    CREATE TABLE exploration_finding (
                        \(baseColumns),
                        exploration_summary_uuid TEXT NOT NULL
                            REFERENCES exploration_summary(uuid) ON DELETE CASCADE,
                        kind TEXT NOT NULL
                            CHECK (kind IN ('persistence_model', 'implementation_pattern',
                                            'existing_functionality', 'scope_creep_risk',
                                            'general_relevant_change', 'other')),
                        title TEXT NOT NULL,
                        body TEXT NOT NULL,
                        agent_name TEXT NOT NULL,
                        finding_rating INTEGER
                            CHECK (finding_rating IS NULL OR finding_rating BETWEEN 0 AND 999)
                    );

                    CREATE TABLE review_summary (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        status TEXT NOT NULL DEFAULT 'reviewing'
                            CHECK (status IN ('reviewing', 'complete')),
                        verdict TEXT
                            CHECK (verdict IN ('approved', 'approved_with_nits',
                                               'changes_requested', 'legacy_unstated')),
                        overview TEXT NOT NULL DEFAULT '',
                        CHECK (status != 'complete' OR verdict IS NOT NULL),
                        UNIQUE(prompt_uuid)
                    );

                    CREATE TABLE review_finding (
                        \(baseColumns),
                        review_summary_uuid TEXT NOT NULL
                            REFERENCES review_summary(uuid) ON DELETE CASCADE,
                        kind TEXT NOT NULL
                            CHECK (kind IN ('correctness_bug', 'spec_deviation',
                                            'regression_risk', 'security',
                                            'simplification', 'other')),
                        title TEXT NOT NULL,
                        body TEXT NOT NULL,
                        file_path TEXT,
                        line_start INTEGER,
                        line_end INTEGER,
                        agent_name TEXT NOT NULL,
                        finding_rating INTEGER
                            CHECK (finding_rating IS NULL OR finding_rating BETWEEN 0 AND 999),
                        status TEXT NOT NULL DEFAULT 'open'
                            CHECK (status IN ('open', 'fixed', 'accepted', 'wont_fix')),
                        CHECK (line_end IS NULL OR line_start IS NOT NULL)
                    );

                    CREATE INDEX idx_exploration_summary_prompt_uuid
                        ON exploration_summary(prompt_uuid);
                    CREATE INDEX idx_exploration_key_file_summary_fk
                        ON exploration_key_file(exploration_summary_uuid);
                    CREATE INDEX idx_exploration_finding_summary_fk
                        ON exploration_finding(exploration_summary_uuid);
                    CREATE INDEX idx_review_summary_prompt_uuid
                        ON review_summary(prompt_uuid);
                    CREATE INDEX idx_review_finding_summary_fk
                        ON review_finding(review_summary_uuid);
                    """
            )

            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(
                    source: "exploration_summary",
                    columns: ["overview"]
                ),
                FtsSpec(
                    source: "exploration_key_file",
                    columns: ["file_path"]
                ),
                FtsSpec(
                    source: "exploration_finding",
                    columns: ["title", "body"]
                ),
                FtsSpec(
                    source: "review_summary",
                    columns: ["overview"]
                ),
                FtsSpec(
                    source: "review_finding",
                    columns: ["title", "body", "file_path"]
                ),
            ]
            for spec in specs {
                let fts = "\(spec.source)_fts"
                let cols = spec.columns.joined(separator: ", ")
                let newVals = spec.columns.map { "new.\($0)" }.joined(separator: ", ")
                let oldVals = spec.columns.map { "old.\($0)" }.joined(separator: ", ")
                try db.execute(
                    sql: """
                        CREATE VIRTUAL TABLE \(fts) USING fts5(
                            \(cols),
                            content='\(spec.source)',
                            content_rowid='id'
                        );

                        CREATE TRIGGER \(spec.source)_ai AFTER INSERT ON \(spec.source) BEGIN
                            INSERT INTO \(fts)(rowid, \(cols))
                            VALUES (new.id, \(newVals));
                        END;

                        CREATE TRIGGER \(spec.source)_ad AFTER DELETE ON \(spec.source) BEGIN
                            INSERT INTO \(fts)(\(fts), rowid, \(cols))
                            VALUES ('delete', old.id, \(oldVals));
                        END;

                        CREATE TRIGGER \(spec.source)_au AFTER UPDATE ON \(spec.source) BEGIN
                            INSERT INTO \(fts)(\(fts), rowid, \(cols))
                            VALUES ('delete', old.id, \(oldVals));
                            INSERT INTO \(fts)(rowid, \(cols))
                            VALUES (new.id, \(newVals));
                        END;

                        INSERT INTO \(fts)(\(fts)) VALUES('rebuild');
                        """
                )
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [4, Store.isoNow()]
            )
        }
    }
}
