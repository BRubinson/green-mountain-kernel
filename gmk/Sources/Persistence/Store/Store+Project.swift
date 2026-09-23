import Foundation
import GRDB

// PROJECT_UPDATE — the project-level mutation. The project table carries exactly
// one settable field: primary_project_branch, the branch whose SESSION_INSTANCE
// dope scope may promote into the project's BASE_PROJECT scope. It is a project
// setting rather than an instance one so it applies consistently across
// instances. Standard optimistic-lock shape, identical to updateSession. Bodies
// live in ProjectRepository; these wrappers own the transaction.

extension Store {
    /// Updates a project's configuration with optimistic locking.
    ///
    /// - Parameter req: The update request with new project data and expected version.
    /// - Returns: The updated project row.
    /// - Throws: Store errors or version conflict errors.
    func updateProject(_ req: ProjectUpdateRequest) throws -> ProjectRow {
        try boundary { db in
            try ProjectRepository(db: db, core: core).update(req)
        }
    }

}
