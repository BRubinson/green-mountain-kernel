import Foundation

extension GmBridgeHook {

    public static let pluginRoot = GmBridgeClaudeTypePath.pluginRoot

    public static let current = File(
        hooks: [
            Lifecycle.sessionStart.code: [
                MatcherGroup(
                    matcher: "*",
                    hooks: [
                        Handler(command: "\(pluginRoot)/scripts/gm_session_startup.sh"),
                        Handler(command: "\(pluginRoot)/scripts/check_gm_stale.sh"),
                    ]
                )
            ],
            Agent.subagentStart.code: [
                MatcherGroup(
                    hooks: [
                        Handler(
                            command: "\(pluginRoot)/scripts/gm_hook.sh subagent-start",
                            timeout: 5
                        )
                    ]
                )
            ],
            Tool.postToolUse.code: [
                MatcherGroup(
                    matcher: "Edit|Write|NotebookEdit|Bash",
                    hooks: [
                        Handler(
                            command: "\(pluginRoot)/scripts/gm_hook.sh post-tool-use",
                            async: true
                        )
                    ]
                )
            ],
        ]
    )
}
