// The one place a diagram persistence type and a wire DTO meet. Rows.swift
// types gain no GRDB conformance and no custom decoding; the translation lives
// here, as `dto()`.

import Foundation

extension DiagramWithOwner {
    /// db → wire, with the derived instance injected. `visibility` is passed
    /// explicitly rather than leaning on DiagramRow's "PRIVATE" init default.
    func dto() -> DiagramRow {
        DiagramRow(
            uuid: diagram.uuid,
            version: diagram.version,
            tier: diagram.tier,
            projectUuid: diagram.projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: diagram.sessionUuid,
            promptUuid: diagram.promptUuid,
            code: diagram.code,
            name: diagram.name,
            description: diagram.description,
            gmccDiagramPath: diagram.gmccDiagramPath,
            dopeScopeCode: diagram.dopeScopeCode,
            revision: diagram.revision,
            visibility: diagram.visibility,
            createdAt: diagram.createdAt,
            updatedAt: diagram.updatedAt
        )
    }
}
