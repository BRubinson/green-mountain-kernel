import Foundation

/// Filesystem derivations off daemon rows, isolated in one place. Rows carry gmfs-RELATIVE
/// storage paths; everything here resolves against $GM_FS_ROOT. The archive mirror lives at
/// `_archive/cold_storage/<same relative path>` and is probed at the PROMPT-folder level,
/// because that is the granularity archiving works at.
///
/// Every function performs synchronous FileManager probes: resolve off the main actor and
/// cache the result, never call from a View body.
nonisolated enum GmFsPathResolver {
    /// The folder-segment slug rule, shared with prompt codes.
    ///
    /// This is NOT the session-code rule: `session.code` folds only `/` → `__`, with no case
    /// or punctuation folding, and INSTANCE_CURRENT_SESSION returns the authoritative code.
    /// Never compare a branch against this slug — it folds aggressively, so `Feature/Login`
    /// would silently never match its session.
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

    private static func archiveMirror(relative: String, gmFsRoot: String) -> URL {
        URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent("_archive/cold_storage", isDirectory: true)
            .appendingPathComponent(relative, isDirectory: true)
    }

    /// Resolve a gmfs-relative path, falling back to the archive mirror when
    /// the live location is gone. Returns the live URL when neither exists
    /// (callers render empty states off a missing directory).
    static func resolve(relative: String, gmFsRoot: String) -> URL {
        let live = URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent(relative, isDirectory: true)
        if FileManager.default.fileExists(atPath: live.path) { return live }
        let archived = archiveMirror(relative: relative, gmFsRoot: gmFsRoot)
        if FileManager.default.fileExists(atPath: archived.path) { return archived }
        return live
    }

    static func sessionDir(gmFsRoot: String, session: SessionStub) -> URL {
        URL(fileURLWithPath: gmFsRoot, isDirectory: true)
            .appendingPathComponent(session.gmfsRelativeStoragePath, isDirectory: true)
    }

    /// A prompt's folder, or nil when it has no filesystem presence. The
    /// row's `gmfs_relative_storage_path` is the ONLY source (probed live,
    /// then in the archive mirror — archiving moves prompt folders, leaving
    /// the session dir live with an emptied prompts/). There is NO folder
    /// guessing: a guessed `<seq>_*` folder can collide with a stranger's
    /// files, so an empty path renders a non-blocking unavailable state
    /// instead.
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
        /// directory PROMPT_MEMORY_CHANGED describes. The artifact-common-
        /// ancestor rule can legitimately land elsewhere, and the event would
        /// never describe that directory: only this flag may switch the
        /// explorer from polling to event-driven refresh.
        let isDaemonWatched: Bool
    }

    /// Memory root for a prompt, in priority order:
    /// 1. Deepest common ancestor of the prompt's registered artifact files
    ///    that exists on disk — db-driven (the rows say where the files are).
    /// 2. The storage-path folder's memory/ subdirectory.
    /// Root is nil when neither resolves.
    static func memoryRoot(
        gmFsRoot: String,
        storagePath: String = "",
        artifacts: [ArtifactRow]
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
