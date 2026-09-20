import Foundation
import GRDB

// PROJECT_LIST / INSTANCE_LIST / SESSION_LIST — read-only enumeration, the
// Landing browse surface. Parent uuids are optional filters: nil lists the
// whole level; a supplied-but-unknown parent is a typed NOT_FOUND, never a
// silent empty list. No daemon_event rows (reads only).
// Bodies live in ListingRepository; these wrappers own the transaction.

extension Store {
    func listProjects() throws -> ProjectListResponse {
        try boundaryRead { db in try ListingRepository(db: db, core: core).listProjects() }
    }

    func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        try boundaryRead { db in try ListingRepository(db: db, core: core).listInstances(req) }
    }

    func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        try boundaryRead { db in try ListingRepository(db: db, core: core).listSessions(req) }
    }

}
