import Foundation

extension GmBridgeHook {

    public static let pluginRoot = GmBridgeClaudeTypePath.pluginRoot

    /// Where the binaries live, resolved AT HOOK TIME rather than at generate
    /// time.
    ///
    /// `${GM_FS_ROOT:-$HOME/gmfs}` and not a baked path, because there are THREE
    /// environments — prod at `~/gmfs`, beta at `~/beta_gmfs`, and per-run test
    /// roots under `~/test_gmfs/runs/` — and a hook fired in one of them must
    /// reach that root's kernel. Baking `$HOME/gmfs` here is the recorded
    /// reversal `gm_hook.sh` carries in its own header: it produced "one
    /// session, two databases, no error, no signal".
    ///
    /// This is also the reason every hook below is SHELL FORM. Shell form is the
    /// only handler type that expands a variable at hook time; exec form treats
    /// the command as a literal path and would look for a directory named
    /// `${GM_FS_ROOT:-$HOME/gmfs}`.
    static let binDir = #"${GM_FS_ROOT:-$HOME/gmfs}/bin"#

    /// The shim `gm_hook.sh` used to be, inlined.
    ///
    /// THE `[ -x ]` GUARD AND `exit 0` ARE THE WHOLE CONTRACT, not defensive
    /// noise. A hook that exits non-zero BLOCKS the tool call it fired on, so a
    /// machine with no kernel installed would have every `Edit` and every `Bash`
    /// refused by its own tooling. Silence is the correct behaviour when the
    /// binary is absent, and it is why this cannot be an exec-form command:
    /// exec form cannot express a conditional.
    static func hookCommand(_ subcommand: String) -> String {
        #"[ -x "\#(binDir)/gm_hook" ] || exit 0; exec "\#(binDir)/gm_hook" hook \#(subcommand)"#
    }

    /// `check_gm_stale.sh`, inlined.
    ///
    /// It reports a MISSING OR DANGLING binary, which is exactly why it could
    /// not become a `gm_hook doctor` subcommand: a subcommand cannot run when
    /// the binary it would report on is the thing that is absent. Folding it
    /// into a subcommand would have turned the only broken-install report in the
    /// system into silence.
    ///
    /// Exits 0 on every path — a stale install is a warning, never a blocked
    /// session.
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
