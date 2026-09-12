---
name: gm_art
description: "Interactive co-diagramming: Claude and GMVibes edit the SAME canvas live"
argument-hint: "[diagram_code | new <code> <name>] [instruction]"
disable-model-invocation: false
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# /gm_art [diagram_code] [instruction]

Starts an interactive diagramming session on ONE shared canvas: you edit it
db-natively over the daemon socket, GMVibes reflects every write live off the
daemon event stream, and the human draws in GMVibes while you read their
strokes back. Pure choreography — every primitive already exists; this
command is the loop discipline.

GMVibes is the eye in this loop. It holds the rendered canvas; you hold the
tree. Never describe what the picture looks like — describe what the tree
says, and let the human tell you how it reads.

## The substrate (nothing here is new machinery)

- WRITE: `gmcc_hook call DIAGRAM_BATCH_APPLY --json-file P`, with the payload
  `{"diagram_uuid":"U","expected_revision":N,"mutations":[...]}` — one
  transaction, one revision bump, one durable DIAGRAM_CHANGE event.
  `expected_revision` is the whole-diagram CAS: on VERSION_CONFLICT, re-get,
  rebase your mutations, retry ONCE. Use `--json-file` rather than `--json`
  for anything but a trivial batch; shell argument limits sit far below the
  daemon's content caps.
- WATCH: `gmcc_hook call EVENT_LIST --json '{"kind":"DIAGRAM_CHANGE","subject_uuid":"U","since_id":N}'`.
  Durable and replayable — no subscription needed; poll between your own
  turns.
- READ BACK: `gmcc_hook call DIAGRAM_GET --json '{"diagram_uuid":"U"}'` for
  the tree, including read-time dope binding resolutions.

## Echo suppression (the one stated rule)

Every batch-apply response returns the post-write `revision`. Keep a
per-diagram watermark of YOUR latest returned revision. When polling
events, IGNORE any DIAGRAM_CHANGE for this diagram whose `revision` is
<= your watermark — that is your own write echoing back. A HIGHER
revision is the human's edit: re-run DIAGRAM_GET BEFORE your next write,
then rebase onto the new revision. Never diff by author — there is no actor
column, by design.

## Flow

1. **Pick the canvas.** Resolve the current context first —
   `gmcc_hook context ensure` returns project_uuid, instance_uuid and
   session_uuid. No argument →
   `gmcc_hook call DIAGRAM_SEARCH --json '{"project_uuid":"P","limit":20}'`
   (browse mode) and AskUserQuestion over the recent diagrams (+ "create
   new"). `new <code> <name>` →
   `gmcc_hook call DIAGRAM_INIT --json '{"session_uuid":"U","code":"<code>","name":"<name>"}'`.
   A bare code →
   `gmcc_hook call DIAGRAM_GET --json '{"session_uuid":"U","code":"<code>"}'`;
   on SUMMARY_ABSENT offer to init.
2. **Baseline.** DIAGRAM_GET for the tree + revision; note the current event
   cursor (`gmcc_hook status` → `last_event_id`). Set watermark = revision.
   Ask the human what they see on the GMVibes canvas — that is your only
   check on how the tree actually reads.
3. **Announce the loop** to the user: they draw in GMVibes (the canvas
   updates live for them on your every write); they talk to you here.
4. **Each of your turns:**
   a. Poll EVENT_LIST with `since_id` = your cursor → advance the cursor;
      apply the echo rule. If the human drew, re-get before planning.
   b. Make your edit as ONE batch (mutations file in the scratchpad;
      `expected_revision` = latest known). Update the watermark from the
      response.
   c. Re-get and check the geometry you just wrote — centers, sizes,
      connector endpoints — then ask the human how it reads. Iterate with
      `element_update` mutations until it reads well.
5. **On "done":** a final DIAGRAM_GET, and a short written summary of what
   the canvas now holds.

## Element vocabulary (mutation `fields.payload`, kind tags)

Mutations encode as `{"kind": "element_add|element_update|element_delete|diagram_update", "fields": {...}}`
and apply strictly in array order inside one transaction.

`uml_node` (node_kind: db_cylinder|rounded_rect|triangle|rhombus|diamond|
circle; width/height; markdown body), `connector` (routing_kind:
orthogonal_step|straight|curved; head_kind/tail_kind: none|arrow|dot|
open_arrow|diamond|circle|cross; line_style solid|dashed; label),
`drawing_stroke` (freehand; vertices carry pressure), `drawing_text`
(block markdown box), `drawing_layer`, `dope_scope_persistence_layer` +
`dope_entity` (code bindings; ghosts legal). Connectors are children of
the element they LEAVE and target a peer of their parent — in one batch
use `parent_client_ref`/`target_client_ref`.

## Pre-flight

If `$GMCC_BOOTED` is unset:

```
[GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
```

If the daemon is unreachable: `bash
$GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gmcc_hook context ensure`
(the next client call brings the daemon up), retry.

ARGUMENTS: $ARGUMENTS
