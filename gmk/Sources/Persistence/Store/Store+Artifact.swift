import Foundation
import GRDB

// ARTIFACT_ADD / ARTIFACT_LIST — file pointers for bot-phase memory/ files.
// Content stays in the files; the db stores only pointers.
// Bodies live in ArtifactRepository; these wrappers own the transaction.

extension Store {
    /// Adds an artifact file pointer to the store.
    ///
    /// - Parameter req: The artifact add request.
    /// - Returns: The artifact row.
    /// - Throws: Store errors if the request is invalid.
    func addArtifact(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        try boundary { db in try ArtifactRepository(db: db, core: core).add(req) }
    }

    /// Lists artifacts for a prompt.
    ///
    /// - Parameter req: The list request with the prompt uuid.
    /// - Returns: A list of artifact rows.
    /// - Throws: Store errors if the request is invalid.
    func listArtifacts(_ req: ArtifactListRequest) throws -> ArtifactListResponse {
        try boundaryRead { db in
            ArtifactListResponse(
                artifacts: try ArtifactRepository(db: db, core: core).fetchRows(promptUuid: req.promptUuid)
            )
        }
    }

    // MARK: - Cross-domain helper forwards

}
