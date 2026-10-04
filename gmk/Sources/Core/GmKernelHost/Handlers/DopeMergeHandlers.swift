import Foundation

/// DOPE_MERGE_PLAN — read-only per-element plan of the db tree against the
/// on-disk tree, judged from the stored base.
///
/// Never ingests, never writes files: reporting a conflict must not itself be
/// a mutation.
enum DopeMergePlanHandler {
    /// Handles DOPE_MERGE_PLAN command to report a conflict plan.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the merge plan response.
    /// - Throws: Errors from payload decoding or store access.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeMergePlanRequest.self, from: line)
        let plan = try store.dopeMergePlan(scopeUuid: request.scopeUuid)
        let rows = plan.map {
            DopeMergeOutcomeRow(
                dotPath: $0.dotPath,
                kind: $0.kind,
                decision: $0.decision.rawValue
            )
        }
        return try okResult(
            .dopeMergePlan,
            head,
            DopeMergePlanResponse(
                outcomes: rows,
                conflictCount: DopeMerge.conflicts(in: plan).count
            )
        )
    }
}

/// DOPE_RESOLVE — settle conflicting dot-paths by re-basing provenance, so
/// the next plan is clean in the chosen direction.
enum DopeResolveHandler {
    /// Handles DOPE_RESOLVE command to settle a merge conflict.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the resolve response.
    /// - Throws: Errors from payload decoding or store access.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeResolveRequest.self, from: line)
        let resolved = try store.dopeResolve(
            scopeUuid: request.scopeUuid,
            dotPath: request.dotPath,
            takeOurs: request.takeOurs
        )
        return try okResult(
            .dopeResolve,
            head,
            DopeResolveResponse(
                resolved: resolved,
                takeOurs: request.takeOurs
            )
        )
    }
}
