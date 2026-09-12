import Foundation
import GMCCDaemonKit

/// SHUTDOWN — graceful stop. The response flushes first; the connection's
/// .shutdown postAction then runs Server.performShutdown (drain-by-queue,
/// DAEMON_STOP goodbye event, WAL checkpoint, pidfile + socket removal,
/// exit 0).
enum ShutdownHandler {
    static func handle(head: EnvelopeHead) throws -> HandlerResult {
        let response = ShutdownResponse(message: "daemon pid \(getpid()) stopping")
        let envelope = ResponseEnvelope<ShutdownResponse>(
            type: .shutdown, requestId: head.requestId, ok: true, payload: response)
        return HandlerResult(line: try NDJSON.encodeLine(envelope), postAction: .shutdown)
    }
}
