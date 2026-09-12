import Foundation

/// Single home for the SessionStart env contract: the emitted line set, the
/// PATH resolution rule, the installable shim text, and the env-vs-db
/// consistency check. Kit-level so GMVibes can adopt the same resolution
/// without a second implementation.
///
/// `emit` is socket-free by construction — every value comes from
/// ProcessInfo/Paths (plus an optional db-provided gmfs root the caller
/// fetched best-effort). Only `check` needs a daemon response.
public enum GmEnvironment {

    public struct Finding {
        public let code: String
        public let message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    /// `$GM_FS_ROOT` when set, else `~/gmfs` — the daemon-free
    /// resolution used when the db value is unavailable.
    ///
    /// `env` is injectable so a test can state the claim it is testing instead
    /// of inheriting the ambient machine's. A test that reads the real process
    /// environment is a test whose result depends on whether the runtime
    /// happens to be installed — which is exactly how the mismatch assertion
    /// below came to pass vacuously.
    public static func fallbackFsRoot(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = env["GM_FS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmfs", isDirectory: true)
    }

    /// The full CLAUDE_ENV_FILE line set — one `export KEY='VALUE'` per line.
    ///
    /// CLAUDE_ENV_FILE is a **shell script** Claude Code runs as a preamble
    /// before every Bash command, so the shape is load-bearing twice over:
    ///
    /// - `export`, because a bare assignment sets a shell variable that no
    ///   child process inherits. Without it `getenv("GM_FS_ROOT")` is empty in
    ///   every gm/daemon/script invocation the session makes — the sandbox
    ///   split-brain this file exists to prevent.
    /// - single quotes, because an unquoted value stops at the first space.
    ///   A PATH carrying a component like `/Applications/VMware Fusion.app/…`
    ///   truncates the assignment, so PATH is never set at all and the
    ///   remainder runs as a command — one shell error on every tool call.
    ///
    /// Values ship as fully-resolved literals; single quoting means no
    /// expansion happens, so a `$PATH` reference would never resolve.
    ///
    /// - `dbFsRoot`: pathsGet().gmFsRoot when the daemon answered — emitting
    ///   the DB value makes the env/db match invariant true by construction.
    /// - `env` / `bin`: injection seams. Production callers pass neither.
    public static func emit(
        pluginRoot: String, inheritedPath: String, dbFsRoot: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment,
        bin: URL = Paths.bin
    ) -> [String] {
        var pairs = [("GM_BOOTED", "1"), ("GM_PLUGIN_ROOT", pluginRoot)]
        // ONE root, emitted ONCE. This used to be two lines — a runtime-root
        // passthrough (present only when sandboxed) and a content-root
        // computation (always present). Collapsing them is the whole point of
        // the one-root shape: the sandbox is now a different VALUE of this var
        // rather than a different SHAPE of the env block, so the emitted set no
        // longer varies by whether a session is sandboxed.
        //
        // Precedence, and the reason for it:
        //   1. the db value when the daemon answered — emitting the db's own
        //      answer makes the env/db agreement invariant true by construction
        //   2. the inherited claim (a sandbox launcher or the SessionStart hook
        //      set it, and Paths.root already resolved against it) — dropping
        //      it here is the split-brain bug: the session believes it is
        //      sandboxed while its in-session clients drive prod
        //   3. the daemon-free fallback
        pairs.append(("GM_FS_ROOT", dbFsRoot ?? fallbackFsRoot(env: env).path))
        pairs.append(("PATH", pathValue(current: inheritedPath, bin: bin)))
        return pairs.map { "export \($0.0)=\(shellQuote($0.1))" }
    }

    /// POSIX single-quote escaping: wrap in `'`, and close/escape/reopen for
    /// every embedded `'`. Safe for every byte a path can hold except a
    /// newline, which no env value here can contain.
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// This runtime's bin first, deduped: prepend `Paths.bin` and drop any
    /// other component that already points at it, so re-boots are idempotent
    /// and a sandbox session can never resolve a bare binary name to the prod
    /// build through a stale leading entry.
    public static func pathValue(current: String, bin: URL = Paths.bin) -> String {
        let mine = bin.path
        let survivors = current
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0 != mine }
        return ([mine] + survivors).joined(separator: ":")
    }

    /// Env-vs-db agreement (the user's r35 ruling: "both should always match
    /// or we get worried"). The db is the source; the env is the claim.
    ///
    /// ONE comparison, because there is now one root. This used to be two
    /// checks against two vars, and the weaker of the two was the runtime root,
    /// which was set only when sandboxed — so on an unsandboxed session that
    /// check silently did nothing. One always-present var turns the rule from
    /// "compare two vars against two config rows, one of which may legitimately
    /// be absent" into "compare one var against one config row, always
    /// present," which is a check that cannot quietly stop running.
    ///
    /// `env` is injectable. The claim is an INPUT to this check, so a test must
    /// be able to supply it: reading the process environment made the mismatch
    /// assertion conditional on the runtime being installed, and a test that
    /// silently stops asserting is worse than one that fails.
    public static func check(
        _ paths: PathsGetResponse,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [Finding] {
        var findings: [Finding] = []
        if let claimed = env["GM_FS_ROOT"], !claimed.isEmpty,
           URL(fileURLWithPath: claimed).standardizedFileURL.path
               != URL(fileURLWithPath: paths.gmFsRoot).standardizedFileURL.path {
            findings.append(Finding(code: "gmfs_root_mismatch", message:
                "[GMB] WARN: gmfs_root disagreement — env \(claimed) vs daemon \(paths.gmFsRoot). "
                + "Either the daemon answering this socket lives elsewhere, or the db "
                + "disagrees with the session. In a sandbox: gm_hook sandbox refresh. "
                + "In prod: gm_hook call CONFIG_SET "
                + "--json '{\"key\":\"gmfs_root\",\"value\":\"<correct>\"}'."))
        }
        return findings
    }

    /// The installable resolver shim. Resolves at CALL time so one install
    /// serves prod and every sandbox generation; sandbox launchers and the
    /// SessionStart hook set GM_FS_ROOT.
    public static let shimScript = """
        #!/bin/sh
        # GM client resolver. Do not edit.
        # Resolves at call time so one install serves prod and every sandbox
        # generation; sandbox launchers and the SessionStart hook set GM_FS_ROOT.
        exec "${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook" "$@"
        """
}
