import Foundation
import Observation

/// One `SessionScope` per session uuid, shared by every window showing that
/// session and refcounted by the screens that hold it.
///
/// This restores the invariant the old `WindowGroup` dedupe provided: a single
/// owner per session/prompt for the daemon-event registry and save actors.
/// (Draft boxes register independently per pane.)
@MainActor
final class SessionScopeCache {
    static let shared = SessionScopeCache()

    private struct Entry {
        let scope: SessionScope
        var refs: Int
    }

    private var entries: [String: Entry] = [:]
    /// Retired scopes, newest last.
    ///
    /// Navigate-away-and-back revives the scope with its prompt cache intact
    /// instead of paying a fresh SESSION_GET + sequential prefetch.
    private var grace: [SessionScope] = []
    private let graceCap = 4

    /// Returns a scope without refcounting or promoting from the grace list.
    ///
    /// Safe to call from a View init, which SwiftUI may run repeatedly. Only `acquire`
    /// moves scopes between states.
    ///
    /// - Parameter sessionUuid: The session's UUID.
    /// - Returns: The scope for this session, creating it if needed.
    func scope(for sessionUuid: String) -> SessionScope {
        if let entry = entries[sessionUuid] { return entry.scope }
        if let graced = grace.first(where: { $0.sessionUuid == sessionUuid }) {
            return graced
        }
        let fresh = SessionScope(sessionUuid: sessionUuid)
        entries[sessionUuid] = Entry(scope: fresh, refs: 0)
        return fresh
    }

    /// Acquires a scope reference, promoting from the grace list if needed.
    ///
    /// - Parameter sessionUuid: The session's UUID.
    func acquire(_ sessionUuid: String) {
        if entries[sessionUuid] != nil {
            entries[sessionUuid]?.refs += 1
            return
        }
        if let index = grace.firstIndex(where: { $0.sessionUuid == sessionUuid }) {
            let revived = grace.remove(at: index)
            entries[sessionUuid] = Entry(scope: revived, refs: 1)
            return
        }
        entries[sessionUuid] = Entry(scope: SessionScope(sessionUuid: sessionUuid), refs: 1)
    }

    /// Releases a scope reference, moving it to the grace list when ref count reaches zero.
    ///
    /// - Parameter sessionUuid: The session's UUID.
    func release(_ sessionUuid: String) {
        guard var entry = entries[sessionUuid], entry.refs > 0 else {
            assertionFailure("unbalanced SessionScopeCache.release(\(sessionUuid))")
            return
        }
        entry.refs -= 1
        if entry.refs == 0 {
            entries[sessionUuid] = nil
            entry.scope.retire()
            grace.append(entry.scope)
            while grace.count > graceCap { grace.removeFirst() }
        } else {
            entries[sessionUuid] = entry
        }
    }
}

/// Everything one session owns above the wire: the read store plus one save
/// actor PER PROMPT UUID (shared by every pane on that prompt so writes are
/// serialized through one version thread).
@MainActor
final class SessionScope {
    let sessionUuid: String
    let store: SessionStore

    private weak var daemon: DaemonConnectionModel?
    private var savers: [String: PromptSaveActor] = [:]
    private var phaseStores: [String: PromptPhaseStore] = [:]
    private var dopeStore: DopeStore?

    /// Creates a session scope with a new session store.
    ///
    /// - Parameter sessionUuid: The session's UUID.
    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
        self.store = SessionStore(sessionUuid: sessionUuid)
    }

    /// Registers prompt updates with the daemon.
    ///
    /// Idempotent; keeps prompt-update events routing to this session. Owner-token
    /// guarded so a stale unregister cannot kill a live successor's routing.
    ///
    /// - Parameters:
    ///   - promptUuids: The prompt UUIDs to register.
    ///   - daemon: The daemon connection model.
    func registerPrompts(_ promptUuids: Set<String>, daemon: DaemonConnectionModel) {
        self.daemon = daemon
        daemon.registerSession(sessionUuid, promptUuids: promptUuids, owner: ObjectIdentifier(self))
    }

    /// Called by the cache when the last holder releases the scope.
    ///
    /// Routing stops; panes own their draft boxes and flush on teardown.
    func retire() {
        daemon?.unregisterSession(sessionUuid, ifOwnedBy: ObjectIdentifier(self))
    }

    /// Returns the memoized save actor for a prompt.
    ///
    /// Concurrent panes thread one version through a single actor. The version
    /// argument seeds a new actor only; an existing actor's threading is
    /// authoritative (and `adoptVersion` is monotonic besides).
    ///
    /// - Parameters:
    ///   - promptUuid: The prompt's UUID.
    ///   - version: The initial version for a new actor.
    /// - Returns: The prompt's save actor.
    func saver(forPrompt promptUuid: String, version: Int64) -> PromptSaveActor {
        if let existing = savers[promptUuid] { return existing }
        let fresh = PromptSaveActor(promptUuid: promptUuid, version: version)
        savers[promptUuid] = fresh
        return fresh
    }

    /// Returns the memoized phase store for a prompt.
    ///
    /// N panes on one prompt share one CLARIFY_GET + ARCH_GET pair (and one
    /// summary-routing registration).
    ///
    /// - Parameter promptUuid: The prompt's UUID.
    /// - Returns: The prompt's phase store.
    func phases(forPrompt promptUuid: String) -> PromptPhaseStore {
        if let existing = phaseStores[promptUuid] { return existing }
        let fresh = PromptPhaseStore(promptUuid: promptUuid)
        phaseStores[promptUuid] = fresh
        return fresh
    }

    /// Returns the memoized answer model for a prompt's clarifications.
    ///
    /// Memoized per prompt uuid by delegation: the prompt's `PromptPhaseStore` OWNS
    /// the model, so this is the SAME instance CLARIFY_GET calls `adopt` on — one
    /// source of truth for every question's version cell, and no second registry to
    /// keep in sync. Reached through the scope so per-question drafts and version
    /// cells survive pane navigation within a session: a half-typed answer must not
    /// evaporate because the user glanced at the architecture tab.
    ///
    /// - Parameter promptUuid: The prompt's UUID.
    /// - Returns: The prompt's clarification answer model.
    func answers(forPrompt promptUuid: String) -> ClarificationAnswerModel {
        phases(forPrompt: promptUuid).answers
    }

    /// ONE dope store per scope (not per prompt): DOPE_GET's SESSION_BASE
    /// fallback means the session tab and a prompt's card often render the
    /// SAME tree — every surface on this session shares this store, one
    /// fetch per key, one event wake for all of them.
    var dope: DopeStore {
        if let existing = dopeStore { return existing }
        let fresh = DopeStore(sessionUuid: sessionUuid)
        dopeStore = fresh
        return fresh
    }
}
