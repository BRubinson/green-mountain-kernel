import CryptoKit
import Darwin
import Foundation

// Client-side identity derivation, shared by every DAEMON CLIENT that needs
// the project → instance → session triple or the calling Claude instance's
// key — gmcc_hook and the gmcc_mcp server alike (m0025 moved this here from the
// client's
// Support/ so the MCP server never grows a parallel implementation).

/// A client-context failure (not inside a git repo, detached HEAD, …).
public struct ClientContextError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The CLI gathers the git context (repo root, basename, branch) from the
/// working directory and mirrors gmcc_session_startup.sh's identity
/// conventions (instance code = {repo}_{4-char md5 of abs path}, branch
/// slugified / → __) so db rows line up with the ckfs tree.
public struct GitContext {
    public let repoRoot: String
    public let repoName: String
    public let branch: String

    /// {repo}_{first 4 hex of md5(abs path)} — matches gmcc_session_startup.sh's hash4.
    /// Single Swift home of the convention: InstanceIdentity in the kit
    /// (shared with SandboxRetarget).
    public var instanceCode: String {
        InstanceIdentity.code(repoName: repoName, absolutePath: repoRoot)
    }

    /// Branch with / slugified to __ — matches gmcc_session_startup.sh.
    public var sessionCode: String {
        branch.replacingOccurrences(of: "/", with: "__")
    }

    /// The calling process's own working directory — every interactive client
    /// invocation.
    public static func detect() throws -> GitContext {
        try detect(in: nil)
    }

    /// Identity for a NAMED directory rather than the process's own cwd.
    ///
    /// The hook family is the caller that needs this: a PostToolUse payload
    /// carries the `cwd` the tool call ran in, and that — never the hook
    /// process's inherited working directory — is the repo the change belongs
    /// to. The two differ whenever the hook is launched from somewhere else,
    /// and resolving against the wrong one files a change under another
    /// repo's session.
    public static func detect(in directory: String?) throws -> GitContext {
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

    public init(repoRoot: String, repoName: String, branch: String) {
        self.repoRoot = repoRoot
        self.repoName = repoName
        self.branch = branch
    }

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

public enum CkfsYaml {
    /// `~/gmcc_ckfs/`, or `$GMCC_CKFS_ROOT` when set — same env name the
    /// SessionStart hook already exports, so sandbox sessions redirect the
    /// CLI's yaml reads without a second variable.
    public static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["GMCC_CKFS_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmcc_ckfs", isDirectory: true)
    }()

    /// Extract the first top-level `uuid:` from a ckfs data yaml, if present.
    public static func uuid(_ relativePath: String) -> String? {
        scalar("uuid", relativePath)
    }

    /// Extract the first top-level single-line scalar value for `key:` from a
    /// ckfs data yaml, if present. Block scalars (|, >) are not resolved.
    public static func scalar(_ key: String, _ relativePath: String) -> String? {
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

    /// Strip one layer of surrounding quotes — GMVibes' yaml encoder may quote
    /// scalars, and a literal-quoted code would create a duplicate kbite row.
    static func unquoted(_ value: String) -> String {
        var v = value
        if v.count >= 2,
           (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}

public enum ContextBuilder {
    /// Build the full CONTEXT_ENSURE payload from the working directory's git
    /// identity plus whatever the ckfs tree already knows (uuids). Kbite
    /// registries are db-native — no yaml kbite reads on this path.
    ///
    /// `claudeSessionId` is the SessionStart payload's conversation uuid. It
    /// rides this request rather than a verb of its own, so the binding every
    /// hook write resolves through is created by the same call that creates
    /// the session it points at.
    public static func ensureRequest(claudeSessionId: String? = nil) throws -> ContextEnsureRequest {
        ensureRequest(for: try GitContext.detect(), claudeSessionId: claudeSessionId)
    }

    /// The same payload for an ALREADY-RESOLVED identity — the hook path,
    /// which derives its git context from the payload's cwd and must not
    /// re-derive it from the hook process's own.
    public static func ensureRequest(
        for git: GitContext, claudeSessionId: String? = nil
    ) -> ContextEnsureRequest {
        let projectRel = "projects/\(git.repoName)"
        let instanceRel = "\(projectRel)/instances/\(git.instanceCode)"
        let sessionRel = "\(instanceRel)/sessions/\(git.sessionCode)"
        return ContextEnsureRequest(
            project: ProjectContext(
                gitRepoName: git.repoName,
                code: git.repoName,
                name: git.repoName,
                ckfsRelativeStoragePath: projectRel,
                uuid: CkfsYaml.uuid("\(projectRel)/project_data.gmcc.yaml")
            ),
            instance: InstanceContext(
                code: git.instanceCode,
                name: git.instanceCode,
                absoluteFileSystemPath: git.repoRoot,
                ckfsRelativeStoragePath: instanceRel,
                uuid: CkfsYaml.uuid("\(instanceRel)/instance_data.gmcc.yaml")
            ),
            session: SessionContext(
                code: git.sessionCode,
                name: git.sessionCode,
                ckfsRelativeStoragePath: sessionRel,
                uuid: CkfsYaml.uuid("\(sessionRel)/session_data.gmcc.yaml")
            ),
            claudeSessionId: claudeSessionId
        )
    }

    /// Idempotent resolve: ensure the chain and return the session uuid.
    /// Used by session/prompt subcommands when no --session-uuid is given.
    public static func resolveSessionUuid(_ client: DaemonClient) throws -> String {
        try client.ensureContext(try ensureRequest()).sessionUuid
    }
}

/// The calling Claude Code instance's identity, resolved from process
/// ancestry: walk parents until the nearest `claude` process and key on its
/// pid + start time (start time defeats pid reuse). Every process a Claude
/// instance spawns — Bash tool commands, hook scripts, Task subagents — is a
/// descendant of that instance, so they all resolve the SAME key, while a
/// second Claude instance running a different prompt on the same GMCC session
/// resolves a different one. That is what lets the daemon's activation
/// registry keep several prompts active per session without last-writer-wins
/// clobbering, and what makes a spawned agent's briefing lookup
/// deterministic (no uuid has to survive a spawn prompt).
///
/// nil when no claude ancestor exists (a bare terminal running gmcc_hook by hand):
/// callers omit the key and the daemon falls back to the session's single
/// activation when unambiguous.
public enum ClientKey {
    public static func resolve() -> String? {
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

    private static func procInfo(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard rc == 0, size > 0 else { return nil }
        return info
    }
}
