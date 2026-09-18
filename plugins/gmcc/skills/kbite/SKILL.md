---
name: kbite
description: Pre-indexed external knowledge
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__kbite_search, mcp__plugin_gmcc_cde__kbite_open_maw, mcp__plugin_gmcc_cde__kbite_digest
---

## KBite — Pre-Indexed External Knowledge

A kbite is a persistent body of analyzed reference material — docs, API references, whole example sources — digested into the db and reached by ranked search. Kbites are DB-CANONICAL; the filesystem holds only identity, the raw-source archive, and in-progress maws.

### Access Rule — Search First
1. `kbite_search "<topic>"` — returns ranked file stubs with briefs
2. Read the briefs to decide relevance
3. `kbite_file_get <uuid>` — fetch the top files only
4. No full-tree dumps. There is a hard cap on files pulled per task.
5. A result may come back oversized or withheld — that is an answer, not an error. Narrow the subject.
6. When you use kbite knowledge, cite the source.

### Ingestion
1. Open a maw for the kbite — creates the skeleton and KBITE_PURPOSE
2. Collect raw sources into `{axis1}/{axis2}/{resource}/`, fetching web pages where needed
3. Chew — analyze each resource into chewed analysis files
4. Digest — parse the chewed files into db rows, archive the sources, drop the maw

### Lifecycle
- Relate — cross-reference two kbites
- Export — portable zip carrying db rows and sources
- Import — never auto-registers
- Delete — cascades, and has NO pen door. It is an operator act; report the request rather than performing it.

### Registry
Active kbites are listed on the prompt or session (`kbite_codes` on `cde_load_prompt`). Adding one to a registry has no pen door either: on an explicit request, report it; never auto-add. Path roots resolve under `$GM_FS_ROOT` — never hardcode them.

### Reference
Detail lives beside this file rather than in it — read it only when it names your situation:

- `ref/kbite_awareness.md` — What kbites are, how they are searched, and when to reach for one instead of reading files.
