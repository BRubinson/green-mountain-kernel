import Foundation

/// Per-domain multicast invalidation signals.
///
/// A view's visibility-scoped `.task` awaits a domain stream instead of
/// sleeping. Streams coalesce with `.bufferingNewest(1)`: a capped event
/// replay can deliver thousands of events, and subscribers must wake once, not
/// N times.
@MainActor
final class InvalidationHub {
    enum Domain: Hashable {
        case topology
        case session(String)
        case prompt(String)
        case changes
        /// PROMPT_MEMORY_CHANGED for one prompt's memory/ dir. The event is
        /// ephemeral (id 0, no replay) — disconnect-window changes are lost,
        /// so subscribers must also refetch on the generation bump (which
        /// `invalidateAll()` covers by yielding every domain).
        case memories(String)
        /// PATHS_GET inputs changed (CONFIG_SET) — the env should refetch.
        case paths
        /// DOPE_CHANGE for one session's dope surfaces. Deliberately NOT
        /// `.session`: SessionStore.refresh is coalesced but not debounced, and
        /// a bot's N-node dope write would fire N SESSION_GET + PROMPT_LIST +
        /// prefetch passes on the serial daemon queue. Dope stores subscribe
        /// here; the scope uuid rides the payload for them to narrow on.
        case dope(String)
        /// DIAGRAM_CHANGE for ONE diagram (the event's subject uuid) — the
        /// open editor's stream. Separate from `.diagramList` because a drag
        /// commit must repaint the canvas it came from without re-listing
        /// every rail in the app.
        case diagram(String)
        /// DIAGRAM_CHANGE for one OWNER row (project / session / prompt uuid)
        /// — the tier-scoped lists. One event yields on every owner uuid its
        /// payload carries, since a prompt-tier write moves the prompt's
        /// count and nothing else in the chain.
        case diagramList(String)
    }

    private var continuations: [Domain: [UUID: AsyncStream<Void>.Continuation]] = [:]

    /// Returns an async stream for invalidation signals in a domain.
    /// - Parameter domain: The invalidation domain to observe.
    /// - Returns: An async stream yielding on domain invalidations.
    func stream(for domain: Domain) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let token = UUID()
            continuations[domain, default: [:]][token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.continuations[domain]?[token] = nil
                    // Prune empty buckets so per-session/per-prompt keys don't
                    // accumulate for the life of the process.
                    if self.continuations[domain]?.isEmpty == true {
                        self.continuations[domain] = nil
                    }
                }
            }
        }
    }

    /// Signals invalidation to all observers in a domain.
    /// - Parameter domain: The invalidation domain to signal.
    func invalidate(_ domain: Domain) {
        continuations[domain]?.values.forEach { $0.yield() }
    }

    /// Signals all session-domain observers as a degradation path.
    ///
    /// UPDATE_PROMPT, PROMPT_STATUS_CHANGE, CREATE_PROMPT and FILE_CHANGE may
    /// lack a session UUID on the wire or in pre-v7 replayed rows. This method
    /// fans out to every open session observer in those cases.
    func invalidateAllSessions() {
        for (domain, conts) in continuations {
            if case .session = domain {
                conts.values.forEach { $0.yield() }
            }
        }
    }

    /// Signals all prompt-domain observers as a degradation path.
    ///
    /// REVIEW_CHANGE events with action "resolve" omit the prompt UUID on the
    /// wire. This method fans out to every prompt observer as a workaround.
    /// Delete this when the daemon adds the field.
    func invalidateAllPrompts() {
        for (domain, conts) in continuations {
            if case .prompt = domain {
                conts.values.forEach { $0.yield() }
            }
        }
    }

    /// Signals all dope-domain observers as a degradation path.
    ///
    /// DOPE_CHANGE rows defensively fan out when the payload lacks a session
    /// UUID, though recordDopeChange always writes it.
    func invalidateAllDope() {
        for (domain, conts) in continuations {
            if case .dope = domain {
                conts.values.forEach { $0.yield() }
            }
        }
    }

    /// Signals all observers across all domains as a resync barrier.
    ///
    /// Fired when the connection comes back up, so visible surfaces refetch
    /// once instead of trusting a possibly-gapped stream.
    func invalidateAll() {
        continuations.values.forEach { $0.values.forEach { $0.yield() } }
    }
}
