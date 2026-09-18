import Foundation

extension GmBridgeHook {

    public static let pluginRoot = GmBridgeClaudeTypePath.pluginRoot

    /// Where the binaries live, resolved at hook time rather than at generate time.
    ///
    /// `${GM_FS_ROOT:-$HOME/gmfs}` and not a baked path: there are three
    /// environments, and a hook fired in one must reach that root's kernel. A
    /// baked `$HOME/gmfs` gives one session two databases with no error and no
    /// signal. It is also why every hook below is SHELL FORM — exec form treats
    /// the command as a literal path and would look for a directory named
    /// `${GM_FS_ROOT:-$HOME/gmfs}`.
    static let binDir = #"${GM_FS_ROOT:-$HOME/gmfs}/bin"#

    /// The `gm_hook.sh` shim, inlined.
    ///
    /// The `[ -x ]` guard and `exit 0` are the whole contract: a hook that exits
    /// non-zero BLOCKS the tool call it fired on, so a machine with no kernel
    /// installed would have every `Edit` and every `Bash` refused by its own
    /// tooling. Exec form cannot express that conditional.
    static func hookCommand(_ subcommand: String) -> String {
        #"[ -x "\#(binDir)/gm_hook" ] || exit 0; exec "\#(binDir)/gm_hook" hook \#(subcommand)"#
    }

    /// `check_gm_stale.sh`, inlined.
    ///
    /// It reports a missing or dangling binary, which is why it cannot be a
    /// `gm_hook doctor` subcommand: a subcommand cannot run when the binary it
    /// would report on is the thing that is absent. Exits 0 on every path — a
    /// stale install is a warning, never a blocked session.
    static let staleCheckCommand = #"""
        if [ ! -x "\#(binDir)/gm_hook" ]; then \
          echo "[GMB] gm_hook missing at \#(binDir) — run: bash \"$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh\"" >&2; \
        fi; exit 0
        """#

    public static let current = File(
        hooks: [
            Lifecycle.sessionStart.code: [
                MatcherGroup(
                    matcher: "*",
                    hooks: [
                        // STAYS A FILE, and stays `command`. SessionStart accepts
                        // only `command` and `mcp_tool`; an `mcp_tool` handler
                        // here is documented to expect a "not connected" error on
                        // first run, and this is precisely where the
                        // claude-session binding every later write depends on is
                        // created.
                        Handler(command: "\(pluginRoot)/scripts/gm_session_startup.sh"),
                        Handler(command: staleCheckCommand),
                    ]
                )
            ],
            Agent.subagentStart.code: [
                MatcherGroup(
                    hooks: [
                        Handler(command: hookCommand("subagent-start"), timeout: 5)
                    ]
                )
            ],
            Tool.preToolUse.code: [
                MatcherGroup(
                    matcher: "Bash",
                    hooks: [
                        // DENIES a Bash command that invokes `gm_hook`. The binary
                        // is the harness's client, not an agent door; every
                        // agent-facing verb is a pen tool. The decision rides the
                        // JSON, so exit is 0 on every path and the hook contract
                        // holds. No socket, no daemon — pure string work
                        // in-process.
                        Handler(command: hookCommand("pre-tool-use"), timeout: 5)
                    ]
                )
            ],
            Tool.postToolUse.code: [
                MatcherGroup(
                    matcher: "Edit|Write|NotebookEdit|Bash",
                    hooks: [
                        // ASYNC, and `async` is a command-only field — a third
                        // reason this stays a command hook rather than becoming
                        // `mcp_tool`. PostToolUse is the hottest hook in the
                        // system; making it synchronous puts a socket round trip
                        // on every Bash call.
                        Handler(command: hookCommand("post-tool-use"), async: true)
                    ]
                )
            ],
        ]
    )
}
