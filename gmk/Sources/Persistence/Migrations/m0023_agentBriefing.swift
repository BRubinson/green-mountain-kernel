import Foundation
import GRDB

extension Migrations {
    // m0023 — agent_briefing + prompt_activation: the context package a briefer
    // assembles for a phase, and the activation registry hooks attribute through.
    // Re-opening an (owner, step) pair RESETS the row to building: a step's
    // briefing is always its CURRENT briefing. briefing_for_step and status carry
    // NO db CHECK; validity lives in BriefingStepSpec. session_uuid is ALWAYS
    // populated and prompt_uuid is NULL exactly for a task-owned briefing, so
    // uniqueness is a partial index PAIR — SQLite UNIQUE admits multiple NULLs.
    // dope_refs are DOT-PATHS as TEXT JSON; dangling refs are legal ghosts.
    static func m0023_agentBriefing(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0023_agentBriefing") { db in
            try db.execute(
                sql: """
                    CREATE TABLE agent_briefing (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                        prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                        briefing_for_step TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'building',
                        body TEXT NOT NULL DEFAULT '',
                        dope_refs TEXT NOT NULL DEFAULT '[]',
                        kbite_refs TEXT NOT NULL DEFAULT '[]',
                        dope_scope_uuid TEXT REFERENCES dope_scope(uuid) ON DELETE SET NULL,
                        dope_scope_revision INTEGER
                    );

                    CREATE UNIQUE INDEX idx_agent_briefing_prompt_step
                        ON agent_briefing(prompt_uuid, briefing_for_step)
                        WHERE prompt_uuid IS NOT NULL;
                    CREATE UNIQUE INDEX idx_agent_briefing_session_step
                        ON agent_briefing(session_uuid, briefing_for_step)
                        WHERE prompt_uuid IS NULL;
                    CREATE INDEX idx_agent_briefing_session_fk
                        ON agent_briefing(session_uuid);
                    CREATE INDEX idx_agent_briefing_prompt_fk
                        ON agent_briefing(prompt_uuid);

                    -- The activation registry. NOT a single pointer on the
                    -- session row: several Claude Code instances routinely run
                    -- DIFFERENT prompts on the same GMCC session at once, and a
                    -- last-writer-wins column would let the second instance steal
                    -- the first's attribution. One row per running instance
                    -- (client_key = the caller's nearest claude-ancestor process
                    -- identity, resolved client-side by gm): set-status
                    -- implementing claims it, done releases it. Attribution
                    -- resolves caller's-own-activation first, then the session's
                    -- single activation when unambiguous, else stays unattributed.
                    CREATE TABLE prompt_activation (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        client_key TEXT NOT NULL
                    );

                    CREATE UNIQUE INDEX idx_prompt_activation_client
                        ON prompt_activation(client_key);
                    CREATE UNIQUE INDEX idx_prompt_activation_prompt
                        ON prompt_activation(prompt_uuid);
                    CREATE INDEX idx_prompt_activation_session_fk
                        ON prompt_activation(session_uuid);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [23, Store.isoNow()]
            )
        }
    }
}
