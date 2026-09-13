import Foundation
import GmDaemon
import GmDaemonSdk

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
            protocolVersion: GmWireProtocol.version,
            socketPath: Paths.socket.path,
            dbPath: store.dbPath,
            schemaVersion: try store.schemaVersion(),
            tableCounts: try store.tableCounts(),
            lastEventId: try store.lastEventId(),
            startedAt: startedAt,
            uptimeSeconds: Int(Date().timeIntervalSince(startedDate)),
            // Parity with PING so the menu bar reads one shape whichever verb
            // it polled.
            residentMemoryBytes: KernelVitalsSource.residentMemoryBytes(),
            cpuPercent: KernelVitalsSource.cpuPercent(),
            writerRole: KernelVitalsSource.writerRole,
            writerBundlePath: KernelVitalsSource.writerBundlePath
        )
        return try okResult(.status, head, response)
    }
}
