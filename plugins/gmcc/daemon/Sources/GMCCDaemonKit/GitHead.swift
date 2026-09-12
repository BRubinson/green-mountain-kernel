import Foundation

/// Pure .git/HEAD resolution — item 2's core, shared by SESSION_RESOLVE and
/// INSTANCE_CURRENT_SESSION. No subprocess, no git library: HEAD is a tiny
/// text file (21–37 bytes for a symbolic ref; 41 detached — never assume a
/// fixed size, always read the whole file).
///
/// Failure discipline: a missing or unreadable repo path is COMMON (live
/// instance rows point at paths that no longer exist) and must resolve to
/// .unavailable, never throw — these reads run on the daemon's serial queue.
public enum GitHead {
    public enum State: Sendable, Equatable {
        /// HEAD is a symbolic ref; associated value is the bare branch name
        /// (e.g. "feature/nested-slash").
        case branch(String)
        /// HEAD is a bare commit sha — nothing is "checked out" session-wise.
        case detached
        /// No repo / unreadable / gone.
        case unavailable
    }

    /// Slug a branch name to a session code — forward-only (the mapping is
    /// lossy: never attempt to un-slug a code back into a branch). Exactly
    /// the GitContext.sessionCode rule: / → __, nothing else.
    public static func sessionCode(forBranch branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "__")
    }

    /// The directory holding HEAD for `repoRoot` — `<root>/.git` normally, or
    /// the followed `gitdir:` target for worktrees and submodules. nil when
    /// absent or unreadable (COMMON: instance rows point at paths that no
    /// longer exist). Exposed so the checkout watcher and the resolver agree
    /// on the path by construction rather than by parallel implementation.
    public static func gitDirectory(repoRoot: String) -> String? {
        let gitPath = repoRoot + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return gitPath
        }
        // .git is a FILE: "gitdir: <path>". Follow one level.
        guard let content = readSmallFile(gitPath),
              content.hasPrefix("gitdir:") else {
            return nil
        }
        var gitdir = String(content.dropFirst("gitdir:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !gitdir.hasPrefix("/") {
            gitdir = repoRoot + "/" + gitdir
        }
        return gitdir
    }

    /// Resolve the checked-out state of the repo at `repoRoot`.
    /// Handles the `.git`-as-file `gitdir:` indirection (worktrees emit an
    /// absolute gitdir, submodules a relative one — both resolved against the
    /// containing directory).
    public static func resolve(repoRoot: String) -> State {
        guard let gitdir = gitDirectory(repoRoot: repoRoot),
              let head = readSmallFile(gitdir + "/HEAD") else {
            return .unavailable
        }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: ") {
            let ref = String(line.dropFirst("ref: ".count))
            if ref.hasPrefix("refs/heads/") {
                return .branch(String(ref.dropFirst("refs/heads/".count)))
            }
            return .detached
        }
        // Anything that isn't a symbolic ref (a bare sha) is detached.
        return line.isEmpty ? .unavailable : .detached
    }

    /// Whole-file read with a hard cap and O_NONBLOCK — never a fixed-size
    /// read (the common symbolic ref is 21–37 bytes, not 41), never a blocking
    /// read on a surprising path (FIFO, unreachable mount).
    private static func readSmallFile(_ path: String, cap: Int = 4096) -> String? {
        let fd = open(path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: cap)
        let count = read(fd, &buffer, cap)
        guard count > 0 else { return nil }
        return String(bytes: buffer[0..<count], encoding: .utf8)
    }
}
