// The one place identity-spine persistence types meet the wire DTOs.
//
// Every conversion is a `dto()` on the persistence side. Wire Rows stay free
// of GRDB conformances and of custom decoding.

import Foundation

extension SessionSummary {
    /// db → wire.
    func dto() -> SessionStub {
        SessionStub(
            uuid: session.uuid,
            version: session.version,
            instanceUuid: session.instanceUuid,
            code: session.code,
            name: session.name,
            gmfsRelativeStoragePath: session.gmfsRelativeStoragePath,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            lastActivityAt: lastActivityAt
        )
    }
}
