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

    /// The daemon-free root resolution used when the db value is unavailable.
    ///
    /// The ambient case DELEGATES TO `Paths.root` rather than re-deriving it;
    /// one resolver cannot disagree with itself, and a second would let a
    /// shell-facing surface report one root while the process writes another.
    /// The explicit-`env` path stays env-only: a caller passing a dictionary
    /// is asking what a session with THAT environment would resolve, and
    /// answering from this process's bundle would ignore the question.
    public static func fallbackFsRoot(
        env: [String: String]? = nil
    ) -> URL {
        guard let env else { return Paths.root }
        if let override = env["GM_FS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Paths.defaultProductionRoot
    }

    /// The full CLAUDE_ENV_FILE line set — one `export KEY='VALUE'` per line.
    ///
    /// CLAUDE_ENV_FILE is a shell script run as a preamble before every Bash
    /// command, so both halves of the shape are load-bearing. `export`,
    /// because a bare assignment sets a shell variable no child inherits.
    /// Single quotes, because an unquoted value stops at the first space and a
    /// PATH component holding one truncates the assignment. Passing `dbFsRoot`
    /// makes the env/db match invariant true by construction.
    public static func emit(
        pluginRoot: String,
        inheritedPath: String,
        dbFsRoot: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment,
        bin: URL = Paths.bin
    ) -> [String] {
        var pairs = [("GM_BOOTED", "1"), ("GM_PLUGIN_ROOT", pluginRoot)]
        // ONE root, emitted ONCE, with exactly one legitimate value; a
        // disagreement is a misconfiguration rather than a mode. Precedence:
        //   1. the db value when the daemon answered, which makes env/db
        //      agreement true by construction
        //   2. the inherited claim, forwarded rather than recomputed so the
        //      session and its in-session clients share one runtime
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
    /// and a stale leading entry can never win a bare binary name over the
    /// install this session is actually running.
    public static func pathValue(current: String, bin: URL = Paths.bin) -> String {
        let mine = bin.path
        let survivors =
            current
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0 != mine }
        return ([mine] + survivors).joined(separator: ":")
    }

    /// Env-vs-db agreement: the db is the source, the env is the claim.
    ///
    /// ONE comparison against one always-present var and one config row, which
    /// is a check that cannot quietly stop running. `env` is injectable
    /// because the claim is an INPUT here — reading the process environment
    /// would make the mismatch assertion conditional on the runtime being
    /// installed, and a check that silently stops asserting is worse than one
    /// that fails.
    public static func check(
        _ paths: PathsGetResponse,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [Finding] {
        var findings: [Finding] = []
        if let claimed = env["GM_FS_ROOT"], !claimed.isEmpty,
            URL(fileURLWithPath: claimed).standardizedFileURL.path
                != URL(fileURLWithPath: paths.gmFsRoot).standardizedFileURL.path
        {
            findings.append(
                Finding(
                    code: "gmfs_root_mismatch",
                    message:
                        "[GMB] WARN: gmfs_root disagreement — env \(claimed) vs daemon \(paths.gmFsRoot). "
                        + "Either the daemon answering this socket lives elsewhere, or the db "
                        + "disagrees with the session. Fix with: gm_hook call CONFIG_SET "
                        + "--json '{\"key\":\"gmfs_root\",\"value\":\"<correct>\"}'."
                )
            )
        }
        return findings
    }

    /// The installable resolver shim. Resolves at CALL time rather than baking
    /// a path in, so one installed shim keeps working across upgrades and
    /// rollbacks — the release store swaps what `bin/` points at, and this
    /// follows it. The SessionStart hook sets GM_FS_ROOT.
    public static let shimScript = """
        #!/bin/sh
        # GM client resolver. Do not edit.
        # Resolves at call time so one install survives upgrade and rollback;
        # the SessionStart hook sets GM_FS_ROOT.
        exec "${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook" "$@"
        """
}
