//
//  Prompts.swift
//  gmAgententicsSdk
//
//  Created by Bryce Rubinson on 9/12/26.
//

import Foundation
import FoundationModels
import GmDaemonSdk

// The TURN half of the template surface: what GMCC actually says to a model at
// invocation time, as FoundationModels `Prompt` values. The standing behavioral
// contracts are next door in `Instructions.swift`.
//
// THE SPLIT IS NOT COSMETIC, and getting it backwards is the expensive mistake
// this file exists to prevent. Apple's own guidance: a model is trained to obey
// INSTRUCTIONS over any command arriving in a PROMPT, and untrusted content must
// never be placed in instructions. That maps cleanly onto GMCC's existing
// division — a persona definition is trusted, authored, and fixed for the run;
// a spawn prompt carries uuids, a one-line target, and user-derived topic text.
// So personas are `Instructions`, invocations are `Prompt`, and no builder below
// ever promotes a caller-supplied string into an instruction block.
//
// THREE KINDS OF PROMPT LIVE HERE, and they come from three different places:
//
//   1. VARIANT CONTRACTS (`Text.bot` / `.rpi` / `.team` / `.task`) — copied
//      verbatim from `plugins/gmcc/commands/*.md`. These are the templates the
//      PRIMARY runs under, and they are what makes /gm_bot different from
//      /gm_bot_team. Same verbatim rule and the same reason as Instructions.swift:
//      re-sync by re-copying.
//   2. PHASE TEXT (`phasePrompt(variant:phase:)`) — NOT copied. It is read live
//      from `WorkflowSpec.instructions(variant:phase:)` in gmDaemonSdk, because
//      that text is already compiled into the binary, already drift-guarded by
//      WorkflowSpecTests, and already the thing `bot_next` serves. A second copy
//      here would be a second source of truth for the one part of the machine
//      that changes most often. This is the payoff of the gmDaemonSdk dependency
//      edge, not merely a use of it.
//   3. SPAWN PROMPTS (`spawn(...)` and friends) — BUILT, not copied, because
//      they are the only templates with holes in them. Their shape is fixed by
//      the variant contracts: "Spawn prompts carry ONLY the methodology, the
//      summary uuid where the def asks for one, and the one-line target — plus
//      the explicit `prompt_uuid` pull line. Do not paste briefings or dope
//      dumps into spawn prompts." The builders below are that rule expressed as
//      a signature, which is why none of them takes a free-form context blob.
//
// NOTHING HERE IS WIRED, same as the rest of the package: these values are
// staged for a caller that does not exist yet. No session is created, no model
// is selected, nothing is sent.

/// The invocation-time prompt templates.
public enum GmAgentPrompts {

    /// The primary's per-variant operating contract, verbatim from
    /// `plugins/gmcc/commands/`.
    ///
    /// No availability annotation, for the reason `GmAgentInstructions.Text`
    /// gives: a `String` needs none, and everything that merely wants to READ
    /// or diff a contract should not pay a platform floor for the privilege.
    ///
    /// Each block is the command file's BODY. The YAML frontmatter is dropped —
    /// `argument-hint`, `disable-model-invocation` and `allowed-tools`
    /// configure Claude Code's command dispatcher and mean nothing to a model.
    public enum Text {

        /// `commands/gm_bot.md` — variant `bot`: every phase in primary
        /// context, the haiku doper briefing the only spawn.
        public static let bot = #"""
        # GM-CDE Bot (variant: bot)

        You are executing the **bot** variant: every phase in primary context, no
        subagents except the `gmcc:doper` briefing pass. The lifecycle lives in the
        daemon — `mcp__plugin_gmcc_pen__bot_next` tells you the current phase, its
        instructions, and what blocks the next one. Follow it; this file carries only the variant
        contract. Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

        ## Pre-Flight

        If `$GM_BOOTED` is not set:

        ```
        [GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
        ```

        Exit without proceeding.

        Then confirm `mcp__plugin_gmcc_pen__*` is in your own tool list. This variant
        pens its rows from primary context and spawns the doper, so an unserved pen
        means nothing this run produces can be recorded. Absent pen = report it and
        exit; the session must be restarted, not worked around. `claude mcp list`
        reporting the server healthy does NOT settle it — that check spawns a fresh
        probe process, while what matters is whether THIS session registered the tools.

        ## Arguments

        ONE CALL STARTS A RUN. `mcp__plugin_gmcc_pen__prompt_init` takes what the user
        typed and does the rest: it resolves session and project from the working
        directory and git branch, matches the selector, enters the workflow machine, and
        returns the uuid bundle, the derived phase, that phase's instructions, the NEXT
        phase's expected agents, the gate blockers, and the briefing's state. There is
        nothing to read afterwards to know what to do — no ref doc, no command file, no
        source file.

        - **Numeric seq, code, name, or a unique fragment of one** → resume:
          `prompt_init(selector: "10", variant: "bot")`. The reply's
          `resolution.created` says whether this is a NEW prompt or a RESUMED one, and
          an ambiguous selector comes back with `candidates` and touches nothing — pick
          one and call again rather than guessing.
        - **Slug name + content** → create, by passing the same call the content
          (STAY TRUE: the whole passed prompt goes to `detail` verbatim; goal and
          backstory are never authored):
          `prompt_init(selector: "{name}", variant: "bot", create: true, name: "{name}", detail: "<the user's prompt, verbatim>")`.
          Creation requires `create`, `name` AND `detail` together, so a mistyped
          selector can never silently become a new prompt. Then
          `mkdir -p $GM_FS_ROOT/<gmfs_relative_storage_path>/memory`, taking the
          path verbatim from the response.
        - **No args** → AskUserQuestion for the prompt content.

        If the reply carries `warnings`, read them before spawning anything: a session
        with no `claude_session_binding` row records no file changes at all, and the run
        will look like it worked.

        ## Variant contract (bot)

        - Haiku doper briefing, then YOU run exploration in context: open your
          `general` summary (`mcp__plugin_gmcc_pen__bot_summary --agent-type
          general`), pen the finding rows yourself, complete it. The pen is loaded
          for you too — running the phase in the primary's own context is no reason
          to record it any other way. Every read and every write this variant needs
          is a pen tool, the primary's four included: you are the one reader here,
          so the rank, the decide, the seals and the status moves are yours to make.
        - Clarification: you run the merged clarifier pass in context — rank
          prompt-wide from your own self-ratings, open + complete the `synthesis`
          summary, author the questions/notes, seal, run the user conversation
          (AskUserQuestion mirroring the option rows), answer rows, finalize. NO
          care package — the clarified picture stays in your context.
        - Architecture: design in context; persistence rows first (change kinds +
          dope refs); propose → user sign-off with the full persistence delta
          table → approve. No status move: the prompt was stamped `initiated` when
          its briefing opened and next moves to `done`.
        - Implement in context (persistence first; capture is the PostToolUse hook
          alone), review in context against your general review summary, complete
          with a verdict, run the fix loop, set-status done.

        Every step's exact commands come from `mcp__plugin_gmcc_pen__bot_next` —
        trust the machine, never skip its gate blockers.
        """#

        /// `commands/gm_bot_rpi.md` — variant `rpi`: one general-persona
        /// subagent per phase, plus the care package.
        public static let rpi = #"""
        # GM-CDE Bot RPI (variant: rpi)

        You are executing the **rpi** variant: ONE general-persona subagent per
        phase (it adopts all four methodology lenses at once — summary/agent type
        `general`), plus up to 2 implementation subagents. The lifecycle lives in
        the daemon — `mcp__plugin_gmcc_pen__bot_next` serves each phase's
        instructions and gates.
        Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

        ## Pre-Flight

        If `$GM_BOOTED` is not set:

        ```
        [GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
        ```

        Exit without proceeding.

        Then confirm `mcp__plugin_gmcc_pen__*` is in your own tool list. Every subagent
        this variant spawns records through the pen and nothing else, so an unserved pen
        means no spawn can write. Absent pen = report it and exit; the session must be
        restarted, not worked around. `claude mcp list` reporting the server healthy does
        NOT settle it — that check spawns a fresh probe process, while what matters is
        whether THIS session registered the tools.

        ## Arguments

        Same as /gm_bot (resume by seq / create by slug — STAY TRUE), with
        `--command /gm_bot_rpi` at create and `--variant rpi` at start/resume.

        ## Variant contract (rpi)

        - Haiku doper briefing, then spawn ONE `gmcc:code-explorer` with
          `Methodology: general` — it opens its own summary via the pen tools,
          writes its rows, completes it. No 4-spawn batches; findings stay unranked
          at the end of explore.
        - Clarification: spawn ONE `gmcc:clarifier` for the merged pass — it ranks
          prompt-wide, opens and seals the `synthesis` summary, and pens the
          question/note suite. You seal the suite, run the user conversation,
          answer, then build the CARE PACKAGE (package-open → package-add refs →
          package-complete with the clarified intent), finalize, set-status
          architecting.
        - Architecture: ONE `gmcc:code-architect` (general, solo mode —
          proposal-only); you persist the rows (persistence first), propose →
          sign-off (full persistence delta table) → approve → implementing.
        - Implement with up to 2 implementation subagents (persistence first;
          capture is the PostToolUse hook alone). Review: ONE `gmcc:code-quality-reviewer`
          (general); you complete with the verdict and run the fix loop; done.

        Spawn prompts carry ONLY: the methodology (`general`), the summary uuid
        where the def asks for one, and the one-line target. Do not paste briefings
        or dope dumps into a spawn prompt — agents pull their own context through
        the pen tools.
        """#

        /// `commands/gm_bot_team.md` — variant `team`: four methodology
        /// personas per fan-out phase, architecture optioning, one decide step.
        public static let team = #"""
        # GM-CDE Bot Team (variant: team)

        You are executing the **team** variant: methodology fan-outs
        (conservative / aggressive / pragmatic / alternative) run as persona subagents
        or inside dynamic workflows you author; the daemon machine
        (`mcp__plugin_gmcc_pen__bot_next`) serves every phase's instructions and its
        gate blockers. Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

        ## Pre-Flight

        If `$GM_BOOTED` is not set, or agent teams are unavailable
        (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), report the error and exit
        (fallback: /gm_bot_rpi).

        Then confirm the pen is actually served to this session: `mcp__plugin_gmcc_pen__*`
        must be in your own tool list. Every persona in this variant records through the
        pen and nothing else, so if the tools are absent no spawn can write — the fan-out
        burns four agents and lands nothing. Absent pen = report it and exit; the session
        must be restarted, not worked around. `claude mcp list` reporting the server
        healthy does NOT settle it: that check spawns a fresh probe process, while what
        matters is whether THIS session registered the tools.

        ## Arguments

        Same as /gm_bot (resume by seq / create by slug — STAY TRUE), with
        `--command /gm_bot_team` at create and `--variant team` at start/resume.

        ## Variant contract (team)

        - **Workflow-driven phases** — briefing + explore + clarify-open,
          implementation, and review-fix run as dynamic workflows you HAND-AUTHOR,
          guided by `mcp__plugin_gmcc_pen__bot_next` output. Script code is pure
          orchestration: it never touches the db directly — every read/write happens inside agent()
          subagents, through the MCP pen tools and nothing else. Capture is the
          PostToolUse hook alone — there is no gate-time backstop, so a write the
          hook cannot see is not recorded at all.
        - **Explore** — four `gmcc:code-explorer` personas, each opening its OWN
          summary (`bot_summary`, agent_type = its methodology) and completing it.
          Findings stay unranked; calibration is cross-agent and belongs to one
          reader.
        - **Clarify** — ONE `gmcc:clarifier` runs the merged pass: it reads every
          persona's findings, applies the ONE prompt-scoped calibrated rank batch,
          opens and seals the `synthesis` summary, and pens the question/note
          suite. YOU seal the suite, run the user conversation (AskUserQuestion
          mirroring the option rows) and the answers; then the care package
          (curated COPIES of ranked findings + dope/kbite refs + the
          clarified-intent blob), finalize, then open the architecture summary
          (ARCH_OPEN). No status move — the prompt is already `initiated`.
        - **Architecture optioning** — four `gmcc:code-architect` personas each pen
          their OWN option row (`arch_option_add`). You pick the winner with
          `mcp__plugin_gmcc_pen__arch_decide` (rationale recorded; siblings rejected; offer the
          losers' best features to the user), and ONLY the selected option expands
          into change rows — persistence first, change kinds + dope refs.
        - **Plan gate** — propose → user sign-off with the full persistence delta
          table → approve → implementing.
        - **Review** — four `gmcc:code-quality-reviewer` personas pen finding rows,
          each rating only its own; you run the ONE calibrated rank batch across all
          of them (`mcp__plugin_gmcc_pen__review_rank` — calibration is cross-agent
          and belongs to one reader) and complete with the verdict, clarify fix
          intent with the user, run review-fix (as a workflow when the fixes fan
          out), done.

        Spawn every persona by `subagent_type` — `gmcc:doper`, `gmcc:code-explorer`,
        `gmcc:clarifier`, `gmcc:code-architect`, `gmcc:code-quality-reviewer` — and pass
        NO spawn name. A name routes the spawn down the teammate path, where the agent
        definition never binds: the persona comes up with a general tool set instead of
        its own, holds no pen tools, and registers under the name rather than its type.
        Resume a running persona by the agent id its spawn returned.

        Spawn prompts carry ONLY the methodology, the summary uuid where the def asks
        for one, and the one-line target — plus the explicit `prompt_uuid` pull line
        (personas hold no activation claim). Do not paste briefings or dope dumps into
        spawn prompts. There is no tear-down step.

        ## Error handling

        Persona spawn failure → fall back to the rpi shape for that phase, say so.
        A persona that reports missing pen tools is a spawn that did not bind its
        definition — re-check the Pre-Flight pen line and the no-name rule; a write
        the pen cannot make is a write nothing records.
        Everything else (VERSION_CONFLICT, SUMMARY_ABSENT, daemon unreachable, dead
        doper): `bot_workflows.md`.
        """#

        /// `commands/gm_task.md` — the write-nothing variant.
        ///
        /// NOT A `BotVariant`, and the asymmetry is deliberate on the daemon's
        /// side, not an omission here: `task` has no workflow row because its
        /// contract is to author nothing, so `WorkflowSpec.phases(for:)` has
        /// nothing to walk. It is a template all the same — the primary runs
        /// under it — which is why it lives in this enum and not in
        /// `variantText(for:)` below.
        ///
        /// The `!` line under Pre-Flight is Claude Code's inline-bash syntax:
        /// the dispatcher runs it and substitutes the output before the model
        /// ever sees the text. It is kept verbatim rather than pre-expanded,
        /// because what is being recorded here is the TEMPLATE.
        public static let task = #"""
        # GM-CDE Task (Context-loaded, no ceremony)

        You are executing a task with full GMCC context loaded, but **without** the
        prompt-authoring ceremony of `/gm_bot`. You load context, you do the work,
        and you leave the prompt/report surface of the daemon db untouched — unless
        the user explicitly asks you to write something back.

        The contract that distinguishes this command from `/gm_bot`:

        > **Default behavior authors NOTHING in the daemon db or the gmfs.**
        > No prompt row, no clarify/arch/explore/review summaries, no artifact
        > registrations. Editing the user's *repository* files is the task and is
        > expected — and those Edit/Write changes are captured automatically by the
        > plugin's PostToolUse hook (unattributed when no prompt is active). That
        > capture is harness plumbing and needs nothing from you. The two sanctioned
        > exceptions: the optional doper briefing below, and an explicitly requested
        > retroactive write-back (final section).

        SessionStart injects the pen sheet. The pen tools are typed, so there are no
        flags to guess; `gm_hook verbs --json` lists every MessageType the daemon
        serves for the reads that have no pen tool.

        ---

        ## Pre-Flight

        **Boot Validation**: If `$GM_BOOTED` is not set, output:
        ```
        [GMB] ERROR: GMCC not booted

        GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
        To fix: Restart Claude Code from within a git repository.
        ```
        Exit without proceeding.

        Current session state (inlined at invocation — one shell, because the two
        list calls need the session uuid the first call returns):

        !`U=$(gm_hook context ensure | sed -n 's/.*"session_uuid" : "\(.*\)".*/\1/p'); echo "session_uuid=$U"; gm_hook call PROMPT_LIST --json "{\"session_uuid\":\"$U\",\"with_reports\":true}"; gm_hook call DOPE_LIST --json "{\"session_uuid\":\"$U\"}"`

        If that errored with "daemon unreachable", self-heal:
        `bash $GM_PLUGIN_ROOT/scripts/install_gm.sh`, then re-run it (the next
        client call brings the daemon back up).

        ---

        ## Phase 1: Deeper Context (read-only, on demand)

        The inlined state above covers the default scope: every prompt's
        clarification/architecture/exploration/review stubs, change summary, and dope
        scopes. Pull detail only where the task needs it:

        - `mcp__plugin_gmcc_pen__clarify_get` / `arch_get` / `explore_get` /
          `review_get` for full detail on the prompts that matter (each narrows —
          pass a rating window or an option/change uuid rather than pulling
          everything). `gm_hook call SEARCH --json '{"query":"<topic>","session_uuid":"<U>","limit":20}'`
          finds prior work across prompts — do not grep the gmfs for it.
          `gm_hook call ARTIFACT_LIST --json '{"prompt_uuid":"<P>"}'` shows files
          registered against a prompt.
        - **Dope on demand.** `mcp__plugin_gmcc_pen__dope_search` (FTS5, dot-path
          hits) then targeted `mcp__plugin_gmcc_pen__dope_get` with `code` — never
          full-tree dumps.
        - **KBites on demand.** If a task clearly benefits from a kbite:
          `mcp__plugin_gmcc_pen__kbite_search` for ranked stubs, read the briefs, then
          `mcp__plugin_gmcc_pen__kbite_file_get` for the content that matters
          (`gm_hook call KBITE_GET --json '{"code":"{name}"}'` for the overview;
          purpose file at `{kbite_root}/{name}/KBITE_PURPOSE.md`, kbite_root from
          `gm_hook paths --json`). Prefer kbites already active for the session. Do
          not block on an AskUserQuestion for kbite selection — only load what the
          task needs.

        ### Optional: session-owned briefing for meaty tasks

        For a substantial task that would benefit from real context assembly,
        delegate it to the doper instead of hand-searching (this is a sanctioned
        db write — `agent_briefing` rows are context plumbing, not work records).
        There is no prompt row, so the briefing is SESSION-owned:

        ```bash
        gm_hook call BRIEFING_OPEN --json '{"session_uuid":"{U}","briefing_for_step":"initial"}'
        ```

        The response carries the briefing uuid.

        ```
        Task tool:
          subagent_type: gmcc:doper
          prompt: |
            Owner session uuid: {U}
            Step: initial
            Topic: {one line — what this task is about}
        ```

        Gate on it BY UUID as the spawn's very next call:
        `mcp__plugin_gmcc_pen__briefing_get --briefing-uuid {B}`, where {B} came from
        your own BRIEFING_OPEN response; poll it until it reads ready. Then work from
        its ref set (dope dot-paths, kbite files; briefings are opinion-free ref
        pre-selections) plus your own deeper pulls. `wait_for_briefing` is the
        prompt-owned form and does not apply here — this briefing hangs off the
        session, and you hold its uuid anyway.

        ---

        ## Phase 2: Do the Task

        Execute the user's request directly in the primary context using
        Read / Edit / Write / Grep / Glob / Bash (and Task for subagents if a search
        genuinely warrants it).

        - Edit the user's repository files freely — that is the work. The
          PostToolUse hook captures those changes automatically; do not add manual
          `file_change_add` bookkeeping on top of it.
        - **Do not** author GMCC record entities (no prompt rows, no report summaries, no
          artifact registrations, nothing under `$GM_FS_ROOT`).
        - If the task balloons in scope and would benefit from the full clarify → plan →
          review pipeline, suggest the user re-run it under `/gm_bot` (or `/gm_bot_rpi`
          / `/gm_bot_team`) rather than reaching for GMCC bookkeeping here.

        When finished, give a concise summary: what you did, files touched, anything
        deferred. Do **not** persist that summary anywhere — it stays in the chat.

        ---

        ## Retroactive Write-Back (only on explicit request)

        Skip this section entirely unless the user, at some point in the conversation,
        explicitly asks you to record the work (e.g. "save that to the session",
        "record the files you changed", "write this up as a prompt"). Honor exactly
        what they ask for; do not volunteer writes.

        Two write targets are supported.

        ### A. Record / attribute changed files

        Edit/Write-driven changes were already captured automatically (unattributed).
        `mcp__plugin_gmcc_pen__file_change_add` is needed only for:

        - files changed through Bash (scripts, generators, `git mv`) — the hook sees
          the Bash call, not the paths inside it:
          `file_change_add(path: "<repo-relative path>", kind: "edit|create|delete|rename", prompt_uuid: "<U>")`
        - attributing the work to a prompt row (e.g. one created via write-back B):
          pass `prompt_uuid` on the rows you add.

        Run from inside the repo — git context is auto-detected.
        `mcp__plugin_gmcc_pen__file_change_list` shows what the machine believes you
        have touched.

        ### B. Record a prompt

        Capture the task after the fact as a prompt row (no clarify pipeline is run,
        so it lands as `draft`):

        ```bash
        gm_hook call PROMPT_CREATE --json '{
          "session_uuid": "{U}",
          "name": "{name}",
          "backstory": "",
          "goal": "<what the task aimed to achieve>",
          "detail": "<how it was done — the specifics>",
          "command": "/gm_task"
        }'
        ```

        (Retroactive capture is the one case where the bot authors `goal`/`detail` —
        it is recording work already done at the user's request, not splitting a
        human prompt. For a long write-up put the whole payload in a file and use
        `--json-file <path>`: shell argument limits are far below the daemon's
        content caps.) If you have artifacts to drop there, mkdir the memory dir at
        the RETURNED `gmfs_relative_storage_path` (relative to
        `gm_hook paths --json` → gmfs_root) — never re-derive `{seq}_{name}`
        yourself; the daemon slugs the name — registering each with:

        ```bash
        gm_hook call ARTIFACT_ADD --json '{"prompt_uuid":"{P}","file_path":"{abs path}","note":"..."}'
        ```

        After any write-back, state plainly what was persisted and where.
        """#

        /// The `## Example Invocation` block from
        /// `prompts/gmcc_agent_kbite_crunch_chew.prompt.md`.
        ///
        /// LIFTED OUT OF THE AGENT DEFINITION ON PURPOSE, and this is the one
        /// place the two Templates files disagree with their sources about
        /// where a line belongs. Both `prompts/*.prompt.md` files carry their
        /// spawn example INSIDE the persona definition, because a Claude Code
        /// prompt file is one document. Here the split is enforced by the type
        /// system: a persona contract is `Instructions`, an invocation is a
        /// `Prompt`, and shipping the example inside the instruction block
        /// would put a filled-in invocation into the half of the context the
        /// model is trained to obey over everything else.
        ///
        /// `{kbite_open_root}` is left unsubstituted because it is a TEMPLATE
        /// hole — the prompt file's own closing note says to substitute the
        /// real absolute root from `gm_hook paths --json` at compose time, and
        /// this package resolves no paths.
        public static let kbiteChewSpawn = #"""
        Task tool with subagent_type="gmcc:gmcc_agent_kbite_crunch_chew":
          prompt: |
            Chew the crunchable resource for kbite "claude_code_sdk".
            Crunchable: official_docs
            Axis1: primary
            Axis2: documentation
            Maw path: {kbite_open_root}/claude_code_sdk/primary/documentation/official_docs/
        """#

        /// The `## Example Invocation` block from
        /// `prompts/gmcc_agent_maw_web_fetch.prompt.md`. See `kbiteChewSpawn`
        /// for why it lives here rather than in the instruction block.
        public static let mawFetchSpawn = #"""
        Task tool:
          subagent_type: gmcc:gmcc_agent_maw_web_fetch
          model: sonnet
          prompt: |
            Download web pages for kbite "spatial".

            **Script Path**: $GM_PLUGIN_ROOT/scripts/maw_web_fetch.mjs
            **Maw Root**: {kbite_open_root}/spatial/
            **MAW_INDEX**: {kbite_open_root}/spatial/MAW_INDEX.md

            Resource to download:
            - Name: visionos_2_release_notes
            - URLs: ["https://developer.apple.com/documentation/visionos-release-notes/visionos-2-release-notes"]
            - Axis1: primary
            - Axis2: all_others
            - Output Dir: {kbite_open_root}/spatial/primary/all_others/visionos_2_release_notes/
        """#

        /// The contract text for one machine-driven variant.
        ///
        /// `task` is unreachable here on purpose — it is not a `BotVariant`.
        /// Read it as `Text.task`.
        public static func variantText(for variant: BotVariant) -> String {
            switch variant {
            case .bot: return bot
            case .rpi: return rpi
            case .team: return team
            }
        }

        /// The command that invokes each variant, for the `command` field a
        /// prompt row records.
        public static func command(for variant: BotVariant) -> String {
            switch variant {
            case .bot: return "/gm_bot"
            case .rpi: return "/gm_bot_rpi"
            case .team: return "/gm_bot_team"
            }
        }
    }

    /// Every variant contract, in declaration order, plus `task`.
    ///
    /// The roster. `task` is appended by hand because `BotVariant` does not
    /// carry it — see `Text.task`.
    public static let allVariantText: [(command: String, text: String)] =
        BotVariant.allCases.map { (Text.command(for: $0), Text.variantText(for: $0)) }
        + [("/gm_task", Text.task)]
}

// MARK: - Spawn prompts

extension GmAgentPrompts {

    /// What a persona is handed at spawn — and deliberately nothing more.
    ///
    /// EVERY FIELD HERE IS A UUID, AN ENUM, OR ONE LINE, which is the whole
    /// design. The variant contracts state the rule in prose ("Do not paste
    /// briefings or dope dumps into spawn prompts"); this type makes it
    /// structural, because there is no field a briefing could be pasted into.
    /// Personas pull their own context through the pen — that is what the pen
    /// is for, and a spawn prompt that pre-loads context both duplicates it and
    /// staleness-freezes it at spawn time.
    ///
    /// `promptUuid` is carried explicitly because a persona holds no activation
    /// claim: the primary owns the claim, so a spawned agent that is not told
    /// which prompt it is working on cannot derive one.
    public struct Spawn: Sendable, Hashable {

        /// Which persona is being spawned.
        public let role: GmAgentRole

        /// The prompt row this work belongs to. Nil only for a session-owned
        /// `/gm_task` doper briefing, which has no prompt row at all.
        public let promptUuid: String?

        /// The session that owns the work when `promptUuid` is nil.
        public let sessionUuid: String?

        /// The methodology this persona commits to. Ignored — and omitted from
        /// the rendered text — for a role whose `takesMethodology` is false.
        public let methodology: ExplorationAgentType?

        /// The summary row the persona writes into, where its definition asks
        /// for one (the clarifier, the architect in team flows, the reviewer).
        public let summaryUuid: String?

        /// ONE LINE naming the target. Not a brief, not a context dump.
        public let target: String

        public init(
            role: GmAgentRole,
            promptUuid: String? = nil,
            sessionUuid: String? = nil,
            methodology: ExplorationAgentType? = nil,
            summaryUuid: String? = nil,
            target: String
        ) {
            self.role = role
            self.promptUuid = promptUuid
            self.sessionUuid = sessionUuid
            self.methodology = methodology
            self.summaryUuid = summaryUuid
            self.target = target
        }

        /// The rendered spawn text.
        ///
        /// Line-per-fact rather than prose: every line is a label and a value,
        /// so a persona reading it cannot mistake an identifier for an
        /// instruction. The instruction half already arrived as `Instructions`.
        public var text: String {
            var lines: [String] = []
            if let promptUuid {
                lines.append("Prompt uuid: \(promptUuid)")
                lines.append(
                    "Pull it yourself with bot_current_prompt — you hold no "
                        + "activation claim.")
            }
            if let sessionUuid {
                lines.append("Owner session uuid: \(sessionUuid)")
            }
            if role.takesMethodology, let methodology {
                lines.append("Methodology: \(methodology.rawValue)")
            }
            if let summaryUuid {
                lines.append("Summary uuid: \(summaryUuid)")
            }
            lines.append("Target: \(target)")
            return lines.joined(separator: "\n")
        }
    }

    /// A doper briefing spawn, owned by a PROMPT.
    ///
    /// The step is always `initial` — it is the only step the plugin opens, and
    /// hardcoding it here is more honest than a parameter with one legal value.
    public static func doperSpawn(promptUuid: String, topic: String) -> Spawn {
        Spawn(role: .doper, promptUuid: promptUuid, target: "Step: initial. Topic: \(topic)")
    }

    /// A doper briefing spawn owned by a SESSION — the `/gm_task` shape, where
    /// no prompt row exists to hang the briefing off.
    public static func doperSpawn(sessionUuid: String, topic: String) -> Spawn {
        Spawn(role: .doper, sessionUuid: sessionUuid, target: "Step: initial. Topic: \(topic)")
    }

    /// The explore fan-out for a variant: one spawn per methodology the
    /// variant's gate expects.
    ///
    /// Reads the persona set from `WorkflowSpec.expectedExplorationAgents` so
    /// the fan-out cannot disagree with the gate that admits it — `bot`/`rpi`
    /// get one `general`, `team` gets the four methodologies.
    public static func exploreSpawns(
        variant: BotVariant,
        promptUuid: String,
        target: String
    ) -> [Spawn] {
        WorkflowSpec.expectedExplorationAgents(for: variant).map {
            Spawn(role: .explorer, promptUuid: promptUuid, methodology: $0, target: target)
        }
    }
}

// MARK: - FoundationModels values

@available(GmAgentOs 1.0, *)
extension GmAgentPrompts {

    /// A variant's operating contract as a `Prompt`.
    public static func variantPrompt(for variant: BotVariant) -> Prompt {
        Prompt(Text.variantText(for: variant))
    }

    /// The `/gm_task` contract as a `Prompt`.
    public static var taskPrompt: Prompt { Prompt(Text.task) }

    /// One phase's instruction text as a `Prompt`.
    ///
    /// DELEGATES rather than duplicating: the text comes from
    /// `WorkflowSpec.instructions(variant:phase:)` in gmDaemonSdk, which is the
    /// same text `bot_next` serves and is drift-guarded by WorkflowSpecTests. A
    /// copy here would have to be re-synced on every phase edit, and phase text
    /// is the part of the machine that changes most.
    public static func phasePrompt(variant: BotVariant, phase: WorkflowSpec.Phase) -> Prompt {
        Prompt(WorkflowSpec.instructions(variant: variant, phase: phase))
    }

    /// The whole phase graph for a variant, in order.
    public static func phasePrompts(for variant: BotVariant) -> [(WorkflowSpec.Phase, Prompt)] {
        WorkflowSpec.phases(for: variant).map { ($0, phasePrompt(variant: variant, phase: $0)) }
    }

    /// A spawn as a `Prompt`.
    public static func prompt(for spawn: Spawn) -> Prompt {
        Prompt(spawn.text)
    }
}
