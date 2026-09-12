import Foundation
import GRDB

// REVIEW_* — the db-native review report machine (replaces review.md).
// reviewing → complete, plus the complete → reviewing revision edge. Open is
// EXPLICIT-only: prompt status transitions never create or gate on this
// summary (skip-to-done stays legal). Review verbs NEVER touch prompt.status.
//
// Same finding_rating semantics as Store+Exploration. Two deliberate
// divergences from the clarify template, both by design:
// - overview AND verdict are carried only by COMPLETE (primary-agent-only by
//   write-path shape; verdict `legacy_unstated` exists for the verbatim
//   migration of pre-m0004 review files that never state one).
// - reviewResolve is UNGATED on summary status — the fix loop mutates finding
//   status AFTER the summary completes, and a reopen mid-loop must not strand
//   in-flight resolves (the inversion of the clarify child-lock).
//
// Bodies live in ReviewRepository; these wrappers own the transaction.

extension Store {
    public func reviewOpen(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        try dbQueue.write { db in try ReviewRepository(db: db, core: core).open(req) }
    }

    public func reviewFindingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        try dbQueue.write { db in try ReviewRepository(db: db, core: core).findingAdd(req) }
    }

    public func reviewRank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        try dbQueue.write { db in try ReviewRepository(db: db, core: core).rank(req) }
    }

    public func reviewResolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        try dbQueue.write { db in try ReviewRepository(db: db, core: core).resolve(req) }
    }

    public func reviewComplete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        try dbQueue.write { db in try ReviewRepository(db: db, core: core).complete(req) }
    }

    public func reviewReopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        try dbQueue.write { db in try ReviewRepository(db: db, core: core).reopen(req) }
    }

    public func reviewGet(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        try dbQueue.read { db in try ReviewRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards



}
