import Foundation

/// STATUS — daemon + db health: pid, protocol version, socket path, schema
/// version, uptime, and per-table row counts.
enum StatusHandler {
    /// Handles a daemon status request.
    ///
    /// - Parameters:
    ///   - head: The envelope header with metadata.
    ///   - store: The persistence store.
    ///   - startedAt: ISO-8601 timestamp of daemon startup.
    ///   - startedDate: The Date object for startup time.
    /// - Returns: A handler result with the daemon status response.
    /// - Throws: Server errors during processing or persistence.
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
