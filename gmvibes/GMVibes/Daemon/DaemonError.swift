import Foundation
import GMCCDaemonKit

/// App-facing typed error surface. Views and stores branch on these cases —
/// never on message text — per the daemon's typed-code contract.
nonisolated enum DaemonError: Error, Equatable {
    /// Binary absent at ~/gmcc/bin/gmcc_daemon (distinct from a stopped daemon).
    case notInstalled
    /// Socket dead and autostart disabled (or autostart exhausted its retries).
    case unreachable(String)
    /// Daemon is newer than our linked GMCCDaemonKit — rebuild GMVibes /
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

    /// The single user-facing description. Screens that need context-specific
    /// wording (e.g. search) may special-case a few cases and fall back here.
    var userMessage: String {
        switch self {
        case .notInstalled: return "Daemon not installed (run build_daemon.sh)."
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

    init(_ error: Error) {
        if let already = error as? DaemonError {
            self = already
            return
        }
        guard let clientError = error as? DaemonClientError else {
            self = .transport(String(describing: error))
            return
        }
        switch clientError {
        case .unreachable(let message):
            // "Never installed" and "installed but stopped" are different UI
            // states; classify before reporting unreachable.
            if FileManager.default.isExecutableFile(atPath: Paths.binDaemon.path) {
                self = .unreachable(message)
            } else {
                self = .notInstalled
            }
        case .protocolMismatch(let message, let daemonVersion):
            if let daemonVersion, daemonVersion >= GMCCWireProtocol.version {
                self = .clientTooOld(daemonVersion: daemonVersion)
            } else {
                self = .daemonTooOld(daemonVersion: daemonVersion, message: message)
            }
        case .server(let payload):
            switch payload.code {
            case .notFound: self = .notFound
            case .summaryAbsent: self = .summaryAbsent
            case .versionConflict: self = .versionConflict
            case .invalidTransition: self = .invalidTransition(reason: payload.message.isEmpty ? nil : payload.message)
            case .contentLocked: self = .contentLocked
            default: self = .server(code: payload.codeRaw, message: payload.message)
            }
        case .wire(let message):
            self = .transport(message)
        }
    }
}

nonisolated extension UUID {
    /// The db and the ckfs yamls store lowercase v4 uuids and SQLite TEXT
    /// comparison is case-sensitive; Swift's `uuidString` emits uppercase.
    /// Every uuid crossing the wire goes through this.
    var wireString: String { uuidString.lowercased() }
}
