import Foundation
import GRDB

// SESSION_RESOLVE / INSTANCE_CURRENT_SESSION — git-derived checked-out state
// (item 2). Runs ON the serial queue deliberately: a HEAD read is a sub-100-
// byte local file read guarded by O_NONBLOCK + a 4KB cap (GitHead), and a
// missing instance path fails instantly to .unavailable — no lane needed.
// Resolution is forward-only: slug HEAD's branch (/ → __) and compare to
// session.code; the mapping is lossy, so codes are never un-slugged.
//
// Bodies live in GitStateRepository; these wrappers own the transaction.

extension Store {
    /// Resolves a session against the checked-out git state.
    /// - Parameter req: The session resolve request.
    /// - Returns: The resolved session response with git state binding.
    /// - Throws: Errors from database operations or git state resolution.
    func sessionResolve(_ req: SessionResolveRequest) throws -> SessionResolveResponse {
        try boundaryRead { db in try GitStateRepository(db: db, core: core).sessionResolve(req) }
    }

    /// Gets the current session for an instance's checked-out git state.
    /// - Parameter req: The instance current session request.
    /// - Returns: The response with the current session information.
    /// - Throws: Errors from database operations or git state resolution.
    func instanceCurrentSession(
        _ req: InstanceCurrentSessionRequest
    ) throws -> InstanceCurrentSessionResponse {
        try boundaryRead { db in
            try GitStateRepository(db: db, core: core).instanceCurrentSession(req)
        }
    }

    /// Returns the current git HEAD state summary for a repository.
    ///
    /// The ONE head resolver — shared by the poll responses and the
    /// CHECKOUT_CHANGE broadcast path (server module), so the push event and
    /// the poll responses can never disagree about what is checked out.
    /// `branch` is the RAW branch name, nil unless state == "branch".
    /// - Parameter repoRoot: The path to the repository root.
    /// - Returns: A tuple of (state, code, branch) describing the HEAD state.
    static func headSummary(repoRoot: String) -> (state: String, code: String?, branch: String?) {
        guard !repoRoot.isEmpty else { return ("unavailable", nil, nil) }
        switch GitHead.resolve(repoRoot: repoRoot) {
        case .branch(let branch):
            return ("branch", GitHead.sessionCode(forBranch: branch), branch)
        case .detached:
            return ("detached", nil, nil)
        case .unavailable:
            return ("unavailable", nil, nil)
        }
    }
}
