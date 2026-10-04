import CryptoKit
import Darwin
import Foundation

// Client-side identity derivation, shared by every DAEMON CLIENT that needs
// the project → instance → session triple or the calling Claude instance's
// key — gm_hook and the gm_mcp server alike (m0025 moved this here from the
// client's
// Support/ so the MCP server never grows a parallel implementation).

/// A client-context failure (not inside a git repo, detached HEAD, …).
struct ClientContextError: Error, LocalizedError {
    let message: String
    /// Creates a client context error with the given message.
    /// - Parameter message: A description of the error condition.
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The CLI gathers the git context (repo root, basename, branch) from the
/// working directory and mirrors gm_session_startup.sh's identity
/// conventions (instance code = {repo}_{4-char md5 of abs path}, branch
/// slugified / → __) so db rows line up with the gmfs tree.
struct GitContext {
    let repoRoot: String
    let repoName: String
    let branch: String

    /// {repo}_{first 4 hex of md5(abs path)} — matches gm_session_startup.sh's hash4.
    /// Single Swift home of the convention: InstanceIdentity in the kit
    var instanceCode: String {
        InstanceIdentity.code(repoName: repoName, absolutePath: repoRoot)
    }

    /// Branch with / slugified to __ — matches gm_session_startup.sh.
    var sessionCode: String {
        branch.replacingOccurrences(of: "/", with: "__")
    }

    /// Detects git context from the process's working directory.
    /// - Returns: A git context with repo root, name, and branch.
    /// - Throws: `ClientContextError` if not in a git repo or HEAD is detached.
    static func detect() throws -> GitContext {
        try detect(in: nil)
    }

    /// Detects git context from a named directory.
    ///
    /// Hooks use this to derive context from the tool call's working
    /// directory rather than the hook process's own, ensuring changes are
    /// filed under the correct repo's session.
    /// - Parameter directory: The directory to detect context in, or nil for
    ///   the process's own working directory.
    /// - Returns: A git context with repo root, name, and branch.
    /// - Throws: `ClientContextError` if not in a git repo or HEAD is detached.
    static func detect(in directory: String?) throws -> GitContext {
        let at = directory.map { ["-C", $0] } ?? []
        guard let repoRoot = runGit(at + ["rev-parse", "--show-toplevel"]) else {
            throw ClientContextError("not inside a git repository — a GMCC client needs git context")
        }
        // Detached HEAD prints nothing here. Fail loudly instead of falling
        // back to "main": the daemon-side SESSION_RESOLVE reports detached as
        // "nothing checked out", and a silent main fallback would have the client
        // writing into the main session while the daemon disagrees.
        guard let branch = runGit(at + ["branch", "--show-current"]), !branch.isEmpty else {
            throw ClientContextError("HEAD is detached — a GMCC client needs a checked-out branch for session context")
        }
        return GitContext(
            repoRoot: repoRoot,
            repoName: URL(fileURLWithPath: repoRoot).lastPathComponent,
            branch: branch
        )
    }

    /// Creates a git context with the given values.
    /// - Parameters:
    ///   - repoRoot: The absolute path to the repo root.
    ///   - repoName: The repo name (basename of the root path).
    ///   - branch: The current branch name.
    init(repoRoot: String, repoName: String, branch: String) {
        self.repoRoot = repoRoot
        self.repoName = repoName
        self.branch = branch
    }

    /// Runs a git command and returns trimmed output.
    /// - Parameter arguments: The git command arguments.
    /// - Returns: The command output trimmed of whitespace, or nil on failure.
    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }
}

enum GmFsYaml {
    /// The content root — `Paths.contentRoot`, never a second resolution of it.
    ///
    /// Write containment is a prefix test against ONE root, and two roots that
    /// are "always equal" are two roots that can disagree.
    static var root: URL { Paths.contentRoot }

    /// Extracts the first top-level `uuid:` value from a gmfs data yaml.
    /// - Parameter relativePath: The relative path to the yaml file in gmfs.
    /// - Returns: The uuid value, or nil if not present.
    static func uuid(_ relativePath: String) -> String? {
        scalar("uuid", relativePath)
    }

    /// Extracts the first top-level scalar value for a key.
    ///
    /// Block scalars (|, >) are not resolved.
    /// - Parameters:
    ///   - key: The yaml key to extract the value for.
    ///   - relativePath: The relative path to the yaml file in gmfs.
    /// - Returns: The scalar value, or nil if not present.
    static func scalar(_ key: String, _ relativePath: String) -> String? {
        guard let text = try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8) else {
            return nil
        }
        let prefix = "\(key): "
        for line in text.split(separator: "\n") {
            if line.hasPrefix(prefix) {
                let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Removes one layer of surrounding quotes from a value.
    ///
    /// GMVibes' yaml encoder may quote scalars, and a literal-quoted code
    /// would create a duplicate kbite row.
    /// - Parameter value: A string that may be quoted.
    /// - Returns: The string with outer quotes removed, or unchanged if not
    ///   quoted.
    static func unquoted(_ value: String) -> String {
        var v = value
        if v.count >= 2,
            (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'"))
        {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}

enum ContextBuilder {
    /// Builds a CONTEXT_ENSURE payload from the process's git identity.
    ///
    /// Kbite registries are db-native with no yaml kbite reads on this path.
    /// The `claudeSessionId` is the SessionStart payload's conversation uuid,
    /// bound by the same call that creates the session it points at.
    /// - Parameter claudeSessionId: The Claude session id, or nil for none.
    /// - Returns: A context ensure request with project, instance, and session.
    /// - Throws: `ClientContextError` if not in a git repo or HEAD is detached.
    static func ensureRequest(claudeSessionId: String? = nil) throws -> ContextEnsureRequest {
        ensureRequest(for: try GitContext.detect(), claudeSessionId: claudeSessionId)
    }

    /// Builds a CONTEXT_ENSURE payload for an already-resolved git identity.
    ///
    /// The hook path uses this when the payload's cwd is available and must
    /// not re-derive context from the hook process's own working directory.
    /// - Parameters:
    ///   - git: The git context to build the payload for.
    ///   - claudeSessionId: The Claude session id, or nil for none.
    /// - Returns: A context ensure request with project, instance, and session.
    static func ensureRequest(
        for git: GitContext,
        claudeSessionId: String? = nil
    ) -> ContextEnsureRequest {
        let projectRel = "projects/\(git.repoName)"
        let instanceRel = "\(projectRel)/instances/\(git.instanceCode)"
        let sessionRel = "\(instanceRel)/sessions/\(git.sessionCode)"
        return ContextEnsureRequest(
            project: ProjectContext(
                gitRepoName: git.repoName,
                code: git.repoName,
                name: git.repoName,
                gmfsRelativeStoragePath: projectRel,
                uuid: GmFsYaml.uuid("\(projectRel)/project_data.gmcc.yaml")
            ),
            instance: InstanceContext(
                code: git.instanceCode,
                name: git.instanceCode,
                absoluteFileSystemPath: git.repoRoot,
                gmfsRelativeStoragePath: instanceRel,
                uuid: GmFsYaml.uuid("\(instanceRel)/instance_data.gmcc.yaml")
            ),
            session: SessionContext(
                code: git.sessionCode,
                name: git.sessionCode,
                gmfsRelativeStoragePath: sessionRel,
                uuid: GmFsYaml.uuid("\(sessionRel)/session_data.gmcc.yaml")
            ),
            claudeSessionId: claudeSessionId
        )
    }

    /// Ensures the context chain and returns the session UUID.
    ///
    /// Used by session/prompt subcommands when no --session-uuid is given.
    /// - Parameter client: A verb caller with the ensureContext method.
    /// - Returns: The session UUID from the context ensure response.
    /// - Throws: `ClientContextError` if not in a git repo or HEAD is detached.
    static func resolveSessionUuid(_ client: any GmVerbCaller) throws -> String {
        try client.ensureContext(try ensureRequest()).sessionUuid
    }
}

/// The calling Claude Code instance's identity, resolved from process
/// ancestry: walk parents to the nearest `claude` process and key on its pid
/// plus start time, which defeats pid reuse.
///
/// Everything spawned by this instance resolves the SAME key, allowing multiple
/// active prompts per session without last-writer-wins clobbering. nil when no
/// claude ancestor exists; omit the key and fall back to session-single activation.
enum ClientKey {
    /// Resolves the Claude Code instance key from process ancestry.
    ///
    /// Returns a key based on the nearest `claude` process pid and start
    /// time, allowing multiple active prompts per session without clobbering.
    /// - Returns: A key in the format `claude:<pid>:<start_time>`, or nil if
    ///   no Claude ancestor exists.
    static func resolve() -> String? {
        var pid = getpid()
        var hops = 0
        while pid > 1, hops < 64 {
            guard let info = procInfo(pid) else { return nil }
            var proc = info.kp_proc
            let comm = withUnsafeBytes(of: &proc.p_comm) { raw -> String in
                guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
                return String(cString: base)
            }
            if comm.lowercased().hasPrefix("claude") {
                return "claude:\(pid):\(proc.p_starttime.tv_sec)"
            }
            pid = info.kp_eproc.e_ppid
            hops += 1
        }
        return nil
    }

    /// Gets process information for a process ID.
    /// - Parameter pid: The process ID.
    /// - Returns: A kinfo_proc structure with process info, or nil on failure.
    private static func procInfo(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard rc == 0, size > 0 else { return nil }
        return info
    }
}
