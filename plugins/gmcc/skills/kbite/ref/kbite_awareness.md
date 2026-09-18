# KBite Awareness Reference

<!-- Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file when working with kbites. -->

## KBite Loading Protocol

The KBite system provides persistent, indexed knowledge. Digested text,
keywords, and search live in the daemon db (read with the `kbite_search` /
`kbite_file_get` pen tools); the filesystem keeps each kbite's identity
(`{kbite_root}/{name}/KBITE_PURPOSE.md`) and raw-source archive
(`{kbite_digested_root}/{name}/`) — both roots under `$GM_FS_ROOT`
(`kbites/` and `kbites/digested/`).

KBites are **inherited, not trigger-matched**. The kbites relevant to the
current work are seeded down the hierarchy — project → instance → session →
prompt — into the db's active-kbite registries at row-create time. There is
no per-prompt keyword scan and no automatic activation.

To use kbite knowledge:

1. **Read the registry**: the active kbites are the `kbite_codes` on
   `cde_load_prompt`. A per-scope listing (project, instance, session)
   has no pen tool.
2. **Load on demand**: for a registered kbite, read
   `{kbite_root}/{name}/KBITE_PURPOSE.md`, then query the db:
   `kbite_search` returns ranked file stubs with their briefs across kbites
   — read the briefs, then pull the ones that matter with `kbite_file_get`
   (full file content — the targeted load). A kbite's whole roster in one
   read has no pen tool; search for what you need instead.
3. **Explicit add only**: a kbite joins a registry only when the user
   explicitly asks, and the add has no pen tool — report the request
   rather than performing it. Never add one on your own initiative.
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

Full kbite system documentation is in `$GM_PLUGIN_ROOT/skills/gmcc_kbite/SKILL.md`
