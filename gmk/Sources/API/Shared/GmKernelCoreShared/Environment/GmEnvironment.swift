import Foundation

/// Single home for SessionStart env contract: emitted line set, PATH resolution
/// rule, installable shim text, env-vs-db consistency check.
///
/// Kit-level so GMVibes adopts the same resolution without duplication. `emit`
/// is socket-free (all values from ProcessInfo/Paths plus optional db-provided
/// gmfs root caller fetched). Only `check` needs daemon response.
enum GmEnvironment {

    struct Finding {
        let code: String
        let message: String
        /// Creates a finding with a code and message.
        ///
        /// - Parameters:
        ///   - code: A machine-readable error code.
        ///   - message: A human-readable message.
        init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    /// Resolves the gmfs root when the daemon value is unavailable.
    ///
    /// The ambient case delegates to `Paths.root` rather than re-deriving it.
    /// With an explicit environment dictionary, checks that dictionary only.
    /// Prefers `GM_FS_ROOT` env var, falls back to the default production root.
    ///
    /// - Parameter env: Environment dictionary to use, or `nil` for the process
    ///   environment (which returns `Paths.root`).
    /// - Returns: The resolved gmfs root URL.
    static func fallbackFsRoot(
        env: [String: String]? = nil
    ) -> URL {
        guard let env else { return Paths.root }
        if let override = env["GM_FS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Paths.defaultProductionRoot
    }

    /// Builds the CLAUDE_ENV_FILE shell script line set.
    ///
    /// Produces one `export KEY='VALUE'` per line for the shell preamble.
    /// Uses `export` to make variables inheritable and single quotes to protect
    /// values with spaces. Passing `dbFsRoot` makes the env/db match invariant true.
    ///
    /// - Parameters:
    ///   - pluginRoot: The plugin directory path.
    ///   - inheritedPath: The current `PATH` value.
    ///   - dbFsRoot: The daemon-provided gmfs root, or `nil` to use fallback.
    ///   - env: The environment dictionary; defaults to the process environment.
    ///   - bin: The runtime bin URL; defaults to `Paths.bin`.
    /// - Returns: Lines of `export KEY='VALUE'` statements.
    static func emit(
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
        // The plugin's own bin FIRST: `gm_hook` and `gm_mcp` ship there. The
        // runtime bin follows for `gm_kernel` and the `gm_daemon` symlink.
        let pluginBin = URL(fileURLWithPath: pluginRoot, isDirectory: true).appendingPathComponent("bin")
        pairs.append(("PATH", pathValue(current: inheritedPath, bins: [pluginBin, bin])))
        return pairs.map { "export \($0.0)=\(shellQuote($0.1))" }
    }

    /// Escapes a value for use in POSIX single-quoted shell context.
    ///
    /// Wraps in single quotes and closes/escapes/reopens for each embedded
    /// single quote. Safe for all path bytes except newlines, which cannot appear
    /// in environment values here.
    ///
    /// - Parameter value: The value to escape.
    /// - Returns: The quoted and escaped value.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Builds a deduped PATH value with plugin bins first.
    ///
    /// Prepends bins in order and removes any existing PATH components that point
    /// to them. Makes re-boots idempotent; prevents stale entries from shadowing
    /// the current install.
    ///
    /// - Parameters:
    ///   - current: The current `PATH` value.
    ///   - bins: Plugin bin directories, in priority order.
    /// - Returns: The deduplicated PATH value.
    static func pathValue(current: String, bins: [URL] = [Paths.bin]) -> String {
        let mine = bins.map(\.path)
        let survivors =
            current
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !mine.contains($0) }
        return (mine + survivors).joined(separator: ":")
    }

    /// Checks that the environment and database gmfs root values agree.
    ///
    /// The database is the source of truth. The environment variable is the
    /// claimed value. Compares one var against one config row; an injectable env
    /// parameter prevents the check from silently stopping when the runtime is
    /// not installed.
    ///
    /// - Parameters:
    ///   - paths: The paths configuration from the daemon.
    ///   - env: Environment dictionary to check; defaults to the process environment.
    /// - Returns: Findings for any mismatches found.
    static func check(
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

    /// The installable resolver shim.
    ///
    /// Resolves at CALL time rather than baking
    /// a path in, so one installed shim keeps working across upgrades and
    /// rollbacks — the release store swaps what `bin/` points at, and this
    /// follows it. The SessionStart hook sets GM_FS_ROOT.
    static let shimScript = """
        #!/bin/sh
        # GM client resolver. Do not edit.
        # Resolves at call time so one install survives upgrade and rollback;
        # the SessionStart hook sets GM_FS_ROOT.
        exec "${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_kernel" hook "$@"
        """
}
