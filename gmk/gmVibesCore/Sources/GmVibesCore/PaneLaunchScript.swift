import Foundation
import GmDaemonSdk
import GmITerm2Client

nonisolated func shellSingleQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

nonisolated func paneLaunchScript(root: String,
                                  repoPath: String,
                                  tabColorHex: String,
                                  tierCommand: String) -> String {
    """
    #!/bin/zsh
    rm -f "$0"
    cd \(shellSingleQuoted(repoPath)) || exit 1
    export GM_FS_ROOT=\(shellSingleQuoted(root))
    tabcolor=\(shellSingleQuoted(tabColorHex))
    case $TERM in
      screen*|tmux*) printf '\\033Ptmux;\\033\\033]1337;SetColors=tab=%s\\a\\033\\\\' "$tabcolor" ;;
      *)             printf '\\033]1337;SetColors=tab=%s\\a' "$tabcolor" ;;
    esac
    exec claude \(shellSingleQuoted(tierCommand))

    """
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
            try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                  ofItemAtPath: url.path)
        } catch {
            throw ITerm2Error.transportFailed(
                reason: "Could not write the launch script: \(error.localizedDescription)",
                errno: nil)
        }
        return url
    }
}
