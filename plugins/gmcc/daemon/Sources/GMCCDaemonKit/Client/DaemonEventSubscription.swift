import Foundation

/// Long-lived event stream (SUBSCRIBE → EVENT*). Owns its OWN connection —
/// structurally separate from DaemonClient's request/response surface, so a
/// streaming connection can never have request frames interleaved into it.
///
/// Reconnect contract: persist `lastEventId` and pass it as `sinceId` on the
/// next subscription; the daemon replays every missed event before going
/// live. Replay is capped (see `replayCapped`): after a capped replay,
/// re-subscribe from the new `lastEventId` to drain the remainder.
public final class DaemonEventSubscription: @unchecked Sendable {
    private let client: DaemonClient
    private let sinceId: Int64?
    private var started = false

    /// Highest daemon_event.id seen. Seeded from the caller's own cursor so a
    /// quiet since_id reconnect that drops never regresses it to 0 (which
    /// would replay the entire event log next time); the ack horizon covers
    /// the fresh-subscription case, and each event advances it.
    public private(set) var lastEventId: Int64

    /// True when the subscribe ack indicates the replay hit the daemon's row
    /// cap — events between the last replayed id and the ack horizon were NOT
    /// replayed; re-subscribe from `lastEventId` after draining.
    public private(set) var replayCapped = false

    public init(
        sinceId: Int64? = nil,
        socketPath: String = Paths.socket.path,
        daemonBinaryPath: String = Paths.binDaemon.path,
        clientName: String = "subscriber",
        autostart: Bool = true
    ) {
        self.sinceId = sinceId
        self.lastEventId = sinceId ?? 0
        self.client = DaemonClient(
            socketPath: socketPath,
            daemonBinaryPath: daemonBinaryPath,
            clientName: clientName,
            autostart: autostart
        )
    }

    /// Subscribe and yield replayed + live events until the connection drops.
    /// A DAEMON_STOP event immediately before the stream ends means the drop
    /// was an intentional daemon shutdown, not a failure.
    public func events() -> AsyncThrowingStream<EventNotification, Error> {
        AsyncThrowingStream { continuation in
            // One-shot: a second events() call would put two readers on one
            // connection — exactly the interleaving this type exists to
            // prevent.
            guard !self.started else {
                continuation.finish(throwing: DaemonClientError.wire(
                    "DaemonEventSubscription.events() may only be consumed once — create a new subscription"))
                return
            }
            self.started = true
            let worker = Thread {
                do {
                    let ack: SubscribeAck = try self.client.request(
                        type: .subscribe,
                        payload: Subscribe(sinceId: self.sinceId),
                        responseType: SubscribeAck.self
                    )
                    if self.sinceId == nil {
                        self.lastEventId = ack.lastEventId
                    } else if ack.replayCount >= 10_000 {
                        self.replayCapped = true
                    }
                    while true {
                        let line = try self.client.readLine()
                        let envelope = try NDJSON.decode(ResponseEnvelope<EventNotification>.self, from: line)
                        if let notification = envelope.payload {
                            self.lastEventId = max(self.lastEventId, notification.id)
                            continuation.yield(notification)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            worker.start()
            continuation.onTermination = { _ in self.client.close() }
        }
    }
}
