import Foundation
import GRDB

// REVIEW_* — the db-native review report machine. reviewing → complete, plus the
// complete → reviewing revision edge. Open is EXPLICIT-only, and review verbs
// NEVER touch prompt.status.
// Same finding_rating semantics as Store+Exploration, with two divergences from
// the clarify template: overview AND verdict are carried only by COMPLETE, and
// reviewResolve is UNGATED on summary status, because the fix loop mutates
// finding status after the summary completes and a reopen mid-loop must not
// strand in-flight resolves. Bodies live in ReviewRepository.

extension Store {
    /// Opens a review and returns its initial summary.
    ///
    /// - Parameter req: The review open request.
    /// - Returns: The initial review summary.
    /// - Throws: Store errors if the request is invalid.
    func reviewOpen(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).open(req) }
    }

    /// Adds a finding to a review.
    ///
    /// - Parameter req: The finding add request.
    /// - Returns: The added finding row.
    /// - Throws: Store errors if the request is invalid.
    func reviewFindingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).findingAdd(req) }
    }

    /// Ranks findings in a review.
    ///
    /// - Parameter req: The rank request.
    /// - Returns: The ranking result.
    /// - Throws: Store errors if the request is invalid.
    func reviewRank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).rank(req) }
    }

    /// Resolves a finding in a review.
    ///
    /// - Parameter req: The resolve request.
    /// - Returns: The resolved finding row.
    /// - Throws: Store errors if the request is invalid.
    func reviewResolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).resolve(req) }
    }

    /// Completes a review.
    ///
    /// - Parameter req: The complete request.
    /// - Returns: The review summary after completion.
    /// - Throws: Store errors if the request is invalid.
    func reviewComplete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).complete(req) }
    }

    /// Reopens a completed review.
    ///
    /// - Parameter req: The reopen request.
    /// - Returns: The review summary after reopening.
    /// - Throws: Store errors if the request is invalid.
    func reviewReopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).reopen(req) }
    }

    /// Reads a review and its findings.
    ///
    /// - Parameter req: The get request.
    /// - Returns: The review data.
    /// - Throws: Store errors if the request is invalid.
    func reviewGet(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        try boundaryRead { db in try ReviewRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

}
