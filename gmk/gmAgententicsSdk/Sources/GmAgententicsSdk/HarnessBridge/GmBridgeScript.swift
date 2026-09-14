import Foundation

extension GmBridgeScript {

    /// SessionStart provisioning. Stays a FILE and stays a `command` hook: the
    /// harness accepts only `command` and `mcp_tool` on SessionStart, an
    /// `mcp_tool` handler there is documented to expect a "not connected" error
    /// on first run, and SessionStart is precisely where the claude-session
    /// binding every later write depends on gets created.
    public static let sessionStartup = File(
        name: "gm_session_startup.sh",
        interpreter: .bash,
        body: sessionStartupBody
    )

    /// The marketplace installer. Cannot become a kernel subcommand for the
    /// obvious reason: it is what PUTS the kernel on the machine. It runs before
    /// any binary exists.
    public static let install = File(
        name: "install_gm.sh",
        interpreter: .bash,
        body: installBody
    )

    /// The release-store contract. Emitted from ONE constant, which is what
    /// retires the unchecked vendored twin — see `GmBridgeScript+Bodies.swift`.
    public static let releaseStore = File(
        name: "gm_releases.sh",
        interpreter: .bash,
        body: releaseStoreBody
    )

    /// THREE SCRIPTS ARE DELIBERATELY ABSENT, and their absence is the decision
    /// rather than an omission:
    ///
    /// - `gm_hook.sh` — inlined as a generated SHELL-FORM command string in
    ///   `hooks.json`. Shell form is the only handler type that resolves
    ///   `${GM_FS_ROOT:-$HOME/gmfs}` at hook time and the only one that can hold
    ///   the silent exit-0 no-op contract.
    /// - `run_mcp.sh` — replaced by the `.mcp.json` launcher. Note that stdio
    ///   `command`/`args` substitute only the three `CLAUDE_*` placeholders and
    ///   are spawned with NO SHELL, so the launcher runs `/bin/sh -c` rather
    ///   than relying on `${VAR:-default}` in the command itself.
    /// - `check_gm_stale.sh` — folded into an inline `[ -x ]` test in the same
    ///   hook string. It could NOT become a `gm_hook doctor` subcommand: it works
    ///   precisely because it needs no binary, and a subcommand that cannot run
    ///   when the binary is missing cannot report that the binary is missing.
    public static let all: [File] = [
        sessionStartup, install, releaseStore,
    ]
}
