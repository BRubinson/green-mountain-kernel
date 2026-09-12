import Foundation

/// Boot-side wrapper for BASE_PROJECT promotion.
///
/// Shaped exactly like DopeBootSync, and for the same reason: it rides the
/// SessionStart path, so EVERY outcome is non-throwing. "Boot must never
/// block on a domain model" extends verbatim to publishing one.
///
/// Runs immediately after DopeBootSync.run inside CONTEXT_ENSURE, so the
/// files -> db reconcile happens first and promotion publishes whatever that
/// settled on.
public enum DopePromotion {
    public enum Outcome {
        /// The session is not on the project's primary branch — the common,
        /// silent case.
        case notPrimaryBranch(detail: String)
        case nothingToPublish
        case upToDate
        case promoted([DopePromotedScope])
        /// Daemon unreachable or a refusal. A warning, never a blocked boot.
        case unreachable(String)
    }

    public static func run(client: DaemonClient, sessionUuid: String) -> Outcome {
        do {
            let response = try client.dopePromote(DopePromoteRequest(sessionUuid: sessionUuid))
            if !response.promoted.isEmpty { return .promoted(response.promoted) }
            switch response.skipped {
            case "branch_mismatch": return .notPrimaryBranch(detail: response.detail ?? "")
            case "no_session_scope": return .nothingToPublish
            default: return .upToDate
            }
        } catch {
            return .unreachable(String(describing: error))
        }
    }

    /// One human line for hook output; nil for the silent outcomes.
    public static func notice(for outcome: Outcome) -> String? {
        switch outcome {
        case .notPrimaryBranch, .nothingToPublish, .upToDate:
            return nil
        case let .promoted(scopes):
            let parts = scopes.map { "'\($0.code)' -> revision \($0.toRevision)" }
            return "[GMB] dope: promoted to BASE_PROJECT: " + parts.joined(separator: ", ")
        case let .unreachable(reason):
            return "[GMB] dope: WARN — promotion skipped: \(reason) "
                + "(inspect with: gmcc_hook call DOPE_PROMOTE --json "
                + "'{\"session_uuid\":\"<uuid>\",\"dry_run\":true}')"
        }
    }
}
