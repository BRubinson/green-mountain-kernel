import Foundation
import GMCCDaemonKit

// BRIEFING_* (v21) — thin decode-and-delegate shims over Store+Briefing, one
// file for the family (the DiagramHandlers precedent).

/// BRIEFING_OPEN — reserve (or reset-to-building) the row for one
/// (owner, step) pair. Exactly one owner flag.
enum BriefingOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BriefingOpenRequest.self, from: line)
        return try okResult(.briefingOpen, head, try store.briefingOpen(request))
    }
}

/// BRIEFING_COMPLETE — building → ready; the daemon stamps the staleness
/// evidence and denormalizes kbite briefs itself.
enum BriefingCompleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BriefingCompleteRequest.self, from: line)
        // A briefing that omits a ref class entirely is refused before
        // anything is written — absent and empty are different answers, and
        // only one of them is a record of having looked.
        try BriefingCompletenessRule.check(request)
        return try okResult(.briefingComplete, head, try store.briefingComplete(request))
    }
}

/// BRIEFING_GET — one row + live-computed staleness (drift + ghost paths).
enum BriefingGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BriefingGetRequest.self, from: line)
        return try okResult(.briefingGet, head, try store.briefingGet(request))
    }
}

/// BRIEFING_LIST — all rows for a prompt or a session; empty is normal.
enum BriefingListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BriefingListRequest.self, from: line)
        return try okResult(.briefingList, head, try store.briefingList(request))
    }
}

/// BRIEFING_STUB — the SubagentStart hook's one call; empty stub when nothing
/// applies (a hook must never wedge a spawn).
enum BriefingStubHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BriefingStubRequest.self, from: line)
        return try okResult(.briefingStub, head, try store.briefingStub(request))
    }
}
