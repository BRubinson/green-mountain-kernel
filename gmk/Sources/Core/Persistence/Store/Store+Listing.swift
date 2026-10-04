import Foundation
import GRDB

// PROJECT_LIST / INSTANCE_LIST / SESSION_LIST — read-only enumeration, the
// Landing browse surface. Parent uuids are optional filters: nil lists the
// whole level; a supplied-but-unknown parent is a typed NOT_FOUND, never a
// silent empty list. No daemon_event rows (reads only).
// Bodies live in ListingRepository; these wrappers own the transaction.

extension Store {
    /// Lists all projects in the database.
    ///
    /// - Returns: The list response with all projects.
    /// - Throws: Database errors during the query.
    func listProjects() throws -> ProjectListResponse {
        try boundaryRead { db in try ListingRepository(db: db, core: core).listProjects() }
    }

    /// Lists instances, optionally filtered by project.
    ///
    /// - Parameter req: The list request with optional project filter.
    /// - Returns: The list response with matching instances.
    /// - Throws: `StoreError.notFound` if the project uuid doesn't exist.
    func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        try boundaryRead { db in try ListingRepository(db: db, core: core).listInstances(req) }
    }

    /// Lists sessions, optionally filtered by instance.
    ///
    /// - Parameter req: The list request with optional instance filter.
    /// - Returns: The list response with matching sessions.
    /// - Throws: `StoreError.notFound` if the instance uuid doesn't exist.
    func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        try boundaryRead { db in try ListingRepository(db: db, core: core).listSessions(req) }
    }

}
