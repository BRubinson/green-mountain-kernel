import Foundation

extension GmBridgeCommand {

    static let all: [File] = [
        file(
            name: "ask",
            description: """
                The catch-all GM-CDE command. Carries every gm capability — the whole tool \
                surface and an unrestricted shell — and does whatever is asked of the \
                kernel: daemon lifecycle, diagrams, maw fetching, artifact inspection, \
                one-off wire verbs. Reach for a scoped command when one fits; reach for \
                this when none does.
                """,
            argumentHint: "<anything you want gm to do>",
            allowed: everyGmCapability,
            body: GM_COMMAND_ASK_BODY
        ),
        file(
            name: "gm_bot",
            description: """
                Lightweight GMCC workflow (variant bot). Authors a prompt into the current \
                session, enters the kernel's workflow machine, and runs every phase in \
                primary context — the only spawn is the briefer's briefing.
                """,
            argumentHint: "<prompt-name|seq> <task/prompt content>",
            disableModelInvocation: true,
            allowed: rpirWorkflow,
            body: AgentGmkSessionProfile.bot.instruction.text
        ),
        file(
            name: "gm_bot_rpi",
            description: """
                Subagent GMCC workflow (variant rpi). One general-persona subagent per phase \
                adopts every methodology's goals at once; up to 2 implementation subagents; \
                the care package carries clarified intent into architecture.
                """,
            argumentHint: "<prompt-name|seq> <task/prompt content>",
            disableModelInvocation: true,
            allowed: rpirWorkflow,
            body: AgentGmkSessionProfile.rpi.instruction.text
        ),
        file(
            name: "gm_bot_team",
            description: """
                Agent-team GMCC workflow (variant team). Dynamic workflows drive \
                briefing+explore+clarify-open, implementation, and review-fix; four \
                methodology personas per fan-out phase; architecture optioning with one \
                decide step.
                """,
            argumentHint: "<prompt-name|seq> <task/prompt content>",
            disableModelInvocation: true,
            allowed: rpirWorkflow,
            body: AgentGmkSessionProfile.team.instruction.text
        ),
        file(
            name: "gm_task",
            description: """
                Load GMCC session context, then just do the task. Writes no prompt rows or \
                report summaries — persistence happens only via the automatic file-change \
                hook, an optional briefer briefing for meaty tasks, or an explicitly requested \
                retroactive write-back.
                """,
            argumentHint: "<task / request>",
            disableModelInvocation: true,
            allowed: rpirWorkflow,
            body: AgentGmkSessionProfile.task.instruction.text
        ),
        file(
            name: "gm_init",
            description: """
                Initialize the GM-CDE system at the user level. Creates the filesystem root, \
                installs the kernel binaries, and brings the daemon up. Run once per \
                machine; per-project, per-instance and per-session state is auto-ensured by \
                the SessionStart hook on first encounter.
                """,
            argumentHint: "[--force]",
            disableModelInvocation: true,
            allowed: [.bash, .read, .write, .glob, .askUserQuestion],
            body: GM_COMMAND_INIT_BODY
        ),
        file(
            name: "gm_install",
            description: """
                Install or upgrade the gm_kernel app and binaries to the version this \
                plugin was generated for. Reads the plugin's own version, checks what is \
                active, and fetches the matching GitHub release DMG only when they differ.
                """,
            argumentHint: "[--check | --force | --app | --no-app | --latest]",
            disableModelInvocation: true,
            allowed: [.bash, .read, .glob, .askUserQuestion],
            body: GM_COMMAND_INSTALL_BODY
        ),
        file(
            name: "gm_cleanup",
            description: """
                GM-CDE auditor. Audits the current session's artifact tree against its db \
                rows, the wider gmfs/db environment (kernel health, db-vs-disk drift, \
                archive hygiene, kbite provenance), and the host wiring that lives outside \
                any one repo (binary reachability, env-vs-db root agreement, permission \
                grants) — then interactively resolves each finding.
                """,
            argumentHint: "[session | environment | system | all] [--dry-run]",
            disableModelInvocation: true,
            allowed: [.read, .write, .bash, .glob, .askUserQuestion],
            body: GM_COMMAND_CLEANUP_BODY
        ),
        file(
            name: "gm_crunch_open_maw",
            description: "Open a maw for collecting kbite resources",
            argumentHint: "<kbite_name>",
            allowed: [.read, .write, .bash, .glob] + kbiteTools,
            body: GM_COMMAND_CRUNCH_OPEN_MAW_BODY
        ),
        file(
            name: "gm_crunch_chew",
            description: "Process crunchable resources in a maw to generate chewed analysis files",
            argumentHint: "<kbite_name>",
            allowed: [.read, .write, .bash, .glob, .grep, .task],
            body: GM_COMMAND_CRUNCH_CHEW_BODY
        ),
        file(
            name: "gm_crunch_digest",
            description: "Digest chewed maw resources into the kernel db and archive raw sources",
            argumentHint: "<kbite_name>",
            allowed: [.read, .write, .bash, .glob, .grep] + kbiteTools,
            body: GM_COMMAND_CRUNCH_DIGEST_BODY
        ),
        file(
            name: "gm_kbite_export",
            description: "Export one digested kbite to a portable gmcc_kbite zip",
            argumentHint: "<kbite_code> [output_dir]",
            allowed: [.read, .bash, .glob] + kbiteTools,
            body: GM_COMMAND_KBITE_EXPORT_BODY
        ),
        file(
            name: "gm_kbite_import",
            description: "Import a gmcc_kbite zip into this machine's kernel db",
            argumentHint: "<zip_path> [overwrite]",
            allowed: [.read, .bash, .glob, .askUserQuestion] + kbiteTools,
            body: GM_COMMAND_KBITE_IMPORT_BODY
        ),
        file(
            name: "gm_kbite_relate",
            description: "Define a relationship between two kbites for cross-referencing",
            argumentHint: "<kbite_from> <kbite_to> <relationship>",
            allowed: [.read, .write, .bash, .glob] + kbiteTools,
            body: GM_COMMAND_KBITE_RELATE_BODY
        ),
    ]

    /// The kbite surface, typed — what the crunch and kbite commands reach for.
    static var kbiteTools: [Tool] {
        GmBridgeMcpTool.tools(in: .kbite).map(Tool.mcp)
    }

    /// Every capability the kernel exposes: the native harness tools plus every
    /// bridged MCP tool, each carried as a typed value so a renamed or deleted
    /// tool fails the build instead of leaving a dead name in frontmatter.
    static var everyGmCapability: [Tool] {
        Native.allCases.map(Tool.native) + GmBridgeMcpTool.grantable.map(Tool.mcp)
    }

    /// The tools a workflow command needs to drive the RPIR phase machine.
    ///
    /// Pen tools only: the PreToolUse hook denies `gm_hook` from Bash, so a shell
    /// grant here would be a permission for something the harness refuses.
    static var rpirWorkflow: [Tool] {
        GmBridgeMcpTool.tools(in: .cde).map(Tool.mcp)
            + GmBridgeMcpTool.tools(in: .rpir).map(Tool.mcp)
    }

    /// Creates a tool definition for a file.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - whenToUse: When to use this tool, or nil.
    ///   - argumentHint: Hint for tool arguments, or nil.
    ///   - arguments: List of argument names.
    ///   - disableModelInvocation: Whether to disable model invocation.
    ///   - userInvocable: Whether the tool is user-invocable.
    ///   - allowed: Allowed tools.
    ///   - disallowed: Disallowed tools.
    ///   - model: The model to use, or nil.
    ///   - effort: The reasoning effort level, or nil.
    ///   - context: The context level, or nil.
    ///   - agent: The agent name, or nil.
    ///   - background: Whether to run in background.
    ///   - hooks: Hook groups by name.
    ///   - shell: The shell type, or nil.
    ///   - metadata: Custom metadata.
    ///   - license: License information, or nil.
    ///   - compatibility: Compatibility information, or nil.
    ///   - body: The tool body/description text.
    /// - Returns: A File tool definition.
    static func file(
        name: String,
        description: String,
        whenToUse: String? = nil,
        argumentHint: String? = nil,
        arguments: [String] = [],
        disableModelInvocation: Bool? = nil,
        userInvocable: Bool? = nil,
        allowed: [Tool] = [],
        disallowed: [Tool] = [],
        model: Model? = nil,
        effort: Effort? = nil,
        context: Context? = nil,
        agent: String? = nil,
        background: Bool? = nil,
        hooks: [String: [HookGroup]] = [:],
        shell: Shell? = nil,
        metadata: [String: String] = [:],
        license: String? = nil,
        compatibility: String? = nil,
        body: String = ""
    ) -> File {
        File(
            name: name,
            description: GmBridgeYaml.oneLine(description),
            whenToUse: whenToUse,
            argumentHint: argumentHint,
            arguments: arguments,
            disableModelInvocation: disableModelInvocation,
            userInvocable: userInvocable,
            allowedTools: allowed,
            disallowedTools: disallowed,
            model: model,
            effort: effort,
            context: context,
            agent: agent,
            background: background,
            hooks: hooks,
            shell: shell,
            metadata: metadata,
            license: license,
            compatibility: compatibility,
            body: body
        )
    }
}
