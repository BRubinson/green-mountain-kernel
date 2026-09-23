import Foundation
import GRDB

// PROMPT_DIAGRAM_QUALIFY / _GET / _LIST — a prompt's standing reading of a
// rendered diagram (m0022). No status machine and no findings: the row IS the
// report, and the newest reading is the only one worth keeping.
// Bodies live in PromptDiagramRepository; these wrappers own the transaction
// (and the pre-transaction payload validation).

extension Store {
    /// Qualifies and stores a diagram reading for a prompt.
    ///
    /// Validates that the qualification is non-empty, the rendered path is provided, and the
    /// render fingerprint is a valid JSON object before storing the diagram row.
    /// - Parameter req: The qualification request with diagram details.
    /// - Returns: The stored qualified diagram row.
    /// - Throws: `StoreError.badRequest` if validation fails; any error from the repository.
    func promptDiagramQualify(
        _ req: PromptDiagramQualifyRequest
    ) throws -> PromptQualifiedDiagramRow {
        let qualification = req.qualification.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qualification.isEmpty else {
            throw StoreError.badRequest(detail: "qualification is empty")
        }
        guard !req.renderedPath.isEmpty else {
            throw StoreError.badRequest(detail: "rendered_path is empty")
        }
        // Opaque on the wire, but not unexamined: a fingerprint that is not a
        // JSON object cannot be compared against a render sidecar later, and
        // discovering that at read time would make the row silently useless.
        guard let fingerprintData = req.renderFingerprint.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: fingerprintData)) is [String: Any]
        else {
            throw StoreError.badRequest(
                detail: "render_fingerprint must be a JSON object (the render sidecar's contents)"
            )
        }

        return try boundary { db in
            try PromptDiagramRepository(db: db, core: core)
                .qualify(req, qualification: qualification)
        }
    }

    /// Retrieves the qualified diagram for a prompt.
    /// - Parameter req: The retrieval request with the prompt UUID.
    /// - Returns: The qualified diagram row, or nil if no diagram has been stored.
    /// - Throws: Any error from the repository during the read.
    func promptDiagramGet(
        _ req: PromptDiagramGetRequest
    ) throws -> PromptQualifiedDiagramRow {
        try boundaryRead { db in try PromptDiagramRepository(db: db, core: core).get(req) }
    }

    /// Lists qualified diagrams for a given session and optional prompt filter.
    /// - Parameter req: The list request with session UUID and optional prompt UUIDs.
    /// - Returns: A response containing the matching qualified diagram rows.
    /// - Throws: Any error from the repository during the read.
    func promptDiagramList(
        _ req: PromptDiagramListRequest
    ) throws -> PromptDiagramListResponse {
        try boundaryRead { db in try PromptDiagramRepository(db: db, core: core).list(req) }
    }

    // MARK: - Cross-domain helper forwards

}
