import Foundation

extension GmBridgeScript {

    /// SessionStart provisioning. Stays a FILE and stays a `command` hook: the
    /// harness accepts only `command` and `mcp_tool` on SessionStart, an
    /// `mcp_tool` handler there is documented to expect a "not connected" error
    /// on first run, and SessionStart is precisely where the claude-session
    /// binding every later write depends on gets created.
    static let sessionStartup = File(
        name: "gm_session_startup.sh",
        interpreter: .bash,
        body: sessionStartupBody
    )

    /// The marketplace installer. Cannot become a kernel subcommand for the
    /// obvious reason: it is what PUTS the kernel on the machine. It runs before
    /// any binary exists.
    static let install = File(
        name: "install_gm.sh",
        interpreter: .bash,
        body: installBody
    )

    /// The release-store contract, emitted from ONE constant so the plugin's copy
    /// cannot drift from the authored one. See `GmBridgeScript+Bodies.swift`.
    static let releaseStore = File(
        name: "gm_releases.sh",
        interpreter: .bash,
        body: releaseStoreBody
    )

    /// Three scripts are deliberately absent as files:
    ///
    /// - `gm_hook.sh` — inlined as a shell-form command in `hooks.json`, the only
    ///   handler type resolving `${GM_FS_ROOT:-$HOME/gmfs}` at hook time and able
    ///   to hold the silent exit-0 no-op contract.
    /// - `run_mcp.sh` — the `.mcp.json` launcher runs `/bin/sh -c`, since stdio
    ///   `command`/`args` substitute only the three `CLAUDE_*` placeholders.
    /// - `check_gm_stale.sh` — an inline `[ -x ]` test, needing no binary at all.
    static let all: [File] = [
        sessionStartup, install, releaseStore,
    ]
}
