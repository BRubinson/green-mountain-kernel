import Foundation
import Observation
import GMCCDaemonKit

/// The route() → checkout-state edge. A protocol so DaemonConnectionModel
/// stays free of concrete store types. No owner token: unlike the session
/// registry's SwiftUI scopes, the sink is an app-lifetime singleton, so
/// there is no successor-clobbering race to guard.
@MainActor
protocol CheckoutEventSink: AnyObject {
    func applyCheckoutChange(instanceUuid: String, headState: String,
                             currentBranch: String?, currentSessionCode: String?)
}

/// Per-instance checked-out-session cache. The push edge is the daemon's
/// CHECKOUT_CHANGE broadcast (FSEvents on instance git dirs live daemon-side
/// as of v8) — the client watches nothing on disk. A broadcast's cheap fields
/// (head state, raw branch, slugged code) publish immediately; the resolved
/// `SessionStub` arrives via one coalesced INSTANCE_CURRENT_SESSION, keeping
/// resolution daemon-side (no client catalog scan). Broadcasts are ephemeral
/// (id 0, never replayed), so a reconnect resyncs every watched instance once
/// per daemon generation.
@Observable
@MainActor
final class CheckoutWatcher: CheckoutEventSink {
    /// Mirrors the wire's `head_state` string. `unavailable` (path gone / not
    /// a repo) is NOT `detached` (a real checkout with no branch) — the
    /// instance page says different things about them. Unknown wire values
    /// degrade to `.unavailable` rather than fabricating state.
    enum HeadState: Equatable, Sendable {
        case branch
        case detached
        case unavailable

        init(wire: String) {
            switch wire {
            case "branch": self = .branch
            case "detached": self = .detached
            default: self = .unavailable
            }
        }
    }

    struct CheckoutState: Equatable, Sendable {
        let headState: HeadState
        /// Slugged session code (forward-only rule, daemon-derived) — compare
        /// against `SessionStub.code`; never unslug.
        let currentSessionCode: String?
        /// The RAW branch name (nil unless headState == .branch) — the wire's
        /// display truth. The code stays slugged; the two are never
        /// interconverted client-side.
        let currentBranch: String?
        let session: SessionStub?
    }

    /// Last-known state per instance uuid. Kept on RPC failure — checked-out
    /// state is a display signal, and a daemon restart must not blank every
    /// green ring. Absent entry = never resolved.
    private(set) var stateByInstance: [String: CheckoutState] = [:]

    /// Membership set the reconnect resync iterates. Instances leave it when
    /// they leave the catalog.
    private var watchedInstances: Set<String> = []
    /// The daemon generation the last full resync ran against. Ephemeral
    /// CHECKOUT_CHANGE broadcasts are lost while disconnected, so each
    /// down→up transition re-resolves every watched instance exactly once.
    private var lastResyncGeneration = 0
    /// Per-instance trailing coalesce: back-to-back events (or a broadcast
    /// landing during a resync) must collapse to ONE round trip on the
    /// fairness-free serial queue.
    private var refreshTasks: [String: Task<Void, Never>] = [:]

    private let service = GMCCDaemonService.shared

    // MARK: - Reads

    /// Is this session the checked-out one on its instance?
    /// `session.code` IS the slugged branch; the daemon's code is authoritative.
    func isCheckedOut(sessionCode: String, instanceUuid: String) -> Bool {
        stateByInstance[instanceUuid]?.currentSessionCode == sessionCode
    }

    /// The slugged code of the checked-out branch on an instance, or nil.
    func checkedOutCode(instanceUuid: String) -> String? {
        stateByInstance[instanceUuid]?.currentSessionCode
    }

    /// The resolved session row for the checked-out branch, or nil (detached,
    /// unavailable, or no matching session row).
    func currentSession(instanceUuid: String) -> SessionStub? {
        stateByInstance[instanceUuid]?.session
    }

    // MARK: - Watch management

    /// (Re)target the watch set. Called after every catalog refresh — it must
    /// not burst N RPCs: on an unchanged set and generation it schedules
    /// nothing. A generation bump resolves EVERY member once (missed
    /// ephemeral broadcasts are unrecoverable); otherwise only new or
    /// never-resolved instances resolve.
    func watch(instanceUuids: Set<String>, generation: Int) {
        for uuid in watchedInstances.subtracting(instanceUuids) {
            drop(instanceUuid: uuid)
        }
        let isNewGeneration = generation != lastResyncGeneration
        lastResyncGeneration = generation
        for uuid in instanceUuids {
            let isNew = watchedInstances.insert(uuid).inserted
            if isNewGeneration || isNew || stateByInstance[uuid] == nil {
                scheduleRefresh(instanceUuid: uuid)
            }
        }
    }

    /// Add one instance to the watch set without dropping the others. The
    /// first call to see a new generation resyncs the whole set.
    func ensureWatching(instanceUuid: String, generation: Int) {
        let isNew = watchedInstances.insert(instanceUuid).inserted
        if generation != lastResyncGeneration {
            lastResyncGeneration = generation
            for uuid in watchedInstances { scheduleRefresh(instanceUuid: uuid) }
        } else if isNew || stateByInstance[instanceUuid] == nil {
            scheduleRefresh(instanceUuid: instanceUuid)
        }
    }

    private func drop(instanceUuid: String) {
        watchedInstances.remove(instanceUuid)
        refreshTasks[instanceUuid]?.cancel()
        refreshTasks[instanceUuid] = nil
        if stateByInstance[instanceUuid] != nil {
            stateByInstance[instanceUuid] = nil
        }
    }

    // MARK: - Event application (CheckoutEventSink)

    /// Two-phase apply. The broadcast carries no resolved `SessionStub`, so:
    /// publish everything it DOES carry now (every display surface is
    /// satisfied), keeping the previous stub only while the code is unchanged
    /// — a stub from the old branch is worse than none. Then one coalesced
    /// round trip fills `session` authoritatively.
    func applyCheckoutChange(instanceUuid: String, headState: String,
                             currentBranch: String?, currentSessionCode: String?) {
        // A broadcast racing a catalog removal must not resurrect state for a
        // dropped instance — drop() is the only cleaner of stateByInstance.
        guard watchedInstances.contains(instanceUuid) else { return }
        let previous = stateByInstance[instanceUuid]
        let carried = previous?.currentSessionCode == currentSessionCode ? previous?.session : nil
        let new = CheckoutState(
            headState: HeadState(wire: headState),
            currentSessionCode: currentSessionCode,
            currentBranch: currentBranch,
            session: carried
        )
        if previous != new { stateByInstance[instanceUuid] = new }
        // Nothing to resolve when no branch is checked out — the payload
        // already said everything.
        if currentSessionCode != nil, new.session == nil {
            scheduleRefresh(instanceUuid: instanceUuid)
        }
    }

    // MARK: - Resolution (daemon-side)

    private func scheduleRefresh(instanceUuid: String) {
        refreshTasks[instanceUuid]?.cancel()
        // The slot is NOT cleared from inside the task: a task past its sleep
        // can't be stopped, and clearing unconditionally after the RPC would
        // erase a SUCCESSOR's registration (letting a third fire run
        // concurrently and a superseded response publish stale state). The
        // entry is overwritten by the next schedule and cleared by drop; a
        // completed task's handle is inert.
        refreshTasks[instanceUuid] = Task { [weak self] in
            // Coalesce bursts (resync + broadcast racing) into one RPC.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.refresh(instanceUuid: instanceUuid)
        }
    }

    private func refresh(instanceUuid: String) async {
        do {
            let response = try await service.instanceCurrentSession(instanceUuid: instanceUuid)
            // Superseded mid-RPC (a newer fire cancelled us) or dropped —
            // never publish a stale response over a newer one.
            guard !Task.isCancelled else { return }
            let new = CheckoutState(
                headState: HeadState(wire: response.headState),
                currentSessionCode: response.currentSessionCode,
                currentBranch: response.currentBranch,
                session: response.session
            )
            if stateByInstance[instanceUuid] != new {
                stateByInstance[instanceUuid] = new
            }
        } catch {
            // Keep the last known state — a down daemon must not clear the
            // checked-out ring. The next broadcast or generation resync
            // retries.
        }
    }
}
