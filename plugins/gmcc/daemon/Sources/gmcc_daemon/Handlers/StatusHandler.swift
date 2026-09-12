import Foundation
import GMCCDaemonKit

/// STATUS — daemon + db health: pid, protocol version, socket path, schema
/// version, uptime, and per-table row counts.
enum StatusHandler {
    static func handle(
        head: EnvelopeHead,
        store: Store,
        startedAt: String,
        startedDate: Date
    ) throws -> HandlerResult {
        let response = StatusResponse(
            daemonPid: getpid(),
            protocolVersion: GMCCWireProtocol.version,
            socketPath: Paths.socket.path,
            dbPath: store.dbPath,
            schemaVersion: try store.schemaVersion(),
            tableCounts: try store.tableCounts(),
            lastEventId: try store.lastEventId(),
            startedAt: startedAt,
            uptimeSeconds: Int(Date().timeIntervalSince(startedDate))
        )
        return try okResult(.status, head, response)
    }
}
