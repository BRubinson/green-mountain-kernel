import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0015 — FTS5 mirrors over the dope tables. Pure ADD, and exactly
    // the migration m0007's own comment anticipated: "mirrors attach later
    // as a pure-ADD migration exactly as m0003 did for m0002's tables."
    //
    // The FtsSpec loop is a PRIVATE COPY of m0003's, per the frozen-
    // migration rule — a registered migration never reaches out to shared
    // code that might change under it.
    //
    // Sequenced strictly AFTER both rebuilds: a DROP TABLE takes its
    // triggers with it (m0005 step 5), so mirrors attached before m0012/
    // m0013 would have been silently destroyed.
    static func m0015_dopeSearchIndexes(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0015_dopeSearchIndexes") { db in
            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(source: "dope_scope", columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence", columns: ["code", "name", "description"]),
                FtsSpec(
                    source: "dope_persistence_entity",
                    columns: ["code", "name", "description"]),
                FtsSpec(
                    source: "dope_persistence_entity_property",
                    columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence_enum", columns: ["code", "name", "description"]),
                FtsSpec(
                    source: "dope_persistence_enum_option",
                    columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_cog", columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_cog_element", columns: ["code", "name", "description"]),
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
                arguments: [15, Store.isoNow()]
            )
        }
    }
}
