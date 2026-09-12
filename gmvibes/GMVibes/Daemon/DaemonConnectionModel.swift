import Foundation
import Observation
import GMCCDaemonKit

/// App-wide daemon liveness + the single event subscription.
///
/// Health comes from the probe (STATUS + PING with autostart off), never
/// inferred from the subscription alone — a quiet healthy stream is
/// indistinguishable from a hung one, so while up the event consumption is
/// raced against a 30s status watchdog (the app-wide liveness check that
/// replaced per-view confirming polls). The supervising loop probes, then
/// consumes events until the stream drops, then re-probes; a killed daemon
/// goes red within one iteration and stays red (nothing here autostarts).
/// DAEMON_START is unreceivable while down, so green is re-inferred from the
/// next successful probe.
@Observable @MainActor
final class DaemonConnectionModel {
    enum Health: Equatable {
        case unknown
        case notInstalled
        case down(reason: String, intentional: Bool)
        /// Daemon speaks a newer protocol than our linked kit — rebuild
        /// GMVibes / update the package. Starting the daemon can't fix it.
        case incompatible(daemonVersion: Int?)
        case starting
        case up
    }

    private(set) var health: Health = .unknown
    private(set) var status: StatusResponse?
    private(set) var ping: PingResponse?
    /// Bumped on every down→up transition and on a capped replay (resync barrier).
    private(set) var generation = 0

    let hub = InvalidationHub()

    /// The route() → checkout-state edge. CHECKOUT_CHANGE's payload carries
    /// everything the watcher publishes, so the arm applies state directly
    /// instead of waking a Void-domain subscriber into a round trip. Weak —
    /// the sink is an app-lifetime singleton, wired once by GMVibesServices.
    weak var checkoutSink: CheckoutEventSink?

    /// Live session scopes register their prompt uuids so prompt-subject
    /// events route to the owning session only; unknown subjects fan out.
    /// Owner-token guarded: a retired scope's late unregister must not kill
    /// routing for a successor scope on the same session.
    private var sessionPrompts: [String: (owner: ObjectIdentifier, prompts: Set<String>)] = [:]

    private let service = GMCCDaemonService.shared
    private var runTask: Task<Void, Never>?
    private var probeInFlight = false
    /// Sticky across probe failures so an intentional `gm daemon stop` keeps
    /// reading "daemon stopped" instead of a raw socket error from the next
    /// failed probe.
    private var intentionalStop = false

    private static let cursorKey = "gmvibes.daemon.lastEventId"
    private static let cursorStampKey = "gmvibes.daemon.lastEventStamp"
    /// Replay is served on the daemon's single serial queue; a cursor older
    /// than this replays a backlog to learn what one resync refetch tells us.
    private static let cursorMaxAge: TimeInterval = 3600
    /// Stamp-guard: the cursor timestamp advances only when the id actually
    /// moved, so a quiet reconnect can't keep refreshing a dead cursor's age.
    private var lastPersistedCursor: Int64 = 0

    // App-lifetime singleton — the supervising task runs until process exit.
    // Weak capture so a discarded instance (SwiftUI can re-evaluate app @State)
    // doesn't leak a probe loop + socket forever.
    init(autorun: Bool = true) {
        if autorun {
            runTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.iterate()
                }
            }
        }
    }

    // MARK: - Session routing registry

    func registerSession(_ sessionUuid: String, promptUuids: Set<String>, owner: ObjectIdentifier) {
        let current = sessionPrompts[sessionUuid]
        if current?.owner != owner || current?.prompts != promptUuids {
            sessionPrompts[sessionUuid] = (owner, promptUuids)
        }
    }

    func unregisterSession(_ sessionUuid: String, ifOwnedBy owner: ObjectIdentifier) {
        if sessionPrompts[sessionUuid]?.owner == owner {
            sessionPrompts[sessionUuid] = nil
        }
    }

    private func owningSession(ofPrompt uuid: String) -> String? {
        sessionPrompts.first { $0.value.prompts.contains(uuid) }?.key
    }

    // MARK: - Supervising loop

    /// One loop turn: gate on installed, probe, and while up consume events
    /// raced against the 30s liveness watchdog. Backs off when the subscribe
    /// path fails fast (probe ok but SUBSCRIBE rejected) so a broken daemon
    /// isn't hammered at CPU speed.
    private var fastFailureBackoff: Duration = .seconds(1)

    private func iterate() async {
        guard GMCCDaemonService.isInstalled else {
            setHealth(.notInstalled)
            try? await Task.sleep(for: .seconds(5))
            return
        }
        await probe()
        guard health == .up else {
            try? await Task.sleep(for: .seconds(2))
            return
        }
        let started = ContinuousClock.now
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.consumeEvents() }
            group.addTask {
                // App-wide 30s liveness watchdog (replaces per-view confirming
                // polls): a wedged-but-connected daemon fails this probe and
                // goes red even though the stream never drops.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if Task.isCancelled { break }
                    await self.probe()
                }
            }
            await group.next()   // consumeEvents ended; the watchdog never returns
            group.cancelAll()
        }
        if ContinuousClock.now - started < .seconds(2) {
            try? await Task.sleep(for: fastFailureBackoff)
            fastFailureBackoff = min(fastFailureBackoff * 2, .seconds(10))
        } else {
            fastFailureBackoff = .seconds(1)
        }
    }

    /// Single-flight STATUS+PING probe. Publishes change-gated; bumps the
    /// resync generation only on a genuine down→up transition.
    func probe() async {
        if probeInFlight { return }
        probeInFlight = true
        defer { probeInFlight = false }
        do {
            let newStatus = try await service.status()
            let newPing = try await service.ping()
            if status != newStatus { status = newStatus }
            if ping != newPing { ping = newPing }
            intentionalStop = false
            let wasUp = health == .up
            setHealth(.up)
            if !wasUp {
                generation += 1
                hub.invalidateAll()
            }
        } catch let error as DaemonError {
            switch error {
            case .notInstalled:
                setHealth(.notInstalled)
            case .clientTooOld(let daemonVersion):
                setHealth(.incompatible(daemonVersion: daemonVersion))
            default:
                setHealth(.down(
                    reason: intentionalStop ? "Daemon stopped" : error.userMessage,
                    intentional: intentionalStop))
            }
        } catch {
            setHealth(.down(
                reason: intentionalStop ? "Daemon stopped" : String(describing: error),
                intentional: intentionalStop))
        }
    }

    /// Alias for the probe — refreshes status/ping/health (and, on a genuine
    /// down→up transition, fires the resync barrier).
    func refreshStatus() async {
        await probe()
    }

    func startDaemon() async {
        setHealth(.starting)
        intentionalStop = false
        do {
            _ = try await service.startDaemon()
            await probe()
        } catch let error as DaemonError {
            switch error {
            case .notInstalled:
                setHealth(.notInstalled)
            case .clientTooOld(let daemonVersion):
                setHealth(.incompatible(daemonVersion: daemonVersion))
            default:
                setHealth(.down(reason: error.userMessage, intentional: false))
            }
        } catch {
            setHealth(.down(reason: String(describing: error), intentional: false))
        }
    }

    // MARK: - Event consumption

    private func consumeEvents() async {
        // Cursor policy: bounded replay. Resume from the persisted cursor only
        // when it is fresh AND not ahead of the daemon's event log (a db
        // re-baseline restarts event ids at 1 — replaying above the log head
        // would silently match nothing forever). Otherwise subscribe live;
        // the up-transition's invalidateAll() already resynced surfaces.
        var sinceId: Int64? = nil
        let defaults = UserDefaults.standard
        if let stored = (defaults.object(forKey: Self.cursorKey) as? NSNumber)?.int64Value, stored > 0 {
            lastPersistedCursor = max(lastPersistedCursor, stored)
            let stamp = defaults.object(forKey: Self.cursorStampKey) as? Date ?? .distantPast
            let logHead = status?.lastEventId ?? 0
            if Date().timeIntervalSince(stamp) < Self.cursorMaxAge, stored <= logHead {
                sinceId = stored
            }
        }

        // The subscription's autostart parameter DEFAULTS TO TRUE; left at the
        // default, the reconnect loop would resurrect a daemon the user killed
        // and the red indicator would silently self-heal.
        let subscription = DaemonEventSubscription(
            sinceId: sinceId,
            clientName: "gmvibes-events",
            autostart: false
        )
        var trailingStop = false
        var checkedReplayCap = false
        var eventsSincePersist = 0
        do {
            for try await event in subscription.events() {
                if Task.isCancelled { break }
                if !checkedReplayCap {
                    checkedReplayCap = true
                    if subscription.replayCapped {
                        // Events between the replayed prefix and the ack horizon
                        // were dropped by the cap — resync rather than trusting a
                        // gapped stream.
                        generation += 1
                        hub.invalidateAll()
                    }
                }
                // Only a DAEMON_STOP immediately before the stream ends means an
                // intentional shutdown; a replayed historical one must not stick.
                trailingStop = (event.kind == DaemonEventKind.daemonStop.rawValue)
                route(event)
                eventsSincePersist += 1
                if eventsSincePersist >= 50 {
                    persistCursor(subscription.lastEventId)
                    eventsSincePersist = 0
                }
            }
        } catch {
            // Stream drop — the supervising loop re-probes and reports health.
        }
        persistCursor(subscription.lastEventId)
        if trailingStop {
            intentionalStop = true
            setHealth(.down(reason: "Daemon stopped", intentional: true))
        } else if !Task.isCancelled && health == .up {
            setHealth(.down(reason: "Event stream ended", intentional: false))
        }
    }

    /// The uuid carriers in hand-built event payloads. These payloads are
    /// JSONSerialization'd snake_case literals (`Store.jsonPayload`), OUTSIDE
    /// the wire's type system — decoding through `WireCodec.decoder` is what
    /// maps `sessionUuid` to `"session_uuid"`. A bare `JSONDecoder()` decodes
    /// to nil silently and routing just quietly stops happening.
    private struct EventPayloadUuids: Decodable {
        let sessionUuid: String?
        let promptUuid: String?
        /// DIAGRAM_CHANGE only: the tier owner chain, so the rails that list
        /// a tier can be woken without a re-list of every other tier.
        let projectUuid: String?
    }

    private func payloadUuids(_ event: EventNotification) -> EventPayloadUuids? {
        guard let payload = event.payload, let data = payload.data(using: .utf8) else { return nil }
        return try? WireCodec.decoder.decode(EventPayloadUuids.self, from: data)
    }

    /// CHECKOUT_CHANGE is ephemeral (id 0, never a replay cursor) and its
    /// payload is complete: the daemon's HEAD watcher already resolved the
    /// branch and session code, so the arm publishes state rather than
    /// scheduling a lookup.
    private struct CheckoutChangePayload: Decodable {
        let instanceUuid: String
        let headState: String
        let currentBranch: String?
        let currentSessionCode: String?
    }

    private func route(_ event: EventNotification) {
        guard let kind = DaemonEventKind(rawValue: event.kind) else {
            return // forward compat: unknown kinds bump nothing
        }
        switch kind {
        case .createProject, .createInstance, .createSession, .updateProject:
            // updateProject carries primary_project_branch, which the project
            // view renders — same topology invalidation as its siblings.
            hub.invalidate(.topology)
        case .updateSession:
            hub.invalidate(.topology)
            // Subjects are lowercased on every arm — subscribers key on
            // lowercase wire strings, and a case miss here fails silently.
            if let uuid = event.subjectUuid?.lowercased() { hub.invalidate(.session(uuid)) }
        case .createPrompt:
            // v7 payloads carry session_uuid; replayed pre-v7 rows don't — degrade.
            if let uuid = payloadUuids(event)?.sessionUuid?.lowercased() {
                hub.invalidate(.session(uuid))
            } else {
                hub.invalidateAllSessions()
            }
        case .updatePrompt, .promptStatusChange, .addArtifact:
            // Subject IS the prompt uuid: route to the owning open session when
            // known (avoids a SESSION_GET storm across windows on every save);
            // fan out only for prompts no open window has registered.
            if let uuid = event.subjectUuid?.lowercased() {
                hub.invalidate(.prompt(uuid))
                if let session = owningSession(ofPrompt: uuid) {
                    hub.invalidate(.session(session))
                } else {
                    hub.invalidateAllSessions()
                }
            } else {
                hub.invalidateAllSessions()
            }
        case .fileChange:
            hub.invalidate(.changes)
            if let uuid = payloadUuids(event)?.sessionUuid?.lowercased() {
                hub.invalidate(.session(uuid))
            } else {
                hub.invalidateAllSessions()
            }
        case .addKbite, .removeKbite:
            // At prompt scope the subject is the owner (prompt) uuid — refresh
            // the open editor's pills for terminal-side registry edits.
            if let uuid = event.subjectUuid?.lowercased() { hub.invalidate(.prompt(uuid)) }
        case .kbiteDigest, .kbiteKeywordTag, .kbiteImport:
            // No subscriber surface: the KBites browser reads the filesystem
            // and its search hits the daemon on demand. Import (v22) changes
            // content only — it never registers, so no pills move.
            break
        case .kbiteDelete:
            // v22: the cascade drops the kbite's registrations at EVERY
            // scope, and the subject is the kbite uuid — not routable to the
            // prompts whose pills just lost an entry. Wake open prompt panes.
            hub.invalidateAllPrompts()
        case .hookUnbound, .agentUnregistered:
            // Capture-health diagnostics, not data changes: HOOK_UNBOUND means a
            // payload-borne write named a Claude conversation no binding row
            // resolves (so the write was refused — nothing to refetch), and
            // AGENT_UNREGISTERED means the daemon invented a registration the
            // spawner never made. Neither moves anything this app renders, so
            // there is no subscriber surface to bump. They are deliberately
            // durable and noisy on the daemon side; surfacing them in the status
            // indicator is a real feature, not a routing concern.
            break
        case .promptMemoryChange:
            // Ephemeral (id 0, never a replay cursor). The daemon resolves the
            // storage path server-side and the subject IS the prompt uuid — no
            // payload decode needed.
            if let uuid = event.subjectUuid { hub.invalidate(.memories(uuid.lowercased())) }
        case .checkoutChange:
            guard let payload = event.payload, let data = payload.data(using: .utf8),
                  let decoded = try? WireCodec.decoder.decode(CheckoutChangePayload.self, from: data)
            else { break }
            checkoutSink?.applyCheckoutChange(
                instanceUuid: decoded.instanceUuid.lowercased(),
                headState: decoded.headState,
                currentBranch: decoded.currentBranch,
                currentSessionCode: decoded.currentSessionCode)
        case .clarificationChange, .architectureChange, .explorationChange, .reviewChange:
            // Subject is the SUMMARY uuid, but as of v8 EVERY phase payload
            // carries prompt_uuid — decode and route directly. NO fan-out on
            // miss for clarify/arch: nothing renders an unopened summary, and
            // opening one fetches fresh.
            if let prompt = payloadUuids(event)?.promptUuid?.lowercased() {
                hub.invalidate(.prompt(prompt))
            } else if kind == .reviewChange {
                // The ONE v9 payload without prompt_uuid: REVIEW_CHANGE with
                // action "resolve" (Store+Review resolve arm) — the fix
                // loop's most frequent event, so dropping it would freeze
                // every resolution badge and open-count. Wake open prompt
                // panes instead; delete this arm when the daemon adds
                // prompt_uuid there.
                hub.invalidateAllPrompts()
            }
        case .briefingChange:
            // Payload: {action, step, session_uuid, prompt_uuid?} — prompt_uuid
            // is absent only for /gm_task session-owned briefings, which no
            // surface renders yet, so those events route nowhere by design.
            if let prompt = payloadUuids(event)?.promptUuid?.lowercased() {
                hub.invalidate(.prompt(prompt))
            }
        case .workflowChange:
            // m0025 bot workflow transitions: payload carries prompt_uuid —
            // route like briefingChange (no dedicated pane yet; the prompt
            // surfaces re-pull their phase stores).
            if let prompt = payloadUuids(event)?.promptUuid?.lowercased() {
                hub.invalidate(.prompt(prompt))
            }
        case .diagramChange:
            // Subject IS the diagram uuid — the open editor's key. The
            // payload's owner chain (project always, session/prompt when the
            // diagram is owned that deep) wakes the tier-scoped rails; each
            // is a separate domain so one drag commit repaints one canvas
            // instead of re-listing every rail in the app.
            if let uuid = event.subjectUuid?.lowercased() {
                hub.invalidate(.diagram(uuid))
            }
            if let uuids = payloadUuids(event) {
                for owner in [uuids.projectUuid, uuids.sessionUuid, uuids.promptUuid] {
                    if let owner { hub.invalidate(.diagramList(owner.lowercased())) }
                }
            }
        case .dopeChange:
            // subject_uuid is the SCOPE uuid — a value no surface holds until
            // AFTER a successful DOPE_GET, so it cannot be a routing key.
            // session_uuid (always in recordDopeChange's payload) is what dope
            // stores subscribe on; the scope uuid rides through the payload for
            // the store to narrow via its own scope index.
            if let session = payloadUuids(event)?.sessionUuid?.lowercased() {
                hub.invalidate(.dope(session))
            } else {
                hub.invalidateAllDope()
            }
            // recordDopeChange also touches session.updated_at, so landing
            // recency genuinely moved. `.changes` is the debounced (750ms)
            // catalog-refresh path — NOT `.session`, which would storm
            // SESSION_GET + PROMPT_LIST + prefetch on every node of a bot's
            // tree build.
            hub.invalidate(.changes)
        case .promptDiagramQualified:
            // A prompt qualified a RENDER, not a canvas: nothing about the
            // diagram tree moved, so diagram listeners must not refetch. The
            // prompt surface is the one that shows the qualification.
            if let prompt = payloadUuids(event)?.promptUuid?.lowercased() {
                hub.invalidate(.prompt(prompt))
            } else if let uuid = event.subjectUuid?.lowercased() {
                hub.invalidate(.prompt(uuid))
            }
        case .configSet:
            // A root moved daemon-side — the env's PATHS_GET snapshot is stale.
            hub.invalidate(.paths)
        case .backup, .daemonStart:
            Task { await refreshStatus() }
        case .daemonStop:
            // No probe here: the stream is about to end and a racing probe
            // against a dying daemon would clobber the intentional flag.
            break
        }
    }

    // MARK: - Helpers

    private func persistCursor(_ id: Int64) {
        guard id > 0, id > lastPersistedCursor else { return }
        lastPersistedCursor = id
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: Self.cursorKey)
        defaults.set(Date(), forKey: Self.cursorStampKey)
    }

    private func setHealth(_ new: Health) {
        if health != new { health = new }
    }

}
