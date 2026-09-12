import Foundation

/// The repo-relative path normalizer, in the BASE layer.
///
/// MOVED DOWN out of `StoreCore` rather than made `public` there. It lives here
/// for the same reason `StoreError` does: it is misfiled in a persistence
/// target. It is purely lexical, Foundation-only, touches no database and no
/// filesystem — nothing about it is persistence. Keeping it in the middle layer
/// would have meant either widening a persistence internal to satisfy a
/// base-layer test, or duplicating the normalizer, and a second copy of a join
/// key's normalizer is how two writers start disagreeing about the same string.
///
/// `StoreCore` and `Store` keep thin forwarders, so no call site changed.
public enum RepoRelativePath {

    /// The comparison feature's join key contract: architecture change rows
    /// and file_change rows meet on this string, so both write paths run
    /// through this one normalizer. Purely lexical — NEVER touches the
    /// filesystem (live instance roots include paths that no longer exist,
    /// and architecture rows name files that don't exist yet).
    ///
    /// Relative paths are anchored by definition and pass through cleaned; an
    /// absolute path inside the instance root is stripped to repo-relative;
    /// an absolute path outside it is rejected (honest failure over a
    /// silently zero-match join).
    public static func normalizeRepoRelativePath(_ raw: String, repoRoot: String) throws -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw StoreError.badRequest(detail: "file path is empty")
        }
        guard !path.contains("\0"), !path.contains("\n") else {
            throw StoreError.badRequest(detail: "file path contains control characters")
        }
        if path.hasPrefix("~/") {
            path = NSHomeDirectory() + String(path.dropFirst(1))
        }
        if path.hasPrefix("/") {
            var root = repoRoot
            while root.hasSuffix("/") { root = String(root.dropLast()) }
            guard root.count > 1, path == root || path.hasPrefix(root + "/") else {
                throw StoreError.badRequest(
                    detail: "path is not inside the instance root (\(repoRoot)): \(raw)")
            }
            path = String(path.dropFirst(root.count))
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        }
        while path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        let segments = path.split(separator: "/")
        guard !segments.contains("..") else {
            throw StoreError.badRequest(detail: "path escapes the repo root: \(raw)")
        }
        guard !path.isEmpty, path != "/" else {
            throw StoreError.badRequest(detail: "path resolves to the repo root: \(raw)")
        }
        return path
    }
}
