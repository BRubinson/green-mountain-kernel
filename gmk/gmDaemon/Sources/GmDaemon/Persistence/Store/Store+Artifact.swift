import Foundation
import GRDB
import GmDaemonSdk

// ARTIFACT_ADD / ARTIFACT_LIST — file pointers for bot-phase memory/ files.
// Content stays in the files; the db stores only pointers.
// Bodies live in ArtifactRepository; these wrappers own the transaction.

extension Store {
    public func addArtifact(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        try boundary { db in try ArtifactRepository(db: db, core: core).add(req) }
    }

    public func listArtifacts(_ req: ArtifactListRequest) throws -> ArtifactListResponse {
        try boundaryRead { db in
            ArtifactListResponse(
                artifacts: try ArtifactRepository(db: db, core: core).fetchRows(promptUuid: req.promptUuid))
        }
    }

    // MARK: - Cross-domain helper forwards

}
