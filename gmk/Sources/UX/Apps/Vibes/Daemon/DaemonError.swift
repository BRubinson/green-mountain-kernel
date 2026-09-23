import Foundation

/// App-facing typed error surface for errors from the in-process Store.
///
/// Views and stores branch on these cases — never on message text — per the kernel's typed-code contract.
nonisolated enum DaemonError: Error, Equatable {
    /// Binary absent at `Paths.binDaemon` — the RESOLVED root's `bin/gm_daemon`,
    /// which is `~/gmfs` only for production. Distinct from a stopped daemon.
    case notInstalled
    /// Socket dead and autostart disabled (or autostart exhausted its retries).
    case unreachable(String)
    /// Daemon is newer than our linked GmDaemonSdk — rebuild GMVibes /
    /// update the package. Starting the daemon cannot fix this state.
    case clientTooOld(daemonVersion: Int)
    /// Daemon reported an older protocol and the kit's respawn cycle still
    /// failed to retire it.
    case daemonTooOld(daemonVersion: Int?, message: String)
    /// The uuid itself is unknown to the db — as of wire v8 ALWAYS a real
    /// failure, never "no summary yet" (that is `summaryAbsent`).
    case notFound
    /// The prompt exists but that summary was never opened — the normal
    /// pre-phase state, never a failure.
    case summaryAbsent
    case versionConflict
    /// Illegal status edge OR an unmet daemon-side gate (they share one wire
    /// code). The daemon's reason string is preserved — it names which gate
    /// blocked ("clarification summary must be complete", …).
    case invalidTransition(reason: String?)
    case contentLocked
    /// Any other server-reported code (BAD_REQUEST, DB_ERROR, …) — surfaced
    /// verbatim so e.g. a schema re-baseline DB_ERROR stays diagnosable.
    case server(code: String, message: String)
    /// Wire-level encode/decode/socket failure.
    case transport(String)

    /// The single user-facing description.
    ///
    /// Screens that need context-specific wording (e.g. search) may special-case a few cases and fall back here.
    var userMessage: String {
        switch self {
        case .notInstalled: return "Daemon not installed (run install_gm.sh)."
        case .unreachable(let m): return m
        case .clientTooOld(let v): return "Daemon (wire v\(v)) is newer than this app — rebuild GMVibes."
        case .daemonTooOld(_, let m): return m
        case .notFound: return "Not in the GMCC database — the uuid is unknown."
        case .summaryAbsent:
            return "Not opened yet — run the bot to start this phase."
        case .versionConflict: return "Edited elsewhere — reload to continue."
        case .invalidTransition(let reason): return reason ?? "That status change isn't allowed."
        case .contentLocked: return "Content is locked."
        case .server(let code, let message): return "\(code): \(message)"
        case .transport(let m): return m
        }
    }

    /// Converts any error from the in-process Store to a daemon error.
    ///
    /// Codes not given their own case keep the wire code the kernel would send for them.
    ///
    /// - Parameter error: The error to convert.
    init(_ error: Error) {
        if let already = error as? DaemonError {
            self = already
            return
        }
        guard let storeError = error as? StoreError else {
            self = .transport(String(describing: error))
            return
        }
        switch storeError {
        case .notFound: self = .notFound
        case .summaryAbsent: self = .summaryAbsent
        case .versionConflict, .revisionConflict: self = .versionConflict
        case .invalidTransition, .invalidEntityTransition:
            // The wire carried the whole payload message (edge plus reason), and the
            // views render it verbatim; the bare reason alone would lose the edge.
            let message = storeError.errorPayload.message
            self = .invalidTransition(reason: message.isEmpty ? nil : message)
        case .contentLocked: self = .contentLocked
        default:
            let payload = storeError.errorPayload
            self = .server(code: payload.codeRaw, message: payload.message)
        }
    }
}

nonisolated extension UUID {
    /// The db and the gmfs yamls store lowercase v4 uuids and SQLite TEXT
    /// comparison is case-sensitive; Swift's `uuidString` emits uppercase.
    ///
    /// Every uuid crossing the wire goes through this.
    var wireString: String { uuidString.lowercased() }
}
