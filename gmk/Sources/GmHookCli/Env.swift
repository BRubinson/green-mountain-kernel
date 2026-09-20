import Foundation

/// `gm_hook context env` — the SessionStart env block on stdout, consistency
/// warnings on stderr, ALWAYS exit 0.
///
/// EXIT 0 IS THE CONTRACT, not politeness. SessionStart sources this output; a
/// non-zero exit or a stray stdout line becomes a broken session env rather than
/// a warning about one. Everything diagnostic goes to stderr.
func emitSessionEnv(pluginRoot: String?) -> Int32 {
    guard let pluginRoot, !pluginRoot.isEmpty else {
        FileHandle.standardError.write(Data("[GMB] context env needs --plugin-root\n".utf8))
        return 0
    }
    let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""

    // try?, deliberately: a session must still come up with a usable env when
    // the daemon is down. The warning below is what tells the user why the
    // values are defaults.
    let client = DaemonClient()
    defer { client.close() }
    let paths = try? client.pathsGet()

    let lines = GmEnvironment.emit(
        pluginRoot: pluginRoot,
        inheritedPath: inheritedPath,
        dbFsRoot: paths?.gmFsRoot
    )
    for line in lines { print(line) }

    var warnings: [String] = []
    if let paths {
        warnings = GmEnvironment.check(paths).map(\.message)
    } else {
        warnings.append(
            "[GMB] daemon unavailable — env derived from defaults; run "
                + "'bash $GM_PLUGIN_ROOT/scripts/install_gm.sh' then restart the session"
        )
    }
    for warning in warnings {
        FileHandle.standardError.write(Data((warning + "\n").utf8))
    }
    return 0
}
