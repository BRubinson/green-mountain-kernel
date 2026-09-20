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
    func reviewOpen(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).open(req) }
    }

    func reviewFindingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).findingAdd(req) }
    }

    func reviewRank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).rank(req) }
    }

    func reviewResolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).resolve(req) }
    }

    func reviewComplete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).complete(req) }
    }

    func reviewReopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        try boundary { db in try ReviewRepository(db: db, core: core).reopen(req) }
    }

    func reviewGet(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        try boundaryRead { db in try ReviewRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

}
