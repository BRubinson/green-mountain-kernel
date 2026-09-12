---
name: gm_diagram_from_dope
description: Generate (or regenerate) the session's domain diagram from its dope model onto a db-persisted canvas.
argument-hint: [diagram-code] [--prompt]
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Diagram From Dope

Turn the session's dope model into a db-persisted diagram canvas — one
`dope_scope_persistence_layer` container, one `dope_entity` card per entity,
grouped in per-domain columns (FK edges are drawn by the resolver at read
time) — in ONE atomic batch. GMVibes is where the result is looked at; the
canvas updates live for anyone holding it open.

## Steps

1. **Boot check.** If `$GMCC_BOOTED` is not set, stop with
   `[GMB] ERROR: GMCC not booted` (run /gmcc_boot for diagnostics).

2. **Resolve context.** `gmcc_hook context ensure` returns project_uuid,
   instance_uuid and session_uuid. If the user passed `--prompt`, also
   resolve the active prompt uuid (or ask which prompt) — prompt mode scopes
   BOTH the dope fetch and the diagram tier to that prompt.

3. **Fetch the dope tree.** `mcp__plugin_gmcc_pen__dope_get` with the session
   (add `prompt_uuid` in prompt mode, and `code` to pick one scope). No scope
   ⇒ there is no dope model to draw: offer to seed one from the repo's
   `.gmcc` tree (`gmcc_hook call DOPE_INGEST --json '{"scope_uuid":"S"}'`) or
   to create one (`DOPE_INIT`). A tree whose domains are all entity-less ⇒
   there is nothing to draw; say so and stop.

4. **Open the canvas (idempotent).**
   ```bash
   gmcc_hook call DIAGRAM_INIT --json '{
     "session_uuid": "<U>", "code": "<C>", "name": "<name>",
     "dope_scope_code": "<scope code>"
   }'
   ```
   Default diagram code is `{scope_code}_domain_model`. Pass `prompt_uuid`
   instead of `session_uuid` in prompt mode — tiers never union. The response
   carries the diagram uuid and its current `revision`.

5. **Regenerate in ONE batch.** Read the existing tree
   (`gmcc_hook call DIAGRAM_GET --json '{"diagram_uuid":"<D>"}'`), then write
   a single `DIAGRAM_BATCH_APPLY` payload to a scratchpad file and send it
   with `--json-file`:
   - one `element_delete` per existing TOP-LEVEL element (the delete cascades
     its subtree),
   - one `element_add` for the `dope_scope_persistence_layer` container,
   - one `element_add` per entity as a `dope_entity` card, parented onto the
     container via `parent_client_ref`, laid out in per-domain columns with
     even gutters.

   Carry `expected_revision` from step 4 — the whole-diagram CAS. On
   VERSION_CONFLICT, re-get, rebase the batch onto the new revision, retry
   ONCE. The batch is all-or-nothing: one revision bump, one DIAGRAM_CHANGE
   event.

6. **Report.** Print the diagram code, its new revision, and the counts
   (domains, entities, cards written). Dangling dope bindings are a legal
   state and resolve as ghosts at read time — after a regenerate they usually
   mean the dope tree changed mid-run; mention them.

## Rules

- The dope tree is fetched from the DB, never parsed from the on-disk
  `.gmcc/` dope files — ingest first if the files are ahead.
- Hand-placed elements do not survive a regenerate: the batch deletes ALL
  top-level elements. Say so when regenerating a `revision > 0` diagram
  the user may have edited in GMVibes.
- Never edit the repo's root `.gitignore`, and never stop the daemon.
