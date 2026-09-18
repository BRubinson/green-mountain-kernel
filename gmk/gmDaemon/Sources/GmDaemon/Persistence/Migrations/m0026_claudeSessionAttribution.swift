import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0026 — Session-bound hook attribution. PRECONDITION: a BACKUP.
    //
    // One attribution path, resolved from the PostToolUse payload plus
    // the db. claude_session_binding maps Claude Code's conversation uuid
    // to a gmcc session; agent_registration answers "who is agent X" for
    // an opaque agent_id; file_change grows the typed payload columns the
    // two resolve against. Pure ADD — file_change carries a CHECK only on
    // change_kind, which is untouched, so no table is rebuilt.
    //
    // claude_turn_id is THE naming trap of this migration. The payload
    // field is called prompt_id, but it is Claude Code's TURN id and has
    // nothing to do with a gmcc prompt uuid; the column is named for what
    // it holds so the confusion cannot be inherited by a reader.
    //
    // The new columns are NULL for every pre-m0026 row. There is no
    // backfill: nothing outside a payload can know a tool_use_id.
    static func m0026_claudeSessionAttribution(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0026_claudeSessionAttribution") { db in
            // ---- claude_session_binding: the payload-side attribution key.
            // A gmcc session is instance+branch; this key is Claude Code's
            // conversation uuid — different things, hence the qualified name.
            // It pins the SESSION, not a prompt: at SessionStart the prompt
            // usually does not exist yet, and one conversation legitimately
            // walks several prompts, so the prompt stays live-derived from
            // the pinned session.
            try db.execute(
                sql: """
                    CREATE TABLE claude_session_binding (
                        \(baseColumns),
                        claude_session_id TEXT NOT NULL,
                        session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE
                    );

                    -- THIS INDEX IS THE PIN-ONCE DECISION: the binding is written
                    -- once at SessionStart and an INSERT OR IGNORE re-run bounces
                    -- off the index, so pin-once is a schema fact rather than a
                    -- branch in Swift that some later caller can skip. There is
                    -- deliberately NO other column here — a mid-session checkout
                    -- leaves the binding pointing at the old branch's session and
                    -- that staleness is ACCEPTED, undetected, by decision. A
                    -- column nobody reads (a branch, a bound-at, an invalidated
                    -- flag) is the first step back toward the drift detection and
                    -- re-binding that were declined.
                    CREATE UNIQUE INDEX idx_claude_session_binding_claude_session_id
                        ON claude_session_binding(claude_session_id);
                    CREATE INDEX idx_claude_session_binding_session_fk
                        ON claude_session_binding(session_uuid);
                    """)

            // ---- agent_registration: identity for an opaque agent_id.
            // Two writers merge into ONE row per agent: the SubagentStart
            // hook writes IDENTITY (agent_id, agent_type, claude ids, the
            // resolved session), AGENT_REGISTER writes AUTHORITY (role,
            // methodology, workflow_phase). The join happens at READ time, so
            // ordering is not a constraint — a spawner that only learns agent
            // ids when a dynamic workflow reports back registers late and
            // still explains rows already written.
            //
            // NOT a reuse of agent_briefing, and the two are adjacent enough
            // to be confused: a briefing answers "what refs did this agent
            // get", a registration answers "who is agent X". The briefing's
            // UNIQUE(prompt_uuid, briefing_for_step) cannot hold four
            // same-typed explorers, which is the exact case this table is for.
            try db.execute(
                sql: """
                    CREATE TABLE agent_registration (
                        \(baseColumns),
                        -- Opaque, NEVER parsed. The shape varies by spawn kind
                        -- (a<hex> anonymous, a<name>-<hex> named) and reading
                        -- structure into it would make the registry wrong for
                        -- whichever shape ships next.
                        agent_id TEXT NOT NULL,
                        -- Locates the agent but cannot discriminate it: every
                        -- spawn shape shares the primary's conversation.
                        claude_session_id TEXT,
                        -- Claude Code's TURN id (payload field name: prompt_id).
                        -- NOT a gmcc prompt uuid — see the header note.
                        claude_turn_id TEXT,
                        session_uuid TEXT REFERENCES session(uuid) ON DELETE CASCADE,
                        prompt_uuid TEXT REFERENCES prompt(uuid),
                        -- Payload LABEL only, never authoritative: it is
                        -- overloaded by spawn shape — a plain subagent reports
                        -- its subagent_type, a bare workflow agent reports the
                        -- literal workflow-subagent, a named teammate reports
                        -- the NAME.
                        agent_type TEXT,
                        -- SPAWNER-authoritative, all three: no spawn shape
                        -- delivers role and methodology, and four identical
                        -- personas differ by agent_id alone. For a bare workflow
                        -- agent the role exists nowhere but the spawning script.
                        role TEXT,
                        methodology TEXT,
                        workflow_phase TEXT
                    );

                    -- UNIQUE on agent_id ALONE: the spawner holds exactly one
                    -- identifier (the Agent tool hands agent_id back) and cannot
                    -- see Claude Code's session_id from a shell, so any wider key
                    -- would put the authority write out of reach of its writer.
                    CREATE UNIQUE INDEX idx_agent_registration_agent_id
                        ON agent_registration(agent_id);
                    CREATE INDEX idx_agent_registration_prompt_fk
                        ON agent_registration(prompt_uuid);
                    """)

            // ---- file_change: the payload capture set, one typed column per
            // field rather than a blob, so every axis is queryable. agent_id
            // already exists and stays the single agent-id concept on this
            // table — the hook stamps it from the payload; agent_type here is
            // the payload's overloaded label alongside it.
            try db.execute(
                sql: """
                    ALTER TABLE file_change ADD COLUMN claude_session_id TEXT;
                    ALTER TABLE file_change ADD COLUMN claude_turn_id TEXT;
                    ALTER TABLE file_change ADD COLUMN tool_use_id TEXT;
                    ALTER TABLE file_change ADD COLUMN tool_name TEXT;
                    ALTER TABLE file_change ADD COLUMN agent_type TEXT;
                    ALTER TABLE file_change ADD COLUMN permission_mode TEXT;
                    ALTER TABLE file_change ADD COLUMN duration_ms INTEGER;
                    ALTER TABLE file_change ADD COLUMN transcript_path TEXT;
                    -- The authoritative link from a change to the identity that
                    -- made it. NULLABLE IS FORCED, not a softening: the primary
                    -- carries no agent_id at all — that ABSENCE is the
                    -- primary/subagent discriminator — so a primary write has
                    -- nothing to point at and NOT NULL would make the primary
                    -- unrecordable. NULL for primary writes, non-NULL for every
                    -- agent write.
                    ALTER TABLE file_change ADD COLUMN agent_registration_uuid TEXT
                        REFERENCES agent_registration(uuid);

                    -- Idempotency, keyed on the PAIR. A bare UNIQUE(tool_use_id)
                    -- would make Bash capture impossible: one `sed -i a b c` is
                    -- one tool_use_id and three file_change rows. The unit is
                    -- (tool call, file), which degenerates to one row per call
                    -- for Edit/Write/NotebookEdit. Partial so the column stays
                    -- free for every row that has no tool call behind it.
                    CREATE UNIQUE INDEX idx_file_change_tool_use
                        ON file_change(tool_use_id, session_file_uuid)
                        WHERE tool_use_id IS NOT NULL;

                    CREATE INDEX idx_file_change_claude_session_id
                        ON file_change(claude_session_id);
                    CREATE INDEX idx_file_change_agent_id
                        ON file_change(agent_id);
                    CREATE INDEX idx_file_change_agent_registration_fk
                        ON file_change(agent_registration_uuid);
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [26, Store.isoNow()]
            )
        }
    }
}
