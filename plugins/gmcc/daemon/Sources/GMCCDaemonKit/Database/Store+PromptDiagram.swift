import Foundation
import GRDB

// PROMPT_DIAGRAM_QUALIFY / _GET / _LIST — a prompt's standing reading of a
// rendered diagram (m0022). No status machine and no findings: the row IS the
// report, and the newest reading is the only one worth keeping.
// Bodies live in PromptDiagramRepository; these wrappers own the transaction
// (and the pre-transaction payload validation).

extension Store {
    public func promptDiagramQualify(
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
              (try? JSONSerialization.jsonObject(with: fingerprintData)) is [String: Any] else {
            throw StoreError.badRequest(
                detail: "render_fingerprint must be a JSON object (the render sidecar's contents)")
        }

        return try dbQueue.write { db in
            try PromptDiagramRepository(db: db, core: core)
                .qualify(req, qualification: qualification)
        }
    }

    public func promptDiagramGet(
        _ req: PromptDiagramGetRequest
    ) throws -> PromptQualifiedDiagramRow {
        try dbQueue.read { db in try PromptDiagramRepository(db: db, core: core).get(req) }
    }

    public func promptDiagramList(
        _ req: PromptDiagramListRequest
    ) throws -> PromptDiagramListResponse {
        try dbQueue.read { db in try PromptDiagramRepository(db: db, core: core).list(req) }
    }

    // MARK: - Cross-domain helper forwards


}
