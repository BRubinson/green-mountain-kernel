import Foundation

/// The repo-relative path normalizer, in the BASE layer because it is purely
/// lexical and Foundation-only: it touches no database and no filesystem, so
/// nothing about it is persistence. A second copy of a join key's normalizer
/// is how two writers start disagreeing about the same string, so `StoreCore`
/// and `Store` keep thin forwarders rather than their own.
public enum RepoRelativePath {

    /// The join key contract: architecture change rows and file_change rows
    /// meet on this string, so both write paths run through this normalizer.
    /// Purely lexical — it NEVER touches the filesystem, since instance roots
    /// name paths that are gone and architecture rows name files not yet
    /// created. A relative path passes through cleaned, an absolute path inside
    /// the instance root is stripped, and one outside it is rejected.
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
                    detail: "path is not inside the instance root (\(repoRoot)): \(raw)"
                )
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
