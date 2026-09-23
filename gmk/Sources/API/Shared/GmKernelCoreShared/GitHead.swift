import Foundation

/// Pure .git/HEAD resolution, shared by SESSION_RESOLVE and
/// INSTANCE_CURRENT_SESSION.
///
/// No subprocess, no git library: HEAD is a tiny text file, and its size
/// varies, so always read the whole of it. A missing or unreadable repo path
/// is COMMON — live instance rows point at paths that are gone — and must
/// resolve to .unavailable, never throw, since these reads run on the daemon's
/// serial queue.
enum GitHead {
    enum State: Sendable, Equatable {
        /// HEAD is a symbolic ref; associated value is the bare branch name
        /// (e.g. "feature/nested-slash").
        case branch(String)
        /// HEAD is a bare commit sha — nothing is "checked out" session-wise.
        case detached
        /// No repo / unreadable / gone.
        case unavailable
    }

    /// Converts a branch name to a session code.
    ///
    /// The mapping is lossy and forward-only; never attempt to un-slug a code
    /// back into a branch. Exactly the GitContext.sessionCode rule: forward slash
    /// (`/`) is replaced with double underscore (`__`); nothing else is changed.
    ///
    /// - Parameter branch: The branch name to convert.
    /// - Returns: The session code.
    static func sessionCode(forBranch branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "__")
    }

    /// Returns the `.git` directory for a repository.
    ///
    /// Usually `<root>/.git`, but follows the `gitdir:` target for worktrees
    /// and submodules. Returns `nil` when the directory is absent or unreadable,
    /// which is common when instance rows point at paths that are gone. This is
    /// exposed so the checkout watcher and the resolver can agree on the path by
    /// construction rather than by parallel implementation.
    ///
    /// - Parameter repoRoot: The repository root path.
    /// - Returns: The `.git` directory path, or `nil` if not found or unreadable.
    static func gitDirectory(repoRoot: String) -> String? {
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
            content.hasPrefix("gitdir:")
        else {
            return nil
        }
        var gitdir = String(content.dropFirst("gitdir:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !gitdir.hasPrefix("/") {
            gitdir = repoRoot + "/" + gitdir
        }
        return gitdir
    }

    /// Resolves the checked-out state of a repository.
    ///
    /// Handles the `.git`-as-file `gitdir:` indirection where worktrees emit an
    /// absolute gitdir and submodules emit a relative one, both resolved against
    /// the containing directory.
    ///
    /// - Parameter repoRoot: The repository root path.
    /// - Returns: The checked-out state of the repository.
    static func resolve(repoRoot: String) -> State {
        guard let gitdir = gitDirectory(repoRoot: repoRoot),
            let head = readSmallFile(gitdir + "/HEAD")
        else {
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

    /// Reads a small file with a cap and non-blocking I/O.
    ///
    /// Never performs a fixed-size read (the common symbolic ref is 21–37 bytes,
    /// not 41), and never blocks on a surprising path such as a FIFO or
    /// unreachable mount.
    ///
    /// - Parameters:
    ///   - path: The file path to read.
    ///   - cap: The maximum number of bytes to read, defaulting to 4096.
    /// - Returns: The file contents as a string, or `nil` if read fails.
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
