import Foundation

let GM_CONCEPT_KBITE = """
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
    - `gm_hook call KBITE_DELETE --json '{"code":"<code>"}'` — deletes and cascades; back up first

    ### Registry
    Active kbites are listed on the prompt or session. Add one explicitly only when asked; never auto-add. Path roots come from `gm_hook paths --json` — never hardcode them.
    """
