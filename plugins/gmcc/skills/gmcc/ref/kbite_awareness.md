# KBite Awareness Reference

<!-- Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file when working with kbites. -->

## KBite Loading Protocol

The KBite system provides persistent, indexed knowledge. Digested text,
keywords, and search live in the daemon db (read with the `kbite_search` /
`kbite_file_get` pen tools); the filesystem keeps each kbite's identity
(`{kbite_root}/{name}/KBITE_PURPOSE.md`) and raw-source archive
(`{kbite_digested_root}/{name}/`) — both roots from
`gmcc_hook paths --json`.

KBites are **inherited, not trigger-matched**. The kbites relevant to the
current work are seeded down the hierarchy — project → instance → session →
prompt — into the db's active-kbite registries at row-create time. There is
no per-prompt keyword scan and no automatic activation.

To use kbite knowledge:

1. **Read the registry**: the active kbites are the `kbite_codes` on
   `prompt_get` (and on `SESSION_GET` for the session as a whole). For a
   scoped listing:

   ```bash
   gmcc_hook call KBITE_LIST --json \
     '{"scope":"project|instance|session|prompt","owner_uuid":"U"}'
   # add "all": true for every kbite row in the db
   ```
2. **Load on demand**: for a registered kbite, read
   `{kbite_root}/{name}/KBITE_PURPOSE.md`, then query the db:
   `kbite_search` returns ranked file stubs with their briefs across kbites
   — read the briefs, then pull the ones that matter with `kbite_file_get`
   (full file content — the targeted load). For a kbite's whole roster of
   resources, file stubs and keywords:
   `gmcc_hook call KBITE_GET --json '{"code":"{name}"}'`.
3. **Explicit add only**: add a kbite to a registry only when the user
   explicitly asks for it:

   ```bash
   gmcc_hook call KBITE_ADD --json '{"scope":"session","owner_uuid":"U","code":"C"}'
   ```

   Never add one on your own initiative.
4. **Cite sources**: when using kbite knowledge, cite the source:
   - "Per the swift_code_edit kbite..."
   - "According to kbite knowledge..."

## When to Suggest New KBites

GMB should suggest creating a kbite when:
- User repeatedly references the same external documentation
- A new SDK/library/tool is being integrated
- Complex domain knowledge needs persistent reference
- Current context would benefit from pre-analyzed material

Suggest: "This looks like a good candidate for a kbite. Run `/gm_crunch_open_maw {suggested_name}` to start collecting resources."

## KBite System Reference

Full kbite system documentation is in `$GMCC_PLUGIN_ROOT/skills/gmcc_kbite/SKILL.md`
