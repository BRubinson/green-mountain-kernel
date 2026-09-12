import Foundation
import GRDB

// PROJECT_UPDATE — the project-level mutation. The project table carries
// exactly one settable field, which is why PROJECT_LIST long stood alone.
//
// Today the single settable field is primary_project_branch (the prompt's
// BASE_DOPED_BRANCH): the branch whose SESSION_INSTANCE dope scope is
// allowed to promote into the project's BASE_PROJECT scope. It is a project
// setting rather than an instance one on purpose — it "applies across
// instances a consistent behavior".
//
// Standard optimistic-lock shape, identical to updateSession. Bodies live in
// ProjectRepository; these wrappers own the transaction.

extension Store {
    public func updateProject(_ req: ProjectUpdateRequest) throws -> ProjectRow {
        try dbQueue.write { db in
            try ProjectRepository(db: db, core: core).update(req)
        }
    }

}
