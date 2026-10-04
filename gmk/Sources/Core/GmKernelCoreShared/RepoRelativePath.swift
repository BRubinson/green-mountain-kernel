import Foundation

/// The repo-relative path normalizer, in the BASE layer because it is purely
/// lexical and Foundation-only: it touches no database and no filesystem, so
/// nothing about it is persistence.
///
/// A second copy of a join key's normalizer is how two writers start disagreeing about the same string, so `StoreCore`
/// and `Store` keep thin forwarders rather than their own.
enum RepoRelativePath {

    /// Normalizes a path to a repository-relative form.
    ///
    /// The join key for architecture and file change rows; both write paths
    /// run through this normalizer. Purely lexical — never touches the
    /// filesystem since instance roots name paths that are gone or files not
    /// yet created. Relative paths are cleaned, absolute paths inside the
    /// root are stripped to relative, and those outside are rejected.
    ///
    /// - Parameters:
    ///   - raw: The path to normalize.
    ///   - repoRoot: The instance root path for stripping absolute paths.
    /// - Returns: The normalized repository-relative path.
    /// - Throws: `StoreError.badRequest` if the path is empty, contains control
    ///   characters, escapes the repo root, or resolves to the root itself.
    static func normalizeRepoRelativePath(_ raw: String, repoRoot: String) throws -> String {
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
