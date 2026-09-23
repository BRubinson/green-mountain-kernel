import Foundation

/// The SERVICES half of the component library: GMVibes (or any host)
/// implements `DiagramCommitting` over its vendored DaemonClient and hands it to
/// a `DiagramEditSession`, which accumulates typed mutations during a gesture and
/// flushes them as ONE DIAGRAM_BATCH_APPLY at gesture end (optionally CAS-guarded
/// by the last-seen revision).
///
/// The library never instantiates a client — components consume values, hosts own
/// transport.
protocol DiagramCommitting: Sendable {
    /// Applies mutations atomically and returns the new diagram revision.
    /// - Parameters:
    ///   - mutations: The diagram mutations to apply.
    ///   - expectedRevision: The revision to guard against concurrent changes, or nil to skip.
    /// - Returns: The new diagram revision after applying mutations.
    /// - Throws: An error if the commit fails or the revision guard fails.
    func commit(_ mutations: [DiagramMutation], expectedRevision: Int64?) async throws -> Int64

    /// Applies mutations and reports new revision and minted UUIDs.
    ///
    /// A batch names rows it creates by clientRef because the WRITER mints the
    /// uuid, so a client that adds an element and then wants to select, update or
    /// connect it has no other handle on the row. A daemon committer must report
    /// back what the db minted rather than inventing ids no row has. Defaulted onto
    /// `commit` so a revision-only conformer keeps compiling untouched.
    ///
    /// - Parameters:
    ///   - mutations: The diagram mutations to apply.
    ///   - expectedRevision: The revision to guard against concurrent changes, or nil to skip.
    /// - Returns: The commit outcome with new revision and minted UUIDs.
    /// - Throws: An error if the commit fails or the revision guard fails.
    func commitReporting(
        _ mutations: [DiagramMutation],
        expectedRevision: Int64?
    ) async throws -> DiagramCommitOutcome
}

/// What one commit reports back. `revision` advances the CAS gate; the
/// minted uuids are keyed by the `clientRef` of the `elementAdd` that
/// produced them (adds without a clientRef are not addressable and are
/// deliberately absent).
struct DiagramCommitOutcome: Hashable, Sendable {
    let revision: Int64
    let mintedUuids: [String: String]

    /// Creates a commit outcome with a revision and optional minted UUIDs.
    /// - Parameters:
    ///   - revision: The new diagram revision.
    ///   - mintedUuids: UUIDs minted by the commit, keyed by client reference.
    init(revision: Int64, mintedUuids: [String: String] = [:]) {
        self.revision = revision
        self.mintedUuids = mintedUuids
    }
}

extension DiagramCommitting {
    /// Default implementation that wraps `commit` with empty minted UUIDs.
    /// - Parameters:
    ///   - mutations: The diagram mutations to apply.
    ///   - expectedRevision: The revision to guard against concurrent changes, or nil to skip.
    /// - Returns: The commit outcome with new revision (no minted UUIDs).
    /// - Throws: An error if the commit fails or the revision guard fails.
    func commitReporting(
        _ mutations: [DiagramMutation],
        expectedRevision: Int64?
    ) async throws -> DiagramCommitOutcome {
        DiagramCommitOutcome(
            revision: try await commit(mutations, expectedRevision: expectedRevision)
        )
    }
}

enum DiagramEditSessionError: Error, Sendable {
    /// flush() was called while a previous flush's commit was still awaited —
    /// refused rather than double-committing the same staged prefix.
    case flushInFlight
}

#if canImport(Observation)
import Observation

/// Window-lived staging store for interactive editing: stage mutations per-frame
/// (cheap value appends), flush once at gesture end.
///
/// Absorbing per-frame updates here — never as daemon round trips — is what
/// keeps the single-writer daemon and the revision counter meaningful.
@Observable
final class DiagramEditSession {
    private(set) var staged: [DiagramMutation] = []
    /// The revision the working state was built from; used as the CAS gate
    /// on flush and advanced by every successful commit.
    private(set) var baseRevision: Int64?
    private(set) var lastError: String?
    /// clientRef -> minted uuid from the LAST successful flush.
    ///
    /// The window between a gesture-end add and the caller's follow-up (select
    /// the new element, connect to it) is exactly one flush wide, so one batch's
    /// worth is all any caller has ever needed.
    private(set) var lastMintedUuids: [String: String] = [:]

    private let committer: any DiagramCommitting

    /// Creates a diagram edit session for interactive editing.
    /// - Parameters:
    ///   - committer: The service to apply mutations and report revisions.
    ///   - baseRevision: The initial revision to use as the CAS gate, or nil.
    init(committer: any DiagramCommitting, baseRevision: Int64? = nil) {
        self.committer = committer
        self.baseRevision = baseRevision
    }

    /// Appends a mutation to be applied at gesture end.
    /// - Parameter mutation: The diagram mutation to stage.
    func stage(_ mutation: DiagramMutation) {
        staged.append(mutation)
    }

    /// Replaces or appends a mutation per-frame based on the target element.
    ///
    /// Per-frame collapse: replace the last staged mutation ONLY when it
    /// targets the same element (same kind + element identity); otherwise
    /// append — restaging element A must never clobber a pending edit to
    /// element B.
    ///
    /// - Parameter mutation: The diagram mutation to stage or replace.
    func restage(_ mutation: DiagramMutation) {
        if let last = staged.last, Self.sameTarget(last, mutation) {
            staged[staged.count - 1] = mutation
        } else {
            staged.append(mutation)
        }
    }

    /// Returns true when both mutations target the same element.
    /// - Parameters:
    ///   - a: The first mutation.
    ///   - b: The second mutation.
    /// - Returns: True when both mutations target the same element.
    private static func sameTarget(_ a: DiagramMutation, _ b: DiagramMutation) -> Bool {
        switch (a, b) {
        case (.elementUpdate(let x), .elementUpdate(let y)):
            return x.elementUuid == y.elementUuid
        case (.elementAdd(let x), .elementAdd(let y)):
            return x.clientRef != nil && x.clientRef == y.clientRef
        case (.diagramUpdate, .diagramUpdate):
            return true
        default:
            return false
        }
    }

    /// Clears all staged mutations and invalidates bookkeeping.
    func discard() {
        staged.removeAll()
        // Invalidates any in-flight flush's committed-prefix bookkeeping:
        // everything staged after this point is NEW and must survive that
        // flush's completion (see the generation check in flush()).
        discardGeneration += 1
    }

    private var inFlight = false
    /// Bumped by discard().
    ///
    /// A flush that started before a discard must NOT removeFirst() its
    /// committed prefix afterwards — the prefix is already gone and the removal
    /// would eat post-discard stages (or trap when fewer remain than committed).
    private var discardGeneration = 0

    /// Gesture-end commit: everything staged at call time, one transaction, one
    /// revision.
    ///
    /// Mutations staged DURING the awaited commit stay staged for the next flush
    /// (only the committed prefix is removed), and a second flush while one is in
    /// flight is refused rather than double-committing.
    @discardableResult
    // Runs on the caller's actor: the session is owned by whoever drives it.
    nonisolated(nonsending) func flush(guarded: Bool = true) async throws -> Int64? {
        guard !staged.isEmpty else { return baseRevision }
        guard !inFlight else {
            throw DiagramEditSessionError.flushInFlight
        }
        inFlight = true
        defer { inFlight = false }
        let mutations = staged
        let generation = discardGeneration
        do {
            let outcome = try await committer.commitReporting(
                mutations,
                expectedRevision: guarded ? baseRevision : nil
            )
            let revision = outcome.revision
            lastMintedUuids = outcome.mintedUuids
            if generation == discardGeneration {
                staged.removeFirst(mutations.count)
            }
            // else: a discard landed during the await — the committed prefix
            // is already gone and anything now staged is post-discard work.
            baseRevision = revision
            lastError = nil
            return revision
        } catch {
            lastError = String(describing: error)
            throw error
        }
    }

    /// Re-anchors to a new revision after an external refresh.
    ///
    /// Called when an external event (e.g. a DIAGRAM_CHANGE from another
    /// window) prompts a refetch of the current state.
    ///
    /// - Parameter revision: The new revision to use as the base.
    func rebase(revision: Int64) {
        baseRevision = revision
    }
}
#endif
