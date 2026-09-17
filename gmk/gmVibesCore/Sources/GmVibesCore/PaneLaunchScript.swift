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
/// The shared preamble both pane scripts start with: self-delete, cd, root
/// export, the OSC 1337 helpers, and the three visual signals (tab hue,
/// environment background, environment badge). Extracted so the claude form
/// and the shell form cannot drift — one preamble, two tails.
///
/// The BADGE is the environment's HEADER: iTerm2 renders SetBadgeFormat as a
/// large text overlay in the pane, which is what makes a TEST pane say TEST
/// where a background tint alone can be mistaken for a theme. The payload is
/// base64 per the OSC 1337 contract, computed in-shell so this string stays
/// printable. A nil badge emits no CALL, like the other nil channels — the
/// setbadge helper itself is always defined, so a production script carries
/// the (inert) definition; only the call is conditional.
private nonisolated func paneScriptPreamble(root: String,
                                            repoPath: String,
                                            tabColorHex: String,
                                            badgeText: String?,
                                            envBackgroundHex: String?) -> String {
    let envbgAssign = envBackgroundHex.map { "envbg=\(shellSingleQuoted($0))\n" } ?? ""
    let envbgCall = envBackgroundHex == nil
        ? ""
        : "[ -n \"$envbg\"    ] && setcolor bg  \"$envbg\"\n"
    let badgeCall = badgeText.map {
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

nonisolated func paneLaunchScript(root: String,
                                  repoPath: String,
                                  tabColorHex: String,
                                  tierCommand: String,
                                  pluginDir: String? = nil,
                                  badgeText: String? = nil,
                                  envBackgroundHex: String? = nil) -> String {
    let pluginFlag = pluginDir.map { "--plugin-dir \(shellSingleQuoted($0)) " } ?? ""
    return paneScriptPreamble(root: root,
                              repoPath: repoPath,
                              tabColorHex: tabColorHex,
                              badgeText: badgeText,
                              envBackgroundHex: envBackgroundHex)
        + "exec claude \(pluginFlag)\(shellSingleQuoted(tierCommand))\n"
}

/// The INDEPENDENT pane: the same prepared environment, an interactive shell
/// instead of a bot run. `$GM_FS_ROOT/bin` is prepended to PATH so `gm_hook`
/// (and a hand-typed `claude`) resolve against this root's staged binaries —
/// a zshrc that RESETS PATH can shadow the prepend, which is cosmetic;
/// GM_FS_ROOT itself survives any rc file.
nonisolated func paneShellScript(root: String,
                                 repoPath: String,
                                 tabColorHex: String,
                                 badgeText: String? = nil,
                                 envBackgroundHex: String? = nil,
                                 shell: String) -> String {
    paneScriptPreamble(root: root,
                       repoPath: repoPath,
                       tabColorHex: tabColorHex,
                       badgeText: badgeText,
                       envBackgroundHex: envBackgroundHex)
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
