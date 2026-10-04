import Foundation

/// Escapes a string for safe use as a single-quoted shell argument.
///
/// - Parameter s: The string to escape.
/// - Returns: The escaped string in single quotes.
nonisolated func shellSingleQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Generates the shared preamble for pane scripts.
///
/// The preamble includes self-delete, cd, root export, OSC 1337 helpers, and visual
/// signals. One preamble with two tails ensure claude and shell forms stay in sync.
///
/// - Parameters:
///   - root: The GM_FS_ROOT value to export.
///   - repoPath: The repository path to cd into.
///   - tabColorHex: The hex color for the terminal tab.
///   - badgeText: Optional badge text; nil emits nothing.
///   - envBackgroundHex: Optional environment background hex; nil emits nothing.
/// - Returns: A shell script preamble.
private nonisolated func paneScriptPreamble(
    root: String,
    repoPath: String,
    tabColorHex: String,
    badgeText: String?,
    envBackgroundHex: String?
) -> String {
    let envbgAssign = envBackgroundHex.map { "envbg=\(shellSingleQuoted($0))\n" } ?? ""
    let envbgCall =
        envBackgroundHex == nil
        ? ""
        : "[ -n \"$envbg\"    ] && setcolor bg  \"$envbg\"\n"
    let badgeCall =
        badgeText.map {
            "setbadge \"$(printf %s \(shellSingleQuoted($0)) | base64)\"\n"
        } ?? ""
    return """
        #!/bin/zsh
        rm -f "$0"
        cd \(shellSingleQuoted(repoPath)) || exit 1
        export GM_FS_ROOT=\(shellSingleQuoted(root))
        tabcolor=\(shellSingleQuoted(tabColorHex))
        \(envbgAssign)setcolor() {   # $1=key  $2=hex
          case $TERM in
            screen*|tmux*) printf '\\033Ptmux;\\033\\033]1337;SetColors=%s=%s\\a\\033\\\\' "$1" "$2" ;;
            *)             printf '\\033]1337;SetColors=%s=%s\\a' "$1" "$2" ;;
          esac
        }
        setbadge() {   # $1=base64 text
          case $TERM in
            screen*|tmux*) printf '\\033Ptmux;\\033\\033]1337;SetBadgeFormat=%s\\a\\033\\\\' "$1" ;;
            *)             printf '\\033]1337;SetBadgeFormat=%s\\a' "$1" ;;
          esac
        }
        [ -n "$tabcolor" ] && setcolor tab "$tabcolor"
        \(envbgCall)\(badgeCall)
        """
}

/// Generates a pane script that launches Claude.
///
/// - Parameters:
///   - root: The GM_FS_ROOT value to export.
///   - repoPath: The repository path to cd into.
///   - tabColorHex: The hex color for the terminal tab.
///   - tierCommand: The Claude command tier to run.
///   - pluginDir: Optional plugin directory path.
///   - badgeText: Optional badge text.
///   - envBackgroundHex: Optional environment background hex.
/// - Returns: A shell script to launch Claude in the pane.
nonisolated func paneLaunchScript(
    root: String,
    repoPath: String,
    tabColorHex: String,
    tierCommand: String,
    pluginDir: String? = nil,
    badgeText: String? = nil,
    envBackgroundHex: String? = nil
) -> String {
    let pluginFlag = pluginDir.map { "--plugin-dir \(shellSingleQuoted($0)) " } ?? ""
    return paneScriptPreamble(
        root: root,
        repoPath: repoPath,
        tabColorHex: tabColorHex,
        badgeText: badgeText,
        envBackgroundHex: envBackgroundHex
    )
        + "exec claude \(pluginFlag)\(shellSingleQuoted(tierCommand))\n"
}

/// Generates a pane script that launches an interactive shell.
///
/// The pane prepares the environment with root export and prepends
/// `$GM_FS_ROOT/bin` to PATH for `gm_hook` resolution.
///
/// - Parameters:
///   - root: The GM_FS_ROOT value to export.
///   - repoPath: The repository path to cd into.
///   - tabColorHex: The hex color for the terminal tab.
///   - shell: The shell executable to launch.
///   - badgeText: Optional badge text.
///   - envBackgroundHex: Optional environment background hex.
/// - Returns: A shell script to launch the interactive shell in the pane.
nonisolated func paneShellScript(
    root: String,
    repoPath: String,
    tabColorHex: String,
    shell: String,
    badgeText: String? = nil,
    envBackgroundHex: String? = nil
) -> String {
    paneScriptPreamble(
        root: root,
        repoPath: repoPath,
        tabColorHex: tabColorHex,
        badgeText: badgeText,
        envBackgroundHex: envBackgroundHex
    )
        + "export PATH=\"$GM_FS_ROOT/bin:$PATH\"\n"
        + "exec \(shellSingleQuoted(shell)) -i\n"
}

/// Returns the user's login shell path.
///
/// - Returns: The login shell path, or /bin/zsh if not determinable.
nonisolated func loginShellPath() -> String {
    let fallback = "/bin/zsh"
    guard let pw = getpwuid(getuid()), let raw = pw.pointee.pw_shell else { return fallback }
    let shell = String(cString: raw)
    switch (shell as NSString).lastPathComponent {
    case "zsh", "bash", "sh": return shell
    default: return fallback
    }
}

/// Constructs a command line for executing a pane script.
///
/// - Parameters:
///   - shell: The shell executable to use.
///   - scriptPath: The path to the script to execute.
/// - Returns: The command line string.
/// - Throws: `ITerm2Error.unsafeCommandPath` if the path contains quotes or escapes.
nonisolated func paneCommandLine(shell: String, scriptPath: String) throws(ITerm2Error) -> String {
    guard !scriptPath.contains("\""), !scriptPath.contains("\\") else {
        throw ITerm2Error.unsafeCommandPath(scriptPath)
    }
    guard !shell.contains("\""), !shell.contains("\\") else {
        throw ITerm2Error.unsafeCommandPath(shell)
    }
    return "\(shell) -l \"\(scriptPath)\""
}

enum PaneScriptWriter {
    /// Writes a pane script to a temp file and returns its URL.
    ///
    /// - Parameters:
    ///   - script: The script content to write.
    ///   - root: The root directory path.
    /// - Returns: The URL of the written script file.
    /// - Throws: `ITerm2Error.unsafeCommandPath` if the path is unsafe.
    nonisolated static func write(script: String, root: String) throws(ITerm2Error) -> URL {
        let dir = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("gm_pane", isDirectory: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).sh")
        do {
            try Paths.assertContained(url)
        } catch {
            throw ITerm2Error.unsafeCommandPath(url.path)
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(script.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            throw ITerm2Error.transportFailed(
                reason: "Could not write the launch script: \(error.localizedDescription)",
                errno: nil
            )
        }
        return url
    }
}
