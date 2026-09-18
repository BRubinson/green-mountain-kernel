import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0003 — full-text search over prompt/clarification/architecture
    // text (the SEARCH message). Append-only: adds six external-content
    // FTS5 mirrors + sync triggers, touches no domain row. Six separate
    // tables is forced, not chosen — external-content FTS5 binds one
    // virtual table to exactly one source via content_rowid; the search
    // query UNIONs across them. The `_ad` triggers ride the globally
    // enabled recursive_triggers pragma (Store) so they fire on FK
    // cascade deletes too. Each table ends with a one-time
    // `INSERT INTO <fts>(<fts>) VALUES('rebuild')` — triggers only fire
    // on future writes, so without the rebuild all pre-existing history
    // would be unsearchable. No PRAGMA in this body (silently ignored
    // inside a transaction).
    static func m0003_searchIndexes(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0003_searchIndexes") { db in
            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(
                    source: "prompt",
                    columns: ["name", "goal", "detail", "backstory"]),
                FtsSpec(
                    source: "clarification_summary",
                    columns: ["refined_goal", "refined_detail", "backstory_note"]),
                FtsSpec(
                    source: "clarification",
                    columns: ["question", "answer"]),
                FtsSpec(
                    source: "architecture_summary",
                    columns: ["body"]),
                FtsSpec(
                    source: "architecture_general_change",
                    columns: ["file_path", "reason_brief", "change_code"]),
                FtsSpec(
                    source: "architecture_persistence_change",
                    columns: ["class_name", "file_path", "reason_brief"]),
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
                        """)
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [3, Store.isoNow()]
            )
        }
    }
}
