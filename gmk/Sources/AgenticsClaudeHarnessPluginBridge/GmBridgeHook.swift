import Foundation

extension GmBridgeHook {

    static let pluginRoot = GmBridgeClaudeTypePath.pluginRoot

    /// Where the kernel's binaries live, resolved at hook time rather than at
    /// generate time.
    ///
    /// There are three environments, and a hook fired in one must reach that
    /// root's kernel. A baked `$HOME/gmfs` gives one session two databases with
    /// no error and no signal.
    static let binDir = #"${GM_FS_ROOT:-$HOME/gmfs}/bin"#

    /// Where the generated hook executables live: inside the plugin itself.
    static let hookBinDir = #"${CLAUDE_PLUGIN_ROOT}/hooks/bin"#

    /// Generates the shell command to run a hook executable.
    ///
    /// Shell form (not exec form) because exec treats the command as a literal path
    /// and cannot expand variables. The `[ -x ]` guard and `exit 0` are the contract:
    /// a hook that exits non-zero blocks the tool call it fired on. A tree written by
    /// `gm_kernel bridge` alone has no binaries yet; it records nothing, not refusing every `Edit`.
    ///
    /// - Parameter binary: The hook binary name.
    /// - Returns: The shell command to run the binary.
    static func hookCommand(_ binary: String) -> String {
        #"[ -x "\#(hookBinDir)/\#(binary)" ] || exit 0; exec "\#(hookBinDir)/\#(binary)""#
    }

    /// `check_gm_stale.sh`, inlined.
    ///
    /// It reports a missing or dangling KERNEL — the `gm_daemon` symlink the
    /// plugin's own clients dial and autostart — which is why it is shell and
    /// not a subcommand: a subcommand cannot run when the binary it would report
    /// on is the thing that is absent. Exits 0 on every path — a stale install is
    /// a warning, never a blocked session.
    static let staleCheckCommand = #"""
        if [ ! -x "\#(binDir)/gm_daemon" ]; then \
          echo "[GMB] kernel missing at \#(binDir)/gm_daemon — run: bash \"$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh\"" >&2; \
        fi; exit 0
        """#

    /// Every event code the bridge's enums declare — the harness's vocabulary,
    /// flattened, so a registry entry that is not a real hook event is caught at
    /// generation rather than ignored at runtime.
    static let knownEventCodes: Set<String> = {
        var codes = Set<String>()
        codes.formUnion(Lifecycle.allCases.map(\.code))
        codes.formUnion(Turn.allCases.map(\.code))
        codes.formUnion(Tool.allCases.map(\.code))
        codes.formUnion(Permission.allCases.map(\.code))
        codes.formUnion(Agent.allCases.map(\.code))
        codes.formUnion(Task.allCases.map(\.code))
        codes.formUnion(Compaction.allCases.map(\.code))
        codes.formUnion(Model.allCases.map(\.code))
        codes.formUnion(Workspace.allCases.map(\.code))
        codes.formUnion(Worktree.allCases.map(\.code))
        codes.formUnion(Elicitation.allCases.map(\.code))
        codes.formUnion(Notification.allCases.map(\.code))
        return codes
    }()

    /// `hooks.json`: the SessionStart shell group, plus one group per registry
    /// entry FOLDED FROM `GmHookEvent`.
    ///
    /// The event key, the executable name, the matcher, the timeout and the
    /// async flag all come off the declared type, so the manifest cannot name
    /// an event the code does not handle.
    static let current: File = {
        var hooks: [String: [MatcherGroup]] = [
            Lifecycle.sessionStart.code: [
                MatcherGroup(
                    hooks: [
                        // STAYS A SCRIPT. SessionStart accepts only `command` and
                        // `mcp_tool`, and this is where the claude-session binding
                        // every later write depends on is created.
                        Handler(command: "\(pluginRoot)/scripts/gm_session_startup.sh"),
                        Handler(command: staleCheckCommand),
                    ],
                    matcher: "*"
                )
            ]
        ]
        for event in GmHookEvent.allCases {
            precondition(
                knownEventCodes.contains(event.rawValue),
                "\(event.rawValue) is not a Claude Code hook event"
            )
            let hook = event.hook
            hooks[event.rawValue] = [
                MatcherGroup(
                    hooks: [
                        Handler(
                            command: hookCommand(event.binaryName),
                            timeout: hook.timeout,
                            async: hook.isAsync ? true : nil
                        )
                    ],
                    matcher: hook.matcher
                )
            ]
        }
        return File(hooks: hooks)
    }()

    /// `hooks/src/<binary>.swift`: the generated main of one hook executable.
    ///
    /// The body is one call; everything else is the declared handler type.
    static var sources: [GmBridgeSwiftMain] {
        GmHookEvent.allCases.map { event in
            GmBridgeSwiftMain(
                directory: "hooks",
                name: event.binaryName,
                origin: "GmHookEvent.\(event)",
                entry: "\(String(describing: event.hook)).main()",
                closureFolders: []
            )
        }
    }
}
