import Foundation

extension GmBridgeScript {

    public static let sessionStartup = File(
        name: "gm_session_startup.sh",
        interpreter: .bash
    )

    public static let staleCheck = File(
        name: "check_gm_stale.sh",
        interpreter: .bash
    )

    public static let hook = File(
        name: "gm_hook.sh",
        interpreter: .bash
    )

    public static let mcpLauncher = File(
        name: "run_mcp.sh",
        interpreter: .bash
    )

    public static let install = File(
        name: "install_gm.sh",
        interpreter: .bash
    )

    public static let releaseStore = File(
        name: "gm_releases.sh",
        interpreter: .bash
    )

    public static let all: [File] = [
        sessionStartup, staleCheck, hook, mcpLauncher, install, releaseStore,
    ]
}
