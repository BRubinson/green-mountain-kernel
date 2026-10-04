import Foundation

/// Filesystem derivations off daemon rows, isolated in one place.
///
/// Rows carry gmfs-RELATIVE storage paths, resolved against $GM_FS_ROOT; archive mirror at
/// `_archive/cold_storage/<same relative path>`, probed at PROMPT-folder level (archiving granularity).
/// Synchronous FileManager probes—resolve off main actor and cache result; never call from View body.
nonisolated enum GmFsPathResolver {
    /// Returns a folder-segment slug, shared with prompt codes.
    ///
    /// Folds case, slashes, and punctuation. Not the session-code rule: `session.code` folds only
    /// `/` → `__`. Never compare a branch against this slug; it folds aggressively.
    ///
    /// - Parameter name: The original folder name.
    /// - Returns: A slug with lowercase letters, digits, hyphens, and underscores only.
    static func slug(_ name: String) -> String {
        let lower = name.lowercased()
        var out = ""
        var lastWasSep = false
        for ch in lower {
            if ch == "/" {
                out += "__"; lastWasSep = false
            } else if ch.isLetter || ch.isNumber || ch == "-" {
                out.append(ch); lastWasSep = false
            } else {
                if !lastWasSep && !out.isEmpty { out.append("_") }; lastWasSep = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        while out.hasPrefix("_") { out.removeFirst() }
        return out
    }

    /// Returns the archive mirror URL for a gmfs-relative storage path.
    ///
    /// - Parameters:
    ///   - relative: The gmfs-relative storage path.
    ///   - gmFsRoot: The filesystem root directory.
    /// - Returns: A URL to the cold storage mirror location.
    private static func archiveMirror(relative: String, gmFsRoot: String) -> URL {
        URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent("_archive/cold_storage", isDirectory: true)
            .appendingPathComponent(relative, isDirectory: true)
    }

    /// Resolves a gmfs-relative path, falling back to archive when live is gone.
    ///
    /// Returns the live URL when neither exists; callers render empty states for missing directories.
    ///
    /// - Parameters:
    ///   - relative: The gmfs-relative storage path.
    ///   - gmFsRoot: The filesystem root directory.
    /// - Returns: The live URL, archive mirror, or live when both missing.
    static func resolve(relative: String, gmFsRoot: String) -> URL {
        let live = URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent(relative, isDirectory: true)
        if FileManager.default.fileExists(atPath: live.path) { return live }
        let archived = archiveMirror(relative: relative, gmFsRoot: gmFsRoot)
        if FileManager.default.fileExists(atPath: archived.path) { return archived }
        return live
    }

    /// Returns the session directory URL for a given root and session stub.
    ///
    /// - Parameters:
    ///   - gmFsRoot: The filesystem root directory.
    ///   - session: The session stub with storage path information.
    /// - Returns: The session directory URL.
    static func sessionDir(gmFsRoot: String, session: SessionStub) -> URL {
        URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent(session.gmfsRelativeStoragePath, isDirectory: true)
    }

    /// Returns a prompt's folder, or nil when it has no filesystem presence.
    ///
    /// The row's `gmfs_relative_storage_path` is the ONLY source, probed live then in archive.
    /// There is no folder guessing; an empty path renders unavailable.
    ///
    /// - Parameters:
    ///   - gmFsRoot: The filesystem root directory.
    ///   - storagePath: The prompt's gmfs-relative storage path, or empty if absent.
    /// - Returns: The prompt folder URL, or nil if not found.
    static func promptFolder(gmFsRoot: String, storagePath: String) -> URL? {
        guard !storagePath.isEmpty else { return nil }
        let live = URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent(storagePath, isDirectory: true)
        if FileManager.default.fileExists(atPath: live.path) { return live }
        let archived = archiveMirror(relative: storagePath, gmFsRoot: gmFsRoot)
        if FileManager.default.fileExists(atPath: archived.path) { return archived }
        return nil
    }

    /// A resolved memory root plus whether it is the exact directory the
    /// daemon's MemoryWatcher resolves against.
    struct ResolvedMemory: Equatable, Sendable {
        let root: URL?
        /// True only when `root` IS `<gmFsRoot>/<storagePath>/memory` — the
        /// directory PROMPT_MEMORY_CHANGED describes.
        ///
        /// The artifact-common-ancestor rule can legitimately land elsewhere, and
        /// the event would never describe that directory: only this flag may
        /// switch the explorer from polling to event-driven refresh.
        let isDaemonWatched: Bool
    }

    /// Returns the memory root for a prompt, resolved in priority order.
    ///
    /// Priority 1: Deepest common ancestor of artifact files (db-driven). Priority 2: The
    /// storage-path folder's memory/ subdirectory. Root is nil when neither resolves.
    ///
    /// - Parameters:
    ///   - gmFsRoot: The filesystem root directory.
    ///   - artifacts: The prompt's registered artifact rows.
    ///   - storagePath: The prompt's gmfs-relative storage path, or empty if absent.
    /// - Returns: A ResolvedMemory with the root URL and daemon-watched flag.
    static func memoryRoot(
        gmFsRoot: String,
        artifacts: [ArtifactRow],
        storagePath: String = ""
    ) -> ResolvedMemory {
        let watched: URL? =
            storagePath.isEmpty
            ? nil
            : URL(fileURLWithPath: gmFsRoot, isDirectory: true)
                .appendingPathComponent(storagePath, isDirectory: true)
                .appendingPathComponent("memory", isDirectory: true)
        func wrap(_ root: URL?) -> ResolvedMemory {
            ResolvedMemory(
                root: root,
                isDaemonWatched: root != nil && watched != nil
                    && root!.standardizedFileURL.path == watched!.standardizedFileURL.path
            )
        }
        let parents = artifacts.compactMap { artifact -> URL? in
            let path = artifact.filePath
            let fileURL: URL =
                path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: gmFsRoot, isDirectory: true).appendingPathComponent(path)
            let parent = fileURL.deletingLastPathComponent()
            return FileManager.default.fileExists(atPath: parent.path) ? parent : nil
        }
        if var common = parents.first {
            for parent in parents.dropFirst() {
                while common.path != "/" && parent.path != common.path
                    && !parent.path.hasPrefix(common.path + "/")
                {
                    common.deleteLastPathComponent()
                }
            }
            if common.path != "/" { return wrap(common) }
        }
        let folder = promptFolder(gmFsRoot: gmFsRoot, storagePath: storagePath)
        return wrap(folder.map { $0.appendingPathComponent("memory", isDirectory: true) })
    }
}
