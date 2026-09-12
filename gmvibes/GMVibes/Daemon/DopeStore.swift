import Foundation
import Observation
import GMCCDaemonKit

/// Read model over DOPE_LIST + DOPE_GET + DOPE_READ_REPO (plus the one
/// DOPE_INIT write).
///
/// SCOPE-LEVEL, one per `SessionScope`, serving BOTH dope surfaces (the
/// session tab and the prompt phase card) — deliberately not prompt-keyed:
/// DOPE_GET with a promptUuid falls back to the SESSION_BASE tree
/// (`resolvedVia` reports which answered), so the two surfaces routinely
/// render the SAME tree. Prompt-keyed stores would double-fetch it, and a
/// SESSION_BASE write could never invalidate a prompt surface rendering the
/// fallback. Here one event wake reloads every live key.
///
/// Refresh rides the `.dope(sessionUuid)` hub domain (see the DOPE_CHANGE
/// arm) — never `.session`, which would storm SESSION_GET per node write.
@Observable
@MainActor
final class DopeStore {
    /// One read surface: `promptUuid` picks the TARGET (nil ⇒ the session's
    /// SESSION_BASE read; a prompt uuid ⇒ the prompt-preferred read, which
    /// MAY resolve to session base — see `resolvedVia`). `code` PINS one
    /// scope when the target has several; nil hands resolution to the daemon.
    ///
    /// Every selected scope is its own cached entry — phases, repo reads and
    /// repo issues are all keyed by the full Key, so switching scopes in the
    /// picker never shows another scope's stale tree or drift banner.
    struct Key: Hashable {
        let promptUuid: String?
        // `var` with a default (a defaulted `let` is dropped from the
        // memberwise init), so Key(promptUuid:) call sites keep compiling.
        var code: String? = nil

        /// The code-agnostic identity of this surface's TARGET — the key
        /// under which DOPE_LIST candidates and the user's pick are stored.
        /// `Key(promptUuid: nil)` is both the session tab's own target AND
        /// the SESSION_BASE candidate bucket every prompt surface consults
        /// for its DOPE_GET fallback: one entry, shared by both surfaces.
        var target: Key { Key(promptUuid: promptUuid) }
    }

    /// Mirrors PromptPhaseStore.Phase with TWO deliberate additions.
    enum Phase: Equatable {
        case idle
        /// No dope scope exists for this session/prompt yet — the NORMAL
        /// pre-init state, never an error banner.
        case absent
        case loaded(DopeGetResponse)
        /// `pick()` BAD_REQUEST: several scopes match and no code was passed.
        /// Now the daemon-side BACKSTOP, not the UI's answer — the store
        /// enumerates DOPE_LIST before every read and pins the first
        /// candidate when the target is ambiguous, so this arm is reached
        /// only if that enumeration itself failed. The pane renders the scope
        /// picker here; the daemon's candidate-naming message is the
        /// last-resort fallback.
        case needsCode(daemonMessage: String)
        case failed(String)
    }

    let sessionUuid: String
    private(set) var phases: [Key: Phase] = [:]
    /// Last DOPE_READ_REPO result per surface (drift + warnings banner).
    private(set) var repoReads: [Key: DopeReadRepoResponse] = [:]
    private(set) var repoIssues: [Key: String] = [:]
    private(set) var repoBusy: Set<Key> = []
    /// DOPE_LIST rows per TARGET (`Key.target`). A prompt surface consults
    /// TWO entries — its own PROMPT scopes, and the SESSION_BASE scopes its
    /// DOPE_GET falls back to (without which a fallback-side ambiguity would
    /// be unpickable). Enumeration is an ENHANCEMENT: its failure never
    /// touches a tree phase.
    private(set) var scopeCandidates: [Key: [DopeScopeRow]] = [:]
    /// The user's explicit pick per target; absent ⇒ daemon resolution order.
    private(set) var selectedCodes: [Key: String] = [:]

    private let service = GMCCDaemonService.shared
    // Per-key single flight, CHAINED like PromptPhaseStore.chainedRun — a
    // load issued after a write must never be satisfied by a fetch that
    // started before it (JOINING would answer a post-write wake with
    // pre-write data). The slot-clear is token-guarded so a finished
    // predecessor can't clobber a chained successor's bookkeeping.
    private var inFlight: [Key: (task: Task<Void, Never>, token: UUID)] = [:]
    /// Candidate fetches JOIN rather than chain — DOPE_LIST is a pure
    /// enumeration with no read-after-write ordering requirement.
    private var candidatesInFlight: [Key: Task<Void, Never>] = [:]
    /// Live observation refcounts (DopePane .task lifetimes). Event wakes
    /// reload only observed keys — `phases` caches every key ever read (the
    /// scope + grace list keep this store alive), so iterating it would fan
    /// one DOPE_CHANGE out to every prompt card ever opened.
    private var observers: [Key: Int] = [:]

    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }

    func phase(_ key: Key) -> Phase {
        phases[key] ?? .idle
    }

    /// A pane's event loop is up for this TARGET (code-nil Key — the pane's
    /// selected code can change while mounted, so observation is registered
    /// against the stable target and `reloadLive` re-resolves the selection).
    /// Balanced by `endObserving` via the pane's `.task` cancellation
    /// (contractually paired).
    func beginObserving(_ key: Key) {
        observers[key, default: 0] += 1
    }

    func endObserving(_ key: Key) {
        guard let count = observers[key], count > 0 else {
            assertionFailure("unbalanced DopeStore.endObserving(\(key))")
            return
        }
        if count == 1 { observers[key] = nil } else { observers[key] = count - 1 }
    }

    // MARK: - Scope enumeration (DOPE_LIST)

    func candidates(for target: Key) -> [DopeScopeRow] {
        scopeCandidates[target] ?? []
    }

    /// This target's OWN scopes (empty on the session tab, whose own scopes
    /// ARE the session-base list below).
    func promptCandidates(_ target: Key) -> [DopeScopeRow] {
        target.promptUuid == nil ? [] : candidates(for: target)
    }

    func sessionCandidates(_ target: Key) -> [DopeScopeRow] {
        candidates(for: Key(promptUuid: nil))
    }

    /// The key a surface should render RIGHT NOW: the target plus whatever
    /// code `resolvedCode` pins for it.
    func key(for promptUuid: String?) -> Key {
        let target = Key(promptUuid: promptUuid)
        return Key(promptUuid: promptUuid, code: resolvedCode(target))
    }

    /// Mirrors the daemon's pick() EXACTLY: ambiguity is per scope TYPE and
    /// PROMPT is consulted before SESSION_BASE. Pinning the first candidate
    /// of an ambiguous set (DOPE_LIST is ORDER BY code, so it is
    /// deterministic and matches the order the BAD_REQUEST message would
    /// have printed) preempts the dead end; the picker shows what was pinned.
    private func resolvedCode(_ target: Key) -> String? {
        let prompts = promptCandidates(target)
        let sessions = sessionCandidates(target)
        if let chosen = selectedCodes[target],
           (prompts + sessions).contains(where: { $0.code == chosen }) {
            return chosen
        }
        if prompts.count > 1 { return prompts.first?.code }
        if prompts.isEmpty, sessions.count > 1 { return sessions.first?.code }
        return nil
    }

    /// THE surface entry point (replaces a bare `load` at the mount site):
    /// enumerate first so the picker and the disambiguating pin both exist
    /// before the tree read is issued.
    func refresh(promptUuid: String?) async {
        let target = Key(promptUuid: promptUuid)
        await loadCandidates(target)
        if target.promptUuid != nil {
            await loadCandidates(Key(promptUuid: nil))
        }
        await load(key(for: promptUuid))
    }

    /// The user's picker choice; nil restores automatic (daemon) resolution.
    func select(_ code: String?, for target: Key) async {
        if let code {
            selectedCodes[target] = code
        } else {
            selectedCodes.removeValue(forKey: target)
        }
        await load(key(for: target.promptUuid))
    }

    private func loadCandidates(_ target: Key) async {
        if let running = candidatesInFlight[target] {
            await running.value
            return
        }
        let task = Task { await self.performListLoad(target) }
        candidatesInFlight[target] = task
        await task.value
        candidatesInFlight[target] = nil
    }

    private func performListLoad(_ target: Key) async {
        do {
            let response = try await service.dopeList(
                sessionUuid: sessionUuid, promptUuid: target.promptUuid)
            if scopeCandidates[target] != response.scopes {
                scopeCandidates[target] = response.scopes
            }
        } catch {
            // Deliberately silent: the picker and the sibling-code hints are
            // additive. Keep the last known rows; performLoad reports
            // anything that actually matters to the user.
            if scopeCandidates[target] == nil {
                scopeCandidates[target] = []
            }
        }
    }

    // MARK: - Tree reads (DOPE_GET)

    /// Chain, never join or race: a new pass starts AFTER whatever is in
    /// flight for the key, so its fetch observes every write that preceded
    /// the call.
    func load(_ key: Key) async {
        let prior = inFlight[key]?.task
        let token = UUID()
        let task = Task {
            await prior?.value
            await self.performLoad(key)
        }
        inFlight[key] = (task, token)
        await task.value
        if inFlight[key]?.token == token { inFlight[key] = nil }
    }

    /// Event wake: DOPE_CHANGE landed for this session — for every TARGET a
    /// live pane is observing (bounded by mounted surfaces, not by history),
    /// refresh its candidate list then reload its currently-selected key.
    /// The payload's scope uuid is not deliverable through the Void hub
    /// stream, and with the SESSION_BASE fallback in play a per-scope
    /// narrowing could skip a surface rendering the fallback tree anyway.
    func reloadLive() async {
        var targets = Set(observers.keys.map(\.target))
        // A live prompt surface's DOPE_GET can fall back to session base, so
        // its candidate list must be fresh even when no session tab is up.
        if targets.contains(where: { $0.promptUuid != nil }) {
            targets.insert(Key(promptUuid: nil))
        }
        for target in targets {
            await loadCandidates(target)
        }
        for target in Set(observers.keys.map(\.target)) {
            await load(key(for: target.promptUuid))
        }
    }

    private func performLoad(_ key: Key) async {
        let next: Phase
        do {
            next = .loaded(try await service.dopeGet(
                sessionUuid: sessionUuid, promptUuid: key.promptUuid,
                code: key.code))
        } catch DaemonError.summaryAbsent {
            next = .absent
        } catch DaemonError.server(let code, let message) where code == "BAD_REQUEST" {
            next = .needsCode(daemonMessage: message)
        } catch let error as DaemonError {
            next = .failed(error.userMessage)
        } catch {
            next = .failed(String(describing: error))
        }
        if phases[key] != next { phases[key] = next }
        // A reload means the db side may have moved — a retained Read Repo
        // banner would keep asserting a drift verdict against a superseded
        // db revision. Drop it; the user re-runs Read Repo for a fresh one.
        if repoReads[key] != nil { repoReads[key] = nil }
        if repoIssues[key] != nil { repoIssues[key] = nil }
    }

    /// Validate the on-disk dope tree for the loaded scope. Never writes —
    /// the response's drift flag + warnings are exactly the read-only banner.
    func readRepo(_ key: Key) async {
        guard case .loaded(let response) = phase(key) else { return }
        guard !repoBusy.contains(key) else { return }
        repoBusy.insert(key)
        defer { repoBusy.remove(key) }
        do {
            let read = try await service.dopeReadRepo(scopeUuid: response.tree.identity.uuid)
            repoReads[key] = read
            repoIssues[key] = nil
        } catch let error as DaemonError {
            repoIssues[key] = error.userMessage
        } catch {
            repoIssues[key] = String(describing: error)
        }
    }

    /// DOPE_INIT (idempotent create-or-return). Throws typed DaemonError for
    /// the sheet to render; a success reloads the surface.
    func initScope(key: Key, code: String, name: String, description: String) async throws {
        _ = try await service.dopeInit(DopeInitRequest(
            sessionUuid: sessionUuid,
            promptUuid: key.promptUuid,
            code: code,
            name: name,
            description: description.isEmpty ? nil : description
        ))
        // Pin what was just created: without this, a second scope on an
        // already-populated target would resolve to the alphabetically first
        // candidate — the opposite of what the user just asked for.
        selectedCodes[key.target] = code
        await loadCandidates(key.target)
        await load(Key(promptUuid: key.promptUuid, code: code))
    }
}
