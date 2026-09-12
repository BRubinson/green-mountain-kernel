---
name: gm_screenshot_session_domain_diagram_state
description: Read the current session's domain diagram out of the db and report its state — elements, geometry, dope bindings, revision.
argument-hint: [diagram-code] [--prompt]
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Read the Session Domain Diagram State

Pull the session's diagram tree from the db and describe what it holds. The
db is the canvas of record: GMVibes renders the same tree live, so anything
reported here is exactly what a viewer sees.

Two things to know before using it:

- **Tiers never union.** A diagram hangs off exactly one owner — session,
  prompt, instance or project — and a list or get names that owner. Asking
  for the session's diagrams will not surface a prompt-tier one.
- **Dope bindings resolve at READ time.** DIAGRAM_GET returns each
  `dope_entity` / `dope_scope_persistence_layer` element together with the
  dope node it currently binds to. A binding that resolves to nothing is a
  ghost — a legal state, not a failure, and usually means the dope tree moved
  under a diagram that was generated earlier.

## Steps

1. **Boot check.** If `$GMCC_BOOTED` is not set, stop with
   `[GMB] ERROR: GMCC not booted` (run /gmcc_boot for diagnostics).

2. **Resolve context.** `gmcc_hook context ensure` returns project_uuid,
   instance_uuid and session_uuid. If the user passed `--prompt`, also
   resolve the active prompt uuid (or ask which prompt).

3. **Pick the diagram.** With an argument, use it as the `code`. Otherwise
   enumerate:
   ```bash
   gmcc_hook call DIAGRAM_LIST --json '{"session_uuid":"<U>"}'
   ```
   (`{"prompt_uuid":"<P>"}` in prompt mode.) Zero rows ⇒ report that no
   diagram exists yet and suggest `/gm_diagram_from_dope` to generate one, or
   `gmcc_hook call DIAGRAM_INIT --json '{"session_uuid":"<U>","code":"<code>","name":"<name>"}'`
   for an empty canvas. Exactly one ⇒ use it. Several ⇒ take the first by
   code order and mention the others.

4. **Read the tree.**
   ```bash
   gmcc_hook call DIAGRAM_GET --json '{"diagram_uuid":"<D>"}'
   ```
   (or `{"session_uuid":"<U>","code":"<C>"}` when you only hold the code).

5. **Report.** The diagram's code, name, revision, element count by kind, the
   per-domain grouping, and any ghost bindings by name. Keep it to the shape
   of the picture — what is on the canvas and how it is arranged — not a
   dump of every coordinate.

The rendered canvas itself lives in GMVibes, which follows the same diagram
off the daemon event stream; point the user there when they want to look at
it. Never edit the repo's root `.gitignore`, and never stop the daemon.
