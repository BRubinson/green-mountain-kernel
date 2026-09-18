import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0023 — agent_briefing + prompt_activation: the context package a
    // briefer agent assembles for a phase, and the activation registry that
    // lets hooks attribute work without arguments.
    //
    // agent_briefing follows m0022's restraint, not the report families:
    // a briefing is spawn-time plumbing consumed once, not a report built
    // across turns — so no findings children, no FTS mirror, and a
    // two-state consumption gate instead of a status machine. Re-opening
    // an existing (owner, step) pair RESETS the row to building: a step's
    // briefing is always its CURRENT briefing, never a pile of drafts.
    //
    // briefing_for_step and status carry NO db CHECK on purpose (the
    // m0021 vocabulary rule): validity lives in BriefingStepSpec, so a
    // future step (pre_implementation, pre_review) is a registry entry,
    // never a migration.
    //
    // Ownership: session_uuid is ALWAYS populated (the daemon derives it
    // from the prompt's owner chain), because it is the attribution
    // anchor for task-owned rows and the single list key for GMVibes.
    // prompt_uuid is NULL exactly when a /gm_task run owns the briefing.
    // SQLite UNIQUE admits multiple NULLs, so uniqueness is a partial
    // index PAIR: prompt-owned rows unique per (prompt, step), task-owned
    // rows unique per (session, step). "The prompt belongs to the
    // session" is a Swift store guard (m0016 precedent — a CHECK cannot
    // reference another table).
    //
    // dope_scope_uuid + dope_scope_revision are the staleness evidence
    // (m0022's fingerprint principle): stamped SERVER-SIDE at complete so
    // the writing agent cannot mis-stamp, compared against the live scope
    // revision at every read — the reader is WARNED about drift, never
    // blocked, honoring the fetch-fresh-per-phase guardrail.
    //
    // dope_refs holds DOT-PATHS and kbite_refs {file_uuid, brief} pairs
    // as TEXT JSON: point-in-time, deliberately non-normalized, dangling
    // refs are legal and render as ghosts (diagram-binding precedent).
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
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [23, Store.isoNow()]
            )
        }
    }
}
