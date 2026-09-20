import Foundation
import GRDB

extension Migrations {
    static func m0001_baseSchema(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0001_baseSchema") { db in
            try db.execute(
                sql: """
                    CREATE TABLE schema_migrations (
                        version INTEGER PRIMARY KEY,
                        applied_at TEXT NOT NULL
                    );

                    CREATE TABLE project (
                        \(baseColumns),
                        git_repo_name TEXT NOT NULL,
                        code TEXT NOT NULL UNIQUE,
                        name TEXT NOT NULL,
                        ckfs_relative_storage_path TEXT NOT NULL
                    );

                    CREATE TABLE instance (
                        \(baseColumns),
                        project_uuid TEXT NOT NULL REFERENCES project(uuid),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        absolute_file_system_path TEXT NOT NULL,
                        ckfs_relative_storage_path TEXT NOT NULL,
                        UNIQUE(project_uuid, name)
                    );

                    CREATE TABLE session (
                        \(baseColumns),
                        instance_uuid TEXT NOT NULL REFERENCES instance(uuid),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        backstory TEXT NOT NULL,
                        goal TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active', 'closed')),
                        ckfs_relative_storage_path TEXT NOT NULL,
                        UNIQUE(instance_uuid, code)
                    );

                    CREATE TABLE prompt (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid),
                        seq INTEGER NOT NULL,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        backstory TEXT NOT NULL,
                        goal TEXT NOT NULL,
                        detail TEXT NOT NULL,
                        command TEXT NOT NULL DEFAULT '',
                        status TEXT NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft', 'clarifying', 'clarified')),
                        ckfs_relative_storage_path TEXT NOT NULL,
                        UNIQUE(session_uuid, code),
                        UNIQUE(session_uuid, seq)
                    );

                    CREATE TABLE prompt_artifact (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        file_path TEXT NOT NULL,
                        kind TEXT NOT NULL
                            CHECK (kind IN ('explore', 'architecture', 'review', 'qualified', 'other')),
                        note TEXT,
                        UNIQUE(prompt_uuid, file_path)
                    );

                    CREATE TABLE kbite (
                        \(baseColumns),
                        code TEXT NOT NULL UNIQUE
                    );

                    CREATE TABLE prompt_active_kbite (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                        UNIQUE(prompt_uuid, kbite_uuid)
                    );

                    CREATE TABLE session_active_kbite (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                        kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                        UNIQUE(session_uuid, kbite_uuid)
                    );

                    CREATE TABLE instance_active_kbite (
                        \(baseColumns),
                        instance_uuid TEXT NOT NULL REFERENCES instance(uuid) ON DELETE CASCADE,
                        kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                        UNIQUE(instance_uuid, kbite_uuid)
                    );

                    CREATE TABLE project_active_kbite (
                        \(baseColumns),
                        project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                        kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                        UNIQUE(project_uuid, kbite_uuid)
                    );

                    CREATE TABLE session_file (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid),
                        relative_path TEXT NOT NULL,
                        active INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(session_uuid, relative_path)
                    );

                    CREATE TABLE file_change (
                        \(baseColumns),
                        session_file_uuid TEXT NOT NULL REFERENCES session_file(uuid),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid),
                        prompt_uuid TEXT REFERENCES prompt(uuid),
                        change_kind TEXT NOT NULL DEFAULT 'edit'
                            CHECK (change_kind IN ('edit', 'create', 'delete', 'rename'))
                    );

                    CREATE TABLE file_change_range (
                        \(baseColumns),
                        file_change_uuid TEXT NOT NULL REFERENCES file_change(uuid) ON DELETE CASCADE,
                        line_start INTEGER NOT NULL,
                        line_end INTEGER NOT NULL,
                        changed_content TEXT
                    );

                    CREATE TABLE daemon_event (
                        \(baseColumns),
                        kind TEXT NOT NULL,
                        subject_uuid TEXT,
                        payload TEXT
                    );

                    CREATE INDEX idx_instance_project_uuid ON instance(project_uuid);
                    CREATE INDEX idx_session_instance_uuid ON session(instance_uuid);
                    CREATE INDEX idx_prompt_session_uuid ON prompt(session_uuid);
                    CREATE INDEX idx_prompt_artifact_prompt_uuid ON prompt_artifact(prompt_uuid);
                    CREATE INDEX idx_prompt_active_kbite_prompt_uuid ON prompt_active_kbite(prompt_uuid);
                    CREATE INDEX idx_prompt_active_kbite_kbite_uuid ON prompt_active_kbite(kbite_uuid);
                    CREATE INDEX idx_session_active_kbite_session_uuid ON session_active_kbite(session_uuid);
                    CREATE INDEX idx_session_active_kbite_kbite_uuid ON session_active_kbite(kbite_uuid);
                    CREATE INDEX idx_instance_active_kbite_instance_uuid ON instance_active_kbite(instance_uuid);
                    CREATE INDEX idx_instance_active_kbite_kbite_uuid ON instance_active_kbite(kbite_uuid);
                    CREATE INDEX idx_project_active_kbite_project_uuid ON project_active_kbite(project_uuid);
                    CREATE INDEX idx_project_active_kbite_kbite_uuid ON project_active_kbite(kbite_uuid);
                    CREATE INDEX idx_session_file_session_uuid ON session_file(session_uuid);
                    CREATE INDEX idx_file_change_session_file_uuid ON file_change(session_file_uuid);
                    CREATE INDEX idx_file_change_session_uuid ON file_change(session_uuid);
                    CREATE INDEX idx_file_change_prompt_uuid ON file_change(prompt_uuid);
                    CREATE INDEX idx_file_change_range_file_change_uuid ON file_change_range(file_change_uuid);
                    CREATE INDEX idx_daemon_event_subject_uuid ON daemon_event(subject_uuid);
                    CREATE INDEX idx_daemon_event_kind ON daemon_event(kind);
                    CREATE INDEX idx_daemon_event_created_at ON daemon_event(created_at);
                    """
            )

            // Kbite content family (v16 prompt 4), folded into the single
            // re-baselined m0001: the digested-content side — resources,
            // files, keyword vocabulary, and the FTS5 mirror backing
            // KBITE_SEARCH.
            try db.execute(
                sql: """
                    CREATE TABLE keyword (
                        \(baseColumns),
                        keyword TEXT NOT NULL UNIQUE
                    );

                    CREATE TABLE kbite_keyword_junction (
                        \(baseColumns),
                        kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                        keyword_uuid TEXT NOT NULL REFERENCES keyword(uuid) ON DELETE CASCADE,
                        UNIQUE(kbite_uuid, keyword_uuid)
                    );

                    CREATE TABLE kbite_resource (
                        \(baseColumns),
                        kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                        resource_name TEXT NOT NULL,
                        resource_summary TEXT NOT NULL,
                        resource_type TEXT NOT NULL
                            CHECK (resource_type IN ('documentation', 'example_project', 'api_reference', 'blogs', 'all_others')),
                        resource_trust INTEGER NOT NULL DEFAULT 0
                            CHECK (resource_trust BETWEEN 0 AND 100)
                    );

                    CREATE TABLE kbite_resource_file (
                        \(baseColumns),
                        kbite_resource_uuid TEXT NOT NULL REFERENCES kbite_resource(uuid) ON DELETE CASCADE,
                        resource_file_name TEXT NOT NULL,
                        resource_file_summary TEXT NOT NULL DEFAULT '',
                        resource_file_content TEXT
                    );

                    CREATE TABLE resource_file_keyword_junction (
                        \(baseColumns),
                        file_uuid TEXT NOT NULL REFERENCES kbite_resource_file(uuid) ON DELETE CASCADE,
                        keyword_uuid TEXT NOT NULL REFERENCES keyword(uuid) ON DELETE CASCADE,
                        UNIQUE(file_uuid, keyword_uuid)
                    );

                    CREATE INDEX idx_kbite_keyword_junction_kbite_uuid ON kbite_keyword_junction(kbite_uuid);
                    CREATE INDEX idx_kbite_keyword_junction_keyword_uuid ON kbite_keyword_junction(keyword_uuid);
                    CREATE INDEX idx_kbite_resource_kbite_uuid ON kbite_resource(kbite_uuid);
                    CREATE INDEX idx_kbite_resource_file_kbite_resource_uuid ON kbite_resource_file(kbite_resource_uuid);
                    CREATE INDEX idx_resource_file_keyword_junction_file_uuid ON resource_file_keyword_junction(file_uuid);
                    CREATE INDEX idx_resource_file_keyword_junction_keyword_uuid ON resource_file_keyword_junction(keyword_uuid);

                    CREATE VIRTUAL TABLE kbite_resource_file_fts USING fts5(
                        resource_file_name,
                        resource_file_summary,
                        resource_file_content,
                        content='kbite_resource_file',
                        content_rowid='id'
                    );

                    CREATE TRIGGER kbite_resource_file_ai AFTER INSERT ON kbite_resource_file BEGIN
                        INSERT INTO kbite_resource_file_fts(rowid, resource_file_name, resource_file_summary, resource_file_content)
                        VALUES (new.id, new.resource_file_name, new.resource_file_summary, new.resource_file_content);
                    END;

                    CREATE TRIGGER kbite_resource_file_ad AFTER DELETE ON kbite_resource_file BEGIN
                        INSERT INTO kbite_resource_file_fts(kbite_resource_file_fts, rowid, resource_file_name, resource_file_summary, resource_file_content)
                        VALUES ('delete', old.id, old.resource_file_name, old.resource_file_summary, old.resource_file_content);
                    END;

                    CREATE TRIGGER kbite_resource_file_au AFTER UPDATE ON kbite_resource_file BEGIN
                        INSERT INTO kbite_resource_file_fts(kbite_resource_file_fts, rowid, resource_file_name, resource_file_summary, resource_file_content)
                        VALUES ('delete', old.id, old.resource_file_name, old.resource_file_summary, old.resource_file_content);
                        INSERT INTO kbite_resource_file_fts(rowid, resource_file_name, resource_file_summary, resource_file_content)
                        VALUES (new.id, new.resource_file_name, new.resource_file_summary, new.resource_file_content);
                    END;
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [1, Store.isoNow()]
            )
        }
    }
}
