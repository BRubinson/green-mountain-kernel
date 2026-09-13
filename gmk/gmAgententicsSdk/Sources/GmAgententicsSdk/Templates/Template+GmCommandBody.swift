// The command bodies, compiled from the markdown each command shipped as.

import Foundation

/// Prepended to EVERY command body.
///
/// Commands are the one surface where the GMB identity is not already loaded:
/// an agent gets it baked into its profile instruction, but a command runs in
/// whatever context the session already has. Loading the skill first is what
/// makes the rest of the body mean what it says.
let GM_COMMAND_SKILL_PRELUDE = """
    **Load the `gmcc` skill before anything else.** It carries the GMB identity and
    the GM-CDE rules every step below assumes. Do not begin the work until it is in
    context.
    """

let GM_COMMAND_ASK_BODY = """
    Survey what the kernel can do for this request, and report it WITHOUT choosing.

    **Steps:**
        1. Read the ask. Name what is actually being requested, in one line, before looking at anything.
        2. Survey the surface that could serve it — the tool families (`cde_*`, `rpir_*`, `dope_*`, `kbite_*`), the shell, the wire verbs behind `gm_hook call`, and the scoped commands that already exist.
        3. Lay out every option you found. For each: what it does, what it costs, and what it would need from the Endotherm.
        4. State what you could NOT determine, and what would settle it.
        5. Stop there.

    **Contract:**
        1. NO RECOMMENDATION. You are surveying, not deciding. Ranking the options is the Endotherm's move, not yours.
        2. An option you dislike still gets stated plainly and fairly. Suppressing it is deciding.
        3. Best effort over completeness theatre: say what you checked and what you did not.
        4. If exactly one option exists, say so — that is a finding, not a recommendation.
        5. Do the work only if the Endotherm asks for it after reading the survey.
    """

let GM_COMMAND_INIT_BODY = """
    Initialize GM-CDE at the USER level. Once per machine.

    **Steps:**
        1. Pre-flight — if the root already exists and `--force` was not passed, report what is present and stop.
        2. Create the filesystem root at `$GM_FS_ROOT` with its directory skeleton and README.
        3. Install the kernel binaries and bring the daemon up; verify it answers.
        4. Put `gm_hook` on the terminal PATH by PRINTING the line to add. Never write the shell profile yourself.
        5. Persist the GMFS permission grant in `~/.claude/settings.json` — `Read`/`Edit` under the root plus the additional directory.
        6. Verify: daemon reachable, env and db agreeing on the root, grant present. Report each.

    **Contract:**
        1. Per-project, per-instance and per-session state is auto-ensured by the SessionStart hook. Do NOT create it here.
        2. GMCC never writes the user's shell profile. Remediation lines are printed, not applied.
        3. The database is append-only history. Initialization never wipes an existing one.
    """

let GM_COMMAND_CLEANUP_BODY = """
    Audit the GM-CDE install and resolve each finding WITH the Endotherm.

    **Scopes** — `session`, `environment`, `system`, or `all` (default):
        1. `session` — this session's artifact tree on disk against its db rows.
        2. `environment` — kernel/db health, db-vs-disk drift, archive hygiene, kbite provenance.
        3. `system` — host wiring outside any one repo: binary reachability, env-vs-db root agreement, permission grants, stray shell env blocks.

    **Steps:**
        1. Pre-flight the scope. Confirm the kernel answers before auditing anything that reads it.
        2. Collect findings per scope. Report counts before details.
        3. Put each finding to the Endotherm with the fix you would apply, and apply only what is accepted.
        4. Re-verify what you changed.

    **Contract:**
        1. `--dry-run` reports and changes NOTHING.
        2. The db is append-only. A wrong row is corrected by writing again, never by deletion.
        3. Take `gm_hook call BACKUP --json '{}'` before anything that touches the database.
    """

let GM_COMMAND_CRUNCH_OPEN_MAW_BODY = """
    Open a maw for collecting kbite resources.

    **Steps:**
        1. Check for an existing maw for this kbite. If one is open, report it and stop rather than clobbering it.
        2. Check for a parent KBITE_PURPOSE — a new kbite needs one, an existing kbite already has one.
        3. Create the maw skeleton: the maw root, its crunchables directory, and MAW_INDEX.
        4. For a NEW kbite, write KBITE_PURPOSE.md covering why it exists, its scope, target use cases, related kbites and success criteria.
        5. Report the maw path and what to drop into it.

    **Contract:**
        1. One open maw per kbite. A second is a collision, not a convenience.
        2. Raw sources go in untouched — chewing happens in `/gm_crunch_chew`, not here.
    """

let GM_COMMAND_CRUNCH_CHEW_BODY = """
    Process crunchable resources in a maw into chewed analysis files.

    **Steps:**
        1. Index untracked crunchables — walk the maw for directories that qualify and add what MAW_INDEX does not already carry.
        2. Identify which are pending.
        3. Mark them in-progress in MAW_INDEX before spawning anything.
        4. Spawn one chew agent per pending crunchable. Each reads its own source and nothing else.
        5. Write the chewed files as each agent returns.
        6. Update MAW_INDEX per completion, not in one batch at the end.
        7. Final index pass, then report what was chewed and what remains.

    **Contract:**
        1. Record as you go. A crash between step 4 and step 7 must leave MAW_INDEX honest about what finished.
        2. Chewing never edits the raw source. It writes alongside it.
    """

let GM_COMMAND_CRUNCH_DIGEST_BODY = """
    Digest chewed maw resources into the kernel db and archive the raw sources.

    **Steps:**
        1. Pre-flight: the maw exists, it has chewed resources, and KBITE_PURPOSE is present. Any missing one stops the run.
        2. Review the chewed resources before writing anything.
        3. Digest into the db.
        4. Archive the raw sources.
        5. Delete the open maw.
        6. Verify the rows landed and report per-file.

    **Contract:**
        1. Digest is the one step that writes the record. Verify before deleting the maw — step 5 is not reversible from here.
        2. Take `gm_hook call BACKUP --json '{}'` first.
    """

let GM_COMMAND_KBITE_EXPORT_BODY = """
    Export one digested kbite to a portable `gmcc_kbite` zip.

    **Steps:**
        1. Pre-flight the kbite code. An unknown code stops the run — report the known ones.
        2. Serialize the db rows for that kbite.
        3. Stage the files alongside the serialized rows.
        4. Zip the staged directory.
        5. Report the zip path and what it carries.

    **Contract:**
        1. Export READS. It never mutates the kbite it is exporting.
    """

let GM_COMMAND_KBITE_IMPORT_BODY = """
    Import a `gmcc_kbite` zip into this machine's kernel db.

    **Steps:**
        1. Pre-flight the zip path. A missing file stops the run.
        2. Unpack to a staging directory.
        3. Load the db rows.
        4. Restore the files.
        5. Report what was imported.

    **Contract:**
        1. A kbite that already exists is a decision, not an error — put the overwrite to the Endotherm before taking it.
        2. Take `gm_hook call BACKUP --json '{}'` before loading rows.
    """

let GM_COMMAND_KBITE_RELATE_BODY = """
    Define a relationship between two kbites for cross-referencing.

    **Steps:**
        1. Resolve both kbites. A missing source or target stops the run.
        2. Determine the relationship type from the argument.
        3. Read the existing KBITE_RELATIONSHIPS.md for the source.
        4. Update the source's OUTGOING relationships.
        5. Update the target's INCOMING relationships.
        6. Update the Related KBites section of both KBITE_PURPOSE files.
        7. Report both sides.

    **Contract:**
        1. A relationship is written on BOTH sides or neither. A half-written edge is worse than no edge.
    """
