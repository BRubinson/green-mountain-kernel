import Foundation
import GmDaemonSdk
import GmITerm2Client

nonisolated func shellSingleQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// The script a pane runs.
///
/// ## Two colour channels, two questions — they cannot fight
///
/// `tabColorHex` is the PROMPT's hue. `envBackgroundHex` is the ENVIRONMENT's.
/// The environment signal rides `bg` rather than `tab` because this repo's own
/// swatch help text admits the tab colour tints window chrome only under the
/// Minimal or Compact window styles and colours the tab alone under Regular —
/// so an environment signal on `tab` CAN FAIL TO RENDER ENTIRELY, and a beta
/// indicator that may be invisible is a detection mechanism that does not
/// detect. `bg` always shows.
///
/// OSC 1337 `SetColors=` accepts `fg bg bold link selbg selfg curbg curfg
/// underline tab` plus `key=preset`. No client change, no protobuf, no iTerm2
/// API method needed.
///
/// NAMED RETREAT: nobody has run the `bg` form from this script (the `tab` form
/// proves the transport). If it no-ops, fall back to the profile's
/// `Background Color` key through the Dynamic Profile writer in
/// `ExternalLaunchers.swift` — NOT to tinting `tab`, which reintroduces the
/// invisibility problem.
///
/// ## `--plugin-dir` CANNOT ride through `tierCommand`
///
/// `shellSingleQuoted` wraps its ENTIRE input in ONE pair of quotes, so
/// appending the flag to `tierCommand` yields ONE argv — a prompt string
/// starting with a hyphen — not a flag plus a command. The directory gets its
/// own `shellSingleQuoted` call and its own argv token.
///
/// ## A nil value emits NOTHING
///
/// Not `--plugin-dir ''` (an empty path claude will try to load and fail on),
/// and not an empty `envbg` assignment. With both nil the emission is
/// byte-identical to the pre-`setcolor` script apart from that refactor.
nonisolated func paneLaunchScript(root: String,
                                  repoPath: String,
                                  tabColorHex: String,
                                  tierCommand: String,
                                  pluginDir: String? = nil,
                                  envBackgroundHex: String? = nil) -> String {
    let envbgAssign = envBackgroundHex.map { "envbg=\(shellSingleQuoted($0))\n" } ?? ""
    let envbgCall = envBackgroundHex == nil
        ? ""
        : "[ -n \"$envbg\"    ] && setcolor bg  \"$envbg\"\n"
    let pluginFlag = pluginDir.map { "--plugin-dir \(shellSingleQuoted($0)) " } ?? ""
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
    [ -n "$tabcolor" ] && setcolor tab "$tabcolor"
    \(envbgCall)exec claude \(pluginFlag)\(shellSingleQuoted(tierCommand))

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
