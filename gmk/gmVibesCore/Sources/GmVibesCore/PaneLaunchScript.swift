import Foundation
import GmDaemonSdk
import GmITerm2Client

// The PURE half of the pane launch — the one place in this slice where a bug is
// SILENT rather than visible, which is why all of it is here, in functions that
// take values and return strings.
//
// EVERY FUNCTION IN THIS FILE IS `nonisolated`, DELIBERATELY. gmVibesCore
// compiles at `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (see this package's
// Package.swift), so a new file lands MainActor-isolated BY DEFAULT. That is
// right for a view and wrong for a string builder: nothing here touches UI
// state, and pinning it to the main actor would mean the script-writing step
// could not move off it later without a signature change.
//
// WHY A SCRIPT FILE AT ALL — stated here so nobody "simplifies" it back into an
// inline command string. iTerm2's profile `Command` key is ARGV-SPLIT, not
// shell-interpreted: ITAddressBookMgr.m:796 and :814 say "The returned value
// gets parsed into an argument array using -componentsInShellCommand". An inline
// multi-clause command would therefore try to exec a binary named `export` and
// fail invisibly — and because the pane closes on failure, it would look exactly
// like "Play did nothing". This is the AppleScript escaping hazard RELOCATED,
// not escaped.
//
// The script file also puts the per-launch scratch INSIDE the write-containment
// invariant (`Paths.assertContained`), which the Dynamic Profile write is not.

// MARK: - Escaping

/// POSIX single-quote escaping: wrap in `'`, and close/escape/reopen around any
/// embedded `'`. The only quoting rule the script uses, applied to every
/// interpolated value without exception.
nonisolated func shellSingleQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - The script

/// The pane's launch script, in full.
///
/// CLAUSE ORDER IS LOAD-BEARING. Each numbered comment below is a reason, not a
/// description:
///
/// 1. `rm -f "$0"` FIRST — self-delete before anything can fail, so an aborted
///    launch leaves no residue. Nothing accumulates the way the stale
///    `gmvibes-*.json` dynamic profiles have.
/// 2. `cd` is redundant with the profile's Working Directory key ON PURPOSE: it
///    makes the script self-contained, so the degraded no-profile rung still
///    lands in the right repo.
/// 3. `export GM_FS_ROOT` BEFORE `claude`. `gm_hook.sh`, `gm_session_startup.sh`,
///    `run_mcp.sh` and `check_gm_stale.sh` all resolve `${GM_FS_ROOT:-$HOME/gmfs}`;
///    Claude Code inherits the shell environment and the hooks it spawns inherit
///    from Claude, so ONE export covers SessionStart, the pen/MCP server and
///    every PostToolUse write.
/// 4. The colour BEFORE `claude`: once the TUI owns the screen a stray `printf`
///    is noise. The tmux branch is copied from `it2setcolor` — a pane whose login
///    shell auto-attaches tmux SILENTLY EATS an unwrapped escape sequence.
/// 5. `exec` so closing claude closes the pane: the pane IS the claude process.
///
/// All interpolated values go through `shellSingleQuoted`. `tabColorHex` is
/// machine-generated and needs no quoting, but GETS IT ANYWAY (via a variable,
/// so the `printf` format string stays intact) — a uniform rule has no
/// exceptions to forget.
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

// MARK: - The shell

/// The user's login shell, allow-listed.
///
/// Deliberately does NOT return `fish`: the script above is POSIX/zsh and fish
/// would mis-parse it. PATH is the only thing the login shell contributes here,
/// and `/bin/zsh -l` gets it from the standard profile files regardless of what
/// the user's interactive shell is.
nonisolated func loginShellPath() -> String {
    let fallback = "/bin/zsh"
    guard let pw = getpwuid(getuid()), let raw = pw.pointee.pw_shell else { return fallback }
    let shell = String(cString: raw)
    switch (shell as NSString).lastPathComponent {
    case "zsh", "bash", "sh": return shell
    default: return fallback
    }
}

/// The value that goes in the profile's `Command` key.
///
/// Remember this is ARGV-SPLIT by `-componentsInShellCommand`, so it may carry
/// quotes but NOT shell operators. THREE arguments come out:
/// `[<shell>, -l, <scriptPath>]`.
///
/// `-l` is what gives the pane a login PATH, so `claude` resolves. The script is
/// passed as the shell's FILE ARGUMENT rather than through `-c`, so it is read
/// by the shell directly and does not depend on the shebang or on the exec bit
/// having survived — and `$0` is still the script's own path, which is what
/// makes the `rm -f "$0"` self-delete work.
nonisolated func paneCommandLine(shell: String, scriptPath: String) throws(ITerm2Error) -> String {
    // A path carrying either of these cannot be expressed inside the
    // double-quoted argument and must never be smuggled through unchecked.
    guard !scriptPath.contains("\""), !scriptPath.contains("\\") else {
        throw ITerm2Error.unsafeCommandPath(scriptPath)
    }
    guard !shell.contains("\""), !shell.contains("\\") else {
        throw ITerm2Error.unsafeCommandPath(shell)
    }
    return "\(shell) -l \"\(scriptPath)\""
}

// MARK: - Writing it out

/// Writes the launch script under `<root>/tmp/gm_pane/`, which is where it
/// belongs because that is INSIDE the write-containment invariant. The write
/// goes through `Paths.assertContained` before a byte is written, so a root that
/// disagrees with the one this process resolved fails HERE rather than by
/// scattering a file somewhere unexpected.
enum PaneScriptWriter {
    /// Returns the script's URL. The script deletes itself on first line, so
    /// there is no cleanup path and no directory that grows.
    nonisolated static func write(script: String, root: String) throws(ITerm2Error) -> URL {
        let dir = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("gm_pane", isDirectory: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).sh")
        do {
            // BEFORE the write, not after: containment is a precondition.
            try Paths.assertContained(url)
        } catch {
            throw ITerm2Error.unsafeCommandPath(url.path)
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(script.utf8).write(to: url, options: .atomic)
            // Owner-only: the script carries this session's root and command.
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
