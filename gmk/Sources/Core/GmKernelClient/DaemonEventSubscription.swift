import Foundation

/// Long-lived event stream (SUBSCRIBE → EVENT*).
///
/// Owns its own connection, structurally separate from DaemonClient's
/// request/response surface to prevent request frame interleaving. Reconnect:
/// persist `lastEventId`, pass as `sinceId` on next subscription. Daemon
/// replays missed events before going live. Replay is capped (see
/// `replayCapped`): re-subscribe from new `lastEventId` to drain remainder.
final class DaemonEventSubscription: @unchecked Sendable {
    private let client: DaemonClient
    private let sinceId: Int64?
    private var started = false

    /// Highest daemon_event.id seen.
    ///
    /// Seeded from the caller's own cursor so a quiet since_id reconnect that
    /// drops never regresses it to 0 (which would replay the entire event log
    /// next time); the ack horizon covers the fresh-subscription case, and each
    /// event advances it.
    private(set) var lastEventId: Int64

    /// True when the subscribe ack indicates the replay hit the daemon's row
    /// cap — events between the last replayed id and the ack horizon were NOT
    /// replayed; re-subscribe from `lastEventId` after draining.
    private(set) var replayCapped = false

    /// Creates an event subscription, optionally resuming from a prior cursor.
    ///
    /// - Parameters:
    ///   - sinceId: The last event id to resume from, or nil to start fresh.
    ///   - socketPath: The daemon socket path.
    ///   - appBundlePath: The kernel app to launch for autostart; defaults to this root's `Paths.launchApp`.
    ///   - clientName: The client name for daemon logging.
    ///   - autostart: Whether to launch the kernel app if not running.
    init(
        sinceId: Int64? = nil,
        socketPath: String = Paths.socket.path,
        appBundlePath: String = Paths.launchApp.path,
        clientName: String = "subscriber",
        autostart: Bool = true
    ) {
        self.sinceId = sinceId
        self.lastEventId = sinceId ?? 0
        self.client = DaemonClient(
            socketPath: socketPath,
            appBundlePath: appBundlePath,
            clientName: clientName,
            autostart: autostart
        )
    }

    /// Subscribes and yields replayed plus live events until the connection drops.
    ///
    /// A DAEMON_STOP event immediately before the stream ends indicates an intentional daemon
    /// shutdown, not a failure. May only be called once per subscription.
    ///
    /// - Returns: An async throwing stream of event notifications.
    func events() -> AsyncThrowingStream<EventNotification, Error> {
        AsyncThrowingStream { continuation in
            // One-shot: a second events() call would put two readers on one
            // connection — exactly the interleaving this type exists to
            // prevent.
            guard !self.started else {
                continuation.finish(
                    throwing: DaemonClientError.wire(
                        "DaemonEventSubscription.events() may only be consumed once — create a new subscription"
                    )
                )
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
