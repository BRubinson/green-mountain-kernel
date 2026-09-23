import Foundation
import Observation

/// Read model over DOPE_LIST + DOPE_GET + DOPE_READ_REPO, plus the one DOPE_INIT write.
///
/// Scope-level, one per `SessionScope`, serving both dope surfaces rather than prompt-keyed:
/// DOPE_GET with a promptUuid falls back to the SESSION_BASE tree (`resolvedVia` reports which
/// answered), so the two surfaces routinely render the same tree and one event wake reloads
/// every live key. Refresh rides the `.dope(sessionUuid)` hub domain, never `.session`, which
/// would storm SESSION_GET per node write.
@Observable
@MainActor
final class DopeStore {
    /// One read surface: `promptUuid` picks the TARGET (nil ⇒ the session's
    /// SESSION_BASE read; a prompt uuid ⇒ the prompt-preferred read, which MAY
    /// resolve to session base — see `resolvedVia`).
    ///
    /// `code` PINS one scope when the target has several; nil hands resolution
    /// to the daemon. Each scope gets its own cached entry — phases, repo reads
    /// and repo issues keyed by the full Key, so scope switching never shows
    /// another scope's stale tree or drift banner.
    struct Key: Hashable {
        let promptUuid: String?
        // `var` with a default (a defaulted `let` is dropped from the
        // memberwise init), so Key(promptUuid:) call sites keep compiling.
        var code: String?

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
    /// DOPE_LIST rows per TARGET (`Key.target`).
    ///
    /// A prompt surface consults TWO entries — its own PROMPT scopes, and the
    /// SESSION_BASE scopes its DOPE_GET falls back to (without which a
    /// fallback-side ambiguity would be unpickable). Enumeration is an
    /// ENHANCEMENT: its failure never touches a tree phase.
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
    /// Live observation refcounts (DopePane .task lifetimes).
    ///
    /// Event wakes reload only observed keys — `phases` caches every key ever
    /// read (the scope + grace list keep this store alive), so iterating it
    /// would fan one DOPE_CHANGE out to every prompt card ever opened.
    private var observers: [Key: Int] = [:]

    /// Creates a store for a session's dope scopes.
    ///
    /// - Parameter sessionUuid: The session identifier.
    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }

    /// The phase of the dope scope for the key.
    ///
    /// - Parameter key: The surface identifier and optional scope code.
    /// - Returns: The current phase, or `.idle` if not yet loaded.
    func phase(_ key: Key) -> Phase {
        phases[key] ?? .idle
    }

    /// Registers the pane's event loop for updates to this target.
    ///
    /// The pane's selected code can change while mounted, so observation is
    /// registered against the stable target and `reloadLive` re-resolves the
    /// selection. Balanced by `endObserving` via the pane's `.task`
    /// cancellation (contractually paired).
    ///
    /// - Parameter key: The target's code-nil key for observation.
    func beginObserving(_ key: Key) {
        observers[key, default: 0] += 1
    }

    /// Unregisters the pane's event loop from updates to this target.
    ///
    /// - Parameter key: The target's code-nil key from `beginObserving`.
    func endObserving(_ key: Key) {
        guard let count = observers[key], count > 0 else {
            assertionFailure("unbalanced DopeStore.endObserving(\(key))")
            return
        }
        if count == 1 { observers[key] = nil } else { observers[key] = count - 1 }
    }

    // MARK: - Scope enumeration (DOPE_LIST)

    /// The enumerated dope scopes for this target.
    ///
    /// - Parameter target: The target key (code-nil).
    /// - Returns: The scope candidates, or empty if not yet enumerated.
    func candidates(for target: Key) -> [DopeScopeRow] {
        scopeCandidates[target] ?? []
    }

    /// The scopes owned by this target.
    ///
    /// Empty on the session tab, whose own scopes are the session-base list.
    ///
    /// - Parameter target: The target key.
    /// - Returns: The prompt-owned scope candidates for the target.
    func promptCandidates(_ target: Key) -> [DopeScopeRow] {
        target.promptUuid == nil ? [] : candidates(for: target)
    }

    /// The session-base scopes available to any prompt surface.
    ///
    /// - Parameter _: Unused; identifies the target context.
    /// - Returns: The session-base scope candidates.
    func sessionCandidates(_: Key) -> [DopeScopeRow] {
        candidates(for: Key(promptUuid: nil))
    }

    /// The surface's current rendering key.
    ///
    /// The target plus whatever code `resolvedCode` pins for it.
    ///
    /// - Parameter promptUuid: The prompt identifier for the target.
    /// - Returns: The combined key with resolved code.
    func key(for promptUuid: String?) -> Key {
        let target = Key(promptUuid: promptUuid)
        return Key(promptUuid: promptUuid, code: resolvedCode(target))
    }

    /// Resolves the code for ambiguous scopes.
    ///
    /// Mirrors the daemon's pick() exactly: ambiguity is per scope type,
    /// and prompts are consulted before session base. Pinning the first
    /// candidate of an ambiguous set (DOPE_LIST is ordered by code, so it
    /// is deterministic and matches the order the BAD_REQUEST message would
    /// have printed) preempts the dead end; the picker shows what was pinned.
    ///
    /// - Parameter target: The target key to resolve code for.
    /// - Returns: The resolved code, or nil if unambiguous.
    private func resolvedCode(_ target: Key) -> String? {
        let prompts = promptCandidates(target)
        let sessions = sessionCandidates(target)
        if let chosen = selectedCodes[target],
            (prompts + sessions).contains(where: { $0.code == chosen })
        {
            return chosen
        }
        if prompts.count > 1 { return prompts.first?.code }
        if prompts.isEmpty, sessions.count > 1 { return sessions.first?.code }
        return nil
    }

    /// The surface entry point for rendering.
    ///
    /// Enumerates candidates first so the picker and the disambiguating pin
    /// both exist before the tree read is issued, replacing a bare `load` at
    /// the mount site.
    ///
    /// - Parameter promptUuid: The prompt identifier for the surface.
    func refresh(promptUuid: String?) async {
        let target = Key(promptUuid: promptUuid)
        await loadCandidates(target)
        if target.promptUuid != nil {
            await loadCandidates(Key(promptUuid: nil))
        }
        await load(key(for: promptUuid))
    }

    /// The user's picker choice; nil restores automatic (daemon) resolution.
    ///
    /// - Parameters:
    ///   - code: The code to select, or nil for automatic resolution.
    ///   - target: The target key identifying the surface.
    func select(_ code: String?, for target: Key) async {
        if let code {
            selectedCodes[target] = code
        } else {
            selectedCodes.removeValue(forKey: target)
        }
        await load(key(for: target.promptUuid))
    }

    /// Loads the dope scope candidates for a target.
    ///
    /// Joins existing fetches rather than chaining; DOPE_LIST is a pure
    /// enumeration with no read-after-write ordering requirement.
    ///
    /// - Parameter target: The target key to fetch candidates for.
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

    /// Fetches the dope scope candidates from the daemon.
    ///
    /// Errors are deliberately silent: the picker and sibling-code hints are
    /// additive. The last known rows are kept; `performLoad` reports anything
    /// that actually matters to the user.
    ///
    /// - Parameter target: The target key to fetch candidates for.
    private func performListLoad(_ target: Key) async {
        do {
            let response = try await service.dopeList(
                sessionUuid: sessionUuid,
                promptUuid: target.promptUuid
            )
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

    /// Loads the dope tree, chaining after prior fetches.
    ///
    /// A new pass starts after whatever is in flight for the key, so its
    /// fetch observes every write that preceded the call.
    ///
    /// - Parameter key: The surface key to load.
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

    /// Reloads live surfaces on dope changes.
    ///
    /// On DOPE_CHANGE event: for every target a live pane is observing
    /// (bounded by mounted surfaces, not by history), refresh its candidate
    /// list then reload its currently-selected key. The payload's scope uuid
    /// is not deliverable through the Void hub stream, and with the
    /// SESSION_BASE fallback in play a per-scope narrowing could skip a
    /// surface rendering the fallback tree anyway.
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

    /// Fetches the dope tree from the daemon and caches the result.
    ///
    /// Clears cached repo reads and issues on reload since the db side may
    /// have moved; a retained Read Repo banner would keep asserting a drift
    /// verdict against a superseded db revision.
    ///
    /// - Parameter key: The surface key to fetch.
    private func performLoad(_ key: Key) async {
        let next: Phase
        do {
            next = .loaded(
                try await service.dopeGet(
                    sessionUuid: sessionUuid,
                    promptUuid: key.promptUuid,
                    code: key.code
                )
            )
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

    /// Validate the on-disk dope tree for the loaded scope.
    ///
    /// Never writes — the response's drift flag + warnings are exactly the
    /// read-only banner.
    ///
    /// - Parameter key: The surface key to validate.
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

    /// Creates or returns a dope scope with the given attributes.
    ///
    /// Idempotent create-or-return; a success reloads the surface.
    ///
    /// - Parameters:
    ///   - key: The target key for the scope.
    ///   - code: The unique code for the scope.
    ///   - name: The human-readable name.
    ///   - description: Optional description of the scope.
    /// - Throws: Typed `DaemonError` for the sheet to render.
    func initScope(key: Key, code: String, name: String, description: String) async throws {
        _ = try await service.dopeInit(
            DopeInitRequest(
                sessionUuid: sessionUuid,
                code: code,
                name: name,
                promptUuid: key.promptUuid,
                description: description.isEmpty ? nil : description
            )
        )
        // Pin what was just created: without this, a second scope on an
        // already-populated target would resolve to the alphabetically first
        // candidate — the opposite of what the user just asked for.
        selectedCodes[key.target] = code
        await loadCandidates(key.target)
        await load(Key(promptUuid: key.promptUuid, code: code))
    }
}
