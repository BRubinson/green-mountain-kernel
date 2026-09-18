import Foundation
import GmDaemonSdk
import GmITerm2Client

nonisolated func shellSingleQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// The shared preamble both pane scripts start with: self-delete, cd, root export, the OSC
/// 1337 helpers, and the three visual signals. One preamble, two tails, so the claude form
/// and the shell form cannot drift.
///
/// The environment signal rides `bg`, never `tab`: the tab colour tints window chrome only
/// under the Minimal or Compact window styles, so a `tab` signal can fail to render at all.
/// `--plugin-dir` gets its own `shellSingleQuoted` call, because that helper wraps its entire
/// input in ONE pair of quotes. A nil value emits nothing at all rather than an empty flag.
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

/// The INDEPENDENT pane: the same prepared environment, an interactive shell
/// instead of a bot run. `$GM_FS_ROOT/bin` is prepended to PATH so `gm_hook`
/// (and a hand-typed `claude`) resolve against this root's staged binaries —
/// a zshrc that RESETS PATH can shadow the prepend, which is cosmetic;
/// GM_FS_ROOT itself survives any rc file.
nonisolated func paneShellScript(
    root: String,
    repoPath: String,
    tabColorHex: String,
    badgeText: String? = nil,
    envBackgroundHex: String? = nil,
    shell: String
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

nonisolated func loginShellPath() -> String {
    let fallback = "/bin/zsh"
    guard let pw = getpwuid(getuid()), let raw = pw.pointee.pw_shell else { return fallback }
    let shell = String(cString: raw)
    switch (shell as NSString).lastPathComponent {
    case "zsh", "bash", "sh": return shell
    default: return fallback
    }
}

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
